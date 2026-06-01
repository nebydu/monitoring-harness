#!/usr/bin/env bash
# codex-gate-core.sh — Codex gate Stop hook 공통 골격 (H2 prototype)
#
# 이 파일은 세 repo(hub/script-agent/monitoring-meta)의 codex-gate.sh에서 "동일한 실행 로직"만
# 추출한 공통 골격이다. 도메인 delta(트리거/스킵 경로, 프롬프트, 스킵 메시지 등)는 하드코딩하지 않고
# 아래 주입점(환경변수/배열)으로만 받는다. plugin은 도메인 결정을 하지 않는다.
#
# 사용법: consumer의 얇은 wrapper가 (1) delta 값을 정의(또는 profile을 source)한 뒤 (2) 이 파일을
#         source 한다. wrapper 예시는 codex-gate.wrapper.example.sh, 값 예시는 profiles/ 참고.
#
# ── 주입점 (consumer/profile이 제공) ──────────────────────────────────────
#   CODEX_GATE_TRIGGER_GLOBS  (배열, 필수)  Codex 검증을 발동시키는 변경 경로 glob
#   CODEX_GATE_SKIP_GLOBS     (배열, 선택)  발동에서 제외할 경로 glob (스킵이 트리거보다 우선)
#   CODEX_GATE_PROMPT         (문자열, 필수) Codex에 줄 리뷰 지시문 (도메인 전체)
#   CODEX_GATE_SKIP_MSG       (문자열, 선택) 코드 변경이 없을 때 출력할 안내 메시지
# ── 주입점 (선택, 기본값 있음) ────────────────────────────────────────────
#   CODEX_GATE_SCHEMA         (경로)  output-schema. 기본 "$CLAUDE_DIR/codex-schema.json"
#   CODEX_GATE_DATA_DIR       (경로)  state/log 보존 위치. 기본 "$CLAUDE_DIR"
#                                     (plugin 모델에서는 ${CLAUDE_PLUGIN_DATA} 권장)
#   CODEX_GATE_FAIL_LIMIT     (정수)  fail 연속 허용 횟수. 기본 3 (초과 시 escalate)
#   CODEX_GATE_PARSE_FAIL_LIMIT (정수) parse 실패 연속 허용 횟수. 기본 2 (도달 시 escalate)
set -euo pipefail

# ── 경로 ────────────────────────────────────────────────────────────────
REPO_ROOT="$(git rev-parse --show-toplevel)"
CLAUDE_DIR="$REPO_ROOT/.claude"
DATA_DIR="${CODEX_GATE_DATA_DIR:-$CLAUDE_DIR}"
STATE_FILE="$DATA_DIR/.codex-gate-state"
LOG_FILE="$DATA_DIR/codex-gate.log"
ESC_LOG="$DATA_DIR/codex-gate-escalation.log"
SCHEMA="${CODEX_GATE_SCHEMA:-$CLAUDE_DIR/codex-schema.json}"
LAST_MSG="$DATA_DIR/.codex-last-message.json"
ISSUES_FILE="$DATA_DIR/.codex-gate-issues.txt"
CODEX_ERR="$DATA_DIR/.codex-gate-stderr.txt"

# empty tree object hash — 아직 커밋이 없을 때(HEAD 부재) diff 비교 기준
EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"

FAIL_LIMIT="${CODEX_GATE_FAIL_LIMIT:-3}"
PARSE_FAIL_LIMIT="${CODEX_GATE_PARSE_FAIL_LIMIT:-2}"

# ── 주입점 검증 ───────────────────────────────────────────────────────────
# 공통부는 도메인 값을 모른다. 필수 주입점이 비면 게이트를 임의 통과시키지 않고 명확히 실패한다.
# (+x 존재 검사를 먼저 해서 set -u에서 미설정 배열 접근으로 죽지 않게 단락 평가한다)
if [ -z "${CODEX_GATE_TRIGGER_GLOBS+x}" ] || [ "${#CODEX_GATE_TRIGGER_GLOBS[@]}" -eq 0 ]; then
  echo "[codex-gate] 구성 오류: CODEX_GATE_TRIGGER_GLOBS 미주입 (consumer profile 누락)" >&2
  exit 2
fi
if [ -z "${CODEX_GATE_PROMPT:-}" ]; then
  echo "[codex-gate] 구성 오류: CODEX_GATE_PROMPT 미주입 (consumer profile 누락)" >&2
  exit 2
fi

# ── 유틸 ────────────────────────────────────────────────────────────────
log_line() { # verdict | crit_count | viol_count | triggered_files
  printf '%s | %s | %s | %s | %s\n' "$(date -Is)" "$1" "$2" "$3" "$4" >> "$LOG_FILE"
}
emit_system_message() { # message
  # PYTHONIOENCODING=utf-8: Windows 기본 콘솔 인코딩(cp949)에서 em dash 등 non-CP949 문자를
  # stdout에 쓸 때 UnicodeEncodeError가 나는 것을 막는다.
  PYTHONIOENCODING=utf-8 python -c 'import json, sys; print(json.dumps({"systemMessage": sys.argv[1]}, ensure_ascii=False))' "$1"
}
escalate() { # message
  printf '%s | %s\n' "$(date -Is)" "$1" >> "$ESC_LOG"
  emit_system_message "[codex-gate] 게이트 강제 통과 — 사람 확인 필요: $1"
}
read_state() {
  FAIL_COUNT=0; PARSE_FAIL_COUNT=0
  if [ -f "$STATE_FILE" ]; then
    read -r FAIL_COUNT PARSE_FAIL_COUNT < "$STATE_FILE" || true
  fi
  FAIL_COUNT=${FAIL_COUNT:-0}
  PARSE_FAIL_COUNT=${PARSE_FAIL_COUNT:-0}
}
write_state() { printf '%s %s\n' "$FAIL_COUNT" "$PARSE_FAIL_COUNT" > "$STATE_FILE"; }
reset_state() { FAIL_COUNT=0; PARSE_FAIL_COUNT=0; write_state; }

# glob 목록 중 하나라도 매칭되면 0 — case 패턴(`*`가 `/`도 매칭)으로 기존 동작과 동일
match_any() { # file, glob...
  local f="$1"; shift
  local g
  for g in "$@"; do
    # shellcheck disable=SC2254
    case "$f" in $g) return 0 ;; esac
  done
  return 1
}

# ── 1) 무한 Stop 루프 가드 ───────────────────────────────────────────────
INPUT="$(cat)"
STOP_ACTIVE="$(printf '%s' "$INPUT" | python -c '
import sys, json
try:
    d = json.loads(sys.stdin.read())
    print("1" if d.get("stop_hook_active") else "0")
except Exception:
    print("0")
' 2>/dev/null || echo "0")"
[ "$STOP_ACTIVE" = "1" ] && exit 0

read_state

# ── 2) 트리거 가드 — 도메인 코드 변경이 있을 때만 Codex 호출 ───────────────
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  BASE="HEAD"
else
  BASE="$EMPTY_TREE"
fi

CHANGED="$( { git -c core.quotepath=false diff --name-only "$BASE"; \
              git -c core.quotepath=false ls-files --others --exclude-standard; } | sort -u )"

SKIP_GLOBS=( "${CODEX_GATE_SKIP_GLOBS[@]:-}" )
TRIGGERED=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # 스킵 glob 우선: 매칭되면 트리거에서 제외 (예: .claude/, docs/, analysis/)
  if [ "${#SKIP_GLOBS[@]}" -gt 0 ] && match_any "$f" "${SKIP_GLOBS[@]}"; then
    continue
  fi
  if match_any "$f" "${CODEX_GATE_TRIGGER_GLOBS[@]}"; then
    TRIGGERED="${TRIGGERED}${f}"$'\n'
  fi
done <<EOF
$CHANGED
EOF

# pipefail+set -e 환경: TRIGGERED가 비면 grep이 exit 1을 내므로 || true로 방어
TRIG_CSV="$(printf '%s' "$TRIGGERED" | grep -v '^$' | tr '\n' ',' | sed 's/,$//' || true)"

if [ -z "$TRIG_CSV" ]; then
  # 트리거 대상이 아닌 변경만 있음 → 매번 검토 비용 크므로 스킵
  log_line "skipped" 0 0 "(no code change)"
  emit_system_message "${CODEX_GATE_SKIP_MSG:-[codex-gate] SKIP: 트리거 대상 코드 변경이 없어 Codex 검증을 건너뜁니다.}"
  exit 0
fi

# ── 3) 검토 입력 구성 (추적 변경 diff + 미추적 신규 코드 파일 내용) ────────
REVIEW_INPUT="$(git -c core.quotepath=false diff "$BASE")"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    # 미추적 파일은 diff에 안 잡히므로 내용을 직접 합류
    REVIEW_INPUT="${REVIEW_INPUT}
--- NEW FILE: ${f} ---
$(cat "$REPO_ROOT/$f" 2>/dev/null)"
  fi
done <<EOF
$TRIGGERED
EOF

# ── 4) Codex 호출 (fallback: codex exec, read-only) ──────────────────────
rm -f "$LAST_MSG" "$ISSUES_FILE"
set +e
printf '%s' "$REVIEW_INPUT" | codex exec --sandbox read-only \
  --output-schema "$SCHEMA" \
  -o "$LAST_MSG" \
  "$CODEX_GATE_PROMPT" >/dev/null 2>"$CODEX_ERR"
set -e

# ── 5) 결과 파싱 (python) ────────────────────────────────────────────────
set +e
PARSE_OUT="$(python -c '
import sys, json
last_msg, issues_path = sys.argv[1], sys.argv[2]
try:
    with open(last_msg, "r", encoding="utf-8") as fp:
        d = json.load(fp)
    verdict = str(d.get("verdict", "")).strip()
    crit = d.get("critical_issues") or []
    viol = d.get("spec_violations") or []
    if verdict not in ("pass", "fail"):
        raise ValueError("invalid verdict: %r" % verdict)
    with open(issues_path, "w", encoding="utf-8") as g:
        for c in crit:
            g.write("[critical] " + str(c) + "\n")
        for v in viol:
            g.write("[spec] " + str(v) + "\n")
    sys.stdout.write("%s\t%d\t%d" % (verdict, len(crit), len(viol)))
except Exception as e:
    sys.stderr.write(str(e))
    sys.exit(3)
' "$LAST_MSG" "$ISSUES_FILE" 2>/dev/null)"
PARSE_RC=$?
set -e

# ── 5a) 파싱 실패 ────────────────────────────────────────────────────────
if [ "$PARSE_RC" -ne 0 ] || [ -z "$PARSE_OUT" ]; then
  PARSE_FAIL_COUNT=$((PARSE_FAIL_COUNT + 1))
  if [ "$PARSE_FAIL_COUNT" -ge "$PARSE_FAIL_LIMIT" ]; then
    escalate "Codex 응답 파싱 ${PARSE_FAIL_LIMIT}회 연속 실패 — 사람 확인 필요 (triggered: $TRIG_CSV)"
    log_line "parse_error(escalated)" 0 0 "$TRIG_CSV"
    reset_state
    exit 0
  fi
  write_state
  log_line "parse_error" 0 0 "$TRIG_CSV"
  {
    echo "[codex-gate] Codex 응답 파싱 실패. 원본 출력 앞 200자:"
    head -c 200 "$LAST_MSG" 2>/dev/null || true
    head -c 200 "$CODEX_ERR" 2>/dev/null || true
    echo ""
  } >&2
  exit 2
fi

VERDICT="$(printf '%s' "$PARSE_OUT" | cut -f1)"
CRIT_COUNT="$(printf '%s' "$PARSE_OUT" | cut -f2)"
VIOL_COUNT="$(printf '%s' "$PARSE_OUT" | cut -f3)"

# ── 5b) verdict == pass ──────────────────────────────────────────────────
if [ "$VERDICT" = "pass" ]; then
  log_line "pass" "$CRIT_COUNT" "$VIOL_COUNT" "$TRIG_CSV"
  reset_state
  emit_system_message "[codex-gate] PASS: Codex 검증 완료. blocking issue 없음, 수정사항 없음. 대상: $TRIG_CSV"
  exit 0
fi

# ── 5c) verdict == fail ──────────────────────────────────────────────────
PARSE_FAIL_COUNT=0   # 파싱은 성공했으므로 연속 파싱 실패 카운터 리셋
FAIL_COUNT=$((FAIL_COUNT + 1))
if [ "$FAIL_COUNT" -gt "$FAIL_LIMIT" ]; then
  escalate "Codex 검증 fail ${FAIL_LIMIT}회 초과 — 사람 확인 필요 (triggered: $TRIG_CSV)"
  log_line "fail(escalated)" "$CRIT_COUNT" "$VIOL_COUNT" "$TRIG_CSV"
  reset_state
  exit 0
fi
write_state
log_line "fail" "$CRIT_COUNT" "$VIOL_COUNT" "$TRIG_CSV"
{
  echo "[codex-gate] Codex 검증 FAIL — 종료 보류. 아래 항목을 해소한 뒤 다시 종료하십시오:"
  cat "$ISSUES_FILE" 2>/dev/null
} >&2
exit 2
