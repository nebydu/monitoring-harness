#!/usr/bin/env bash
# codex-gate-core.sh — Codex gate Stop hook 공통 골격
#
# 이 파일은 consumer repo들의 codex-gate에서 "동일한 실행 로직"만 추출한 공통 골격이다.
# 도메인 delta(트리거/스킵 경로, 프롬프트, 스킵 메시지 등)는 하드코딩하지 않고
# 아래 주입점(환경변수/배열)으로만 받는다. plugin은 도메인 결정을 하지 않는다.
#
# 사용법: consumer의 얇은 wrapper가 (1) delta 값을 정의(또는 profile을 source)한 뒤 (2) 이 파일을
#         source 한다. wrapper 예시는 codex-gate.wrapper.example.sh, 값 예시는 profiles/ 참고.
#
# 검증 윈도우(2026-06-11 사각지대 보완 — meta reference 이식):
#   종전 BASE=HEAD는 미커밋 변경만 봐서 같은 턴에 커밋하면 게이트가 우회됐다. 이제 상태 파일의
#   verified_commit(vc, 마지막 검증 commit) 기준으로 "커밋분 + 작업 트리 + 미추적"을 모두 윈도우에
#   포함한다. 전진 규칙: 윈도우가 BASE..HEAD 전 구간을 커버했고 검증이 실제로 완료(skip=트리거 0
#   확인 / pass)됐을 때만 vc를 HEAD로 전진한다.
#   escalated(강제 통과)는 전진하지 않는다 — 미검증 내용이 baseline로 흡수되는 것 차단. 같은 diff의
#   재방문은 gate_key 캐시(already_force_passed)가 막으므로 deadlock 없음. 해소=수정 또는 state 삭제.
#   단절 이력(vc가 HEAD와 공통 조상 없음)과 기준 없음(vc·baseline ref 공통 조상 모두 부재)은
#   fail-closed — 게이트가 종료를 차단한다(exit 2). 통과 가능한 BASE는 vc/merge-base/
#   bootstrap-origin/bootstrap-origin-mb(diverged branch는 baseline ref와의 공통 조상)/empty-tree 5종뿐.
#   해소 = 사람이 해당 커밋 구간을 직접 검증 완료한 뒤 verified_commit 갱신, 또는 push로 baseline
#   ref 생성(state 삭제 시에도 origin이 있으면 bootstrap이 미push 커밋을 포함해 재검증).
#   차단 이벤트는 BLOCK_LOG에 기록한다(escalation 로그와 분리 — 강제 통과와 차단은 다른 사건).
#
# 상태 파일(.codex-gate-state)은 JSON이다. 두 축을 분리해 기록한다:
#   cache_status = "이 gate_key(diff 에피소드)의 캐시 상태" 축 (passed/escalated 재사용 판단 전용)
#   last_result  = "마지막 hook 결과" 축 — 상태 파일을 소비하는 자동화는 반드시 이것을 읽는다.
#   구버전 평문 state("FAIL PARSE" 두 정수)는 읽기 시 카운터를 승계하고 다음 기록에서 JSON으로 전환된다.
#
# ── 주입점 (consumer/profile이 제공) ──────────────────────────────────────
#   CODEX_GATE_TRIGGER_GLOBS  (배열, 필수)  Codex 검증을 발동시키는 변경 경로 glob
#   CODEX_GATE_SKIP_GLOBS     (배열, 선택)  발동에서 제외할 경로 glob (스킵이 트리거보다 우선)
#   CODEX_GATE_PROMPT         (문자열, 필수) Codex에 줄 리뷰 지시문 (도메인 전체)
#   CODEX_GATE_SKIP_MSG       (문자열, 선택) 코드 변경이 없을 때 출력할 안내 메시지
# ── 주입점 (선택, 기본값 있음) ────────────────────────────────────────────
#   CODEX_GATE_SCHEMA         (경로)  output-schema. 기본 "$CLAUDE_DIR/codex-schema.json"
#   CODEX_GATE_DATA_DIR       (경로)  state/log 보존 위치. 기본 "$CLAUDE_DIR"
#                                     (plugin 모델에서는 ${CLAUDE_PLUGIN_DATA} 권장. 주입 시
#                                      repo별 하위 디렉터리 <data>/<repo명>-<경로 hash8>/로 자동
#                                      분리하고 .repo-path 메타데이터로 소유권 충돌을 감지)
#   CODEX_GATE_FAIL_LIMIT     (정수)  fail 연속 허용 횟수. 기본 3 (도달 시 escalate)
#   CODEX_GATE_PARSE_FAIL_LIMIT (정수) parse 실패 연속 허용 횟수. 기본 2 (도달 시 escalate)
#   CODEX_GATE_BASELINE_REF   (ref)   부트스트랩 신뢰 기준 ref. 기본 "origin/main"
#                                     (push된 이력 = 사람이 publish한 신뢰 기준 — 설계 결정 사항)
set -euo pipefail

# ── 1) 무한 Stop 루프 가드 — 모든 exit 2 경로보다 먼저 판정한다 ──────────
# 주입점 검증·data dir 충돌 등 구성 오류는 exit 2(차단)다. 가드가 그 뒤에 있으면 오설정 시
# stop_hook_active=true에서도 매번 차단되어 무한 stop 루프가 된다(2026-06-11 proposal-review 보완).
# 오설정은 첫 stop(active=false)에서 exit 2로 반드시 한 번 노출된 뒤, 재발화에서는 종료를 허용한다.
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

# ── 경로 ────────────────────────────────────────────────────────────────
REPO_ROOT="$(git rev-parse --show-toplevel)"
CLAUDE_DIR="$REPO_ROOT/.claude"
# data dir 주입(plugin 모델의 ${CLAUDE_PLUGIN_DATA}) 시 repo별 하위 디렉터리로 분리한다.
# 이유: plugin data dir은 모든 소비 repo가 공유하는 단일 경로다 — verified_commit은 repo별 상태라
# 미분리 시 한 repo의 vc가 다른 repo에서 "단절 이력"으로 오차단된다.
# 키 = <repo명>-<repo 절대경로 sha256 앞 8자> — basename만 쓰면 같은 이름의 다른 repo가 state를
# 공유해 동일 오차단이 재발한다. 구 레이아웃(<repo명>/ 또는 flat)은 소유권을 검증할 수 없어
# 승계하지 않는다(fresh bootstrap — vc 공백은 baseline ref 부트스트랩이 안전하게 재검증).
# 미주입(repo-local $CLAUDE_DIR) 시에는 이미 repo 단위라 분리하지 않는다.
if [ -n "${CODEX_GATE_DATA_DIR:-}" ]; then
  REPO_HASH8="$(printf '%s' "$REPO_ROOT" | python -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:8])')"
  DATA_DIR="${CODEX_GATE_DATA_DIR}/$(basename "$REPO_ROOT")-${REPO_HASH8}"
  mkdir -p "$DATA_DIR"
  # 소유권 메타데이터 — hash8 충돌(사실상 다른 repo가 같은 키로 매핑) 감지용. state 오공유는
  # vc 오차단/오허용 둘 다 가능하므로 불일치 시 fail-closed로 차단한다(가드 뒤라 루프 안전).
  REPO_META="$DATA_DIR/.repo-path"
  if [ -f "$REPO_META" ] && [ "$(cat "$REPO_META")" != "$REPO_ROOT" ]; then
    echo "[codex-gate] 구성 오류: data dir 소유권 충돌 — '$DATA_DIR'는 '$(cat "$REPO_META")' 소유인데 현재 repo는 '$REPO_ROOT'입니다. 두 repo의 CODEX_GATE_DATA_DIR를 분리하세요." >&2
    exit 2
  fi
  [ -f "$REPO_META" ] || printf '%s' "$REPO_ROOT" > "$REPO_META"
else
  DATA_DIR="$CLAUDE_DIR"
  mkdir -p "$DATA_DIR"
fi
STATE_FILE="$DATA_DIR/.codex-gate-state"
LOG_FILE="$DATA_DIR/codex-gate.log"
ESC_LOG="$DATA_DIR/codex-gate-escalation.log"
BLOCK_LOG="$DATA_DIR/codex-gate-block.log"   # fail-closed 차단(단절·기준 없음) 전용 — 강제 통과(ESC_LOG)와 분리
SCHEMA="${CODEX_GATE_SCHEMA:-$CLAUDE_DIR/codex-schema.json}"
LAST_MSG="$DATA_DIR/.codex-last-message.json"
ISSUES_FILE="$DATA_DIR/.codex-gate-issues.txt"
CODEX_ERR="$DATA_DIR/.codex-gate-stderr.txt"

# empty tree object hash — 아직 커밋이 없을 때(HEAD 부재) diff 비교 기준
EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"

FAIL_LIMIT="${CODEX_GATE_FAIL_LIMIT:-3}"
PARSE_FAIL_LIMIT="${CODEX_GATE_PARSE_FAIL_LIMIT:-2}"
BASELINE_REF="${CODEX_GATE_BASELINE_REF:-origin/main}"

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
now_iso() { date +%Y-%m-%dT%H:%M:%S%z; }   # date -Is 대체 — MSYS/Git Bash 버전별 -I 지원 차이 방어
log_line() { # verdict | crit_count | viol_count | triggered_files
  printf '%s | %s | %s | %s | %s\n' "$(now_iso)" "$1" "$2" "$3" "$4" >> "$LOG_FILE"
}
emit_system_message() { # message
  # PYTHONIOENCODING=utf-8: Windows 기본 콘솔 인코딩(cp949)에서 em dash 등 non-CP949 문자를
  # stdout에 쓸 때 UnicodeEncodeError가 나는 것을 막는다.
  PYTHONIOENCODING=utf-8 python -c 'import json, sys; print(json.dumps({"systemMessage": sys.argv[1]}, ensure_ascii=False))' "$1"
}
escalate() { # message
  printf '%s | %s\n' "$(now_iso)" "$1" >> "$ESC_LOG"
  # force-pass는 검증을 건너뛴 사건 → SKIP/PASS보다 더 잘 보여야 하므로 systemMessage로 노출
  emit_system_message "[codex-gate] 게이트 강제 통과 — 사람 확인 필요: $1"
}
read_state() { # gate_key triggered_key
  STATE_STATUS="new"; FAIL_COUNT=0; PARSE_FAIL_COUNT=0
  if [ ! -f "$STATE_FILE" ]; then
    return 0
  fi
  # 캐시(passed/escalated 재사용)는 gate_key(=내용+prompt+schema+hook) 완전 일치 시에만 적용한다.
  # fail streak(연속 실패 카운트)은 triggered(파일 집합) 일치 시 승계한다 — diff가 바뀌어도 같은 파일을
  # 계속 고치며 실패하면 카운트가 누적되어 escalation에 실제로 도달한다(diff마다 리셋되면 무력).
  # 구버전 평문 state("FAIL PARSE")는 카운터만 1회 승계한다(구 형식에 키가 없어 무조건 승계).
  STATE_OUT="$(python -c '
import json, sys
path, gate_key, trig = sys.argv[1], sys.argv[2], sys.argv[3]
status, fail, parse = "new", 0, 0
try:
    with open(path, "r", encoding="utf-8") as fp:
        raw = fp.read()
    try:
        d = json.loads(raw)
        if d.get("gate_key") == gate_key:
            # cache_status = 에피소드 캐시 축(구버전 필드명 status에서 개명 — 하위 호환 폴백 유지)
            status = str(d.get("cache_status") or d.get("status") or "new")
        if d.get("triggered") == trig:
            fail = int(d.get("fail_count") or 0)
            parse = int(d.get("parse_fail_count") or 0)
    except ValueError:
        # 구버전 평문 마이그레이션 — "FAIL PARSE" 두 정수
        parts = raw.split()
        if len(parts) >= 2:
            fail, parse = int(parts[0]), int(parts[1])
    sys.stdout.write(f"{status}\t{fail}\t{parse}")
except Exception:
    sys.stdout.write("new\t0\t0")
' "$STATE_FILE" "$1" "$2" 2>/dev/null || printf 'new\t0\t0')"
  STATE_STATUS="$(printf '%s' "$STATE_OUT" | cut -f1)"
  FAIL_COUNT="$(printf '%s' "$STATE_OUT" | cut -f2)"
  PARSE_FAIL_COUNT="$(printf '%s' "$STATE_OUT" | cut -f3)"
  FAIL_COUNT=${FAIL_COUNT:-0}
  PARSE_FAIL_COUNT=${PARSE_FAIL_COUNT:-0}
}
write_state() { # status [new_verified_commit]
  # vc 전진을 같은 1회 기록에 포함(원자성) — 인자 생략/빈 값이면 기존 vc 보존.
  python -c '
import json, sys
path, status, gate_key, diff_hash, triggered, fail, parse, updated_at, new_vc = sys.argv[1:10]
old = {}
try:
    with open(path, "r", encoding="utf-8") as fp:
        old = json.load(fp)
except Exception:
    pass
# cache_status = "이 gate_key(diff 에피소드)의 캐시 상태" 축. 마지막 hook 결과 축은 last_result.
data = {
    "gate_key": gate_key,
    "triggered": triggered,
    "diff_hash": diff_hash,
    "fail_count": int(fail),
    "parse_fail_count": int(parse),
    "cache_status": status,
    "updated_at": updated_at,
}
vc = new_vc or str(old.get("verified_commit") or "")
if vc:
    data["verified_commit"] = vc
    data["vc_updated_at"] = updated_at if new_vc else str(old.get("vc_updated_at") or "")
# last_result = "마지막 hook 결과" 단일 축 — skip(update_verified_commit)과 에피소드 status를 통합 표기.
# 상태 파일을 소비하는 자동화는 반드시 last_result를 기준으로 읽는다(status/gate_key는 캐시 축 — 최신 결과 아님).
data["last_result"] = status
with open(path, "w", encoding="utf-8") as fp:
    json.dump(data, fp, ensure_ascii=False, indent=2)
    fp.write("\n")
' "$STATE_FILE" "$1" "$GATE_KEY" "$DIFF_HASH" "$TRIG_CSV" "$FAIL_COUNT" "$PARSE_FAIL_COUNT" "$(now_iso)" "${2:-}"
}
update_verified_commit() { # commit base_info — skip 경로 전용 state 갱신
  # 캐시 축 필드(gate_key/diff_hash/triggered/fail_count/cache_status)는 보존하고, vc·last_skip_*·
  # last_result를 갱신한다. 구버전 필드명 status는 cache_status로 1회 마이그레이션한다.
  # last_skip_*/last_result는 캐시 축과 독립 — 운영자·자동화는 "마지막 hook 결과"를 last_result로 읽는다.
  [ -z "${1:-}" ] && return 0
  python -c '
import json, sys
path, commit, base_info, updated_at = sys.argv[1:5]
data = {}
try:
    with open(path, "r", encoding="utf-8") as fp:
        data = json.load(fp)
except Exception:
    data = {}
# 구버전(필드명 status) state 마이그레이션 — 캐시 의미 보존 후 개명
if "status" in data and "cache_status" not in data:
    data["cache_status"] = data.pop("status")
data["verified_commit"] = commit
data["vc_updated_at"] = updated_at
data["last_skip_at"] = updated_at
data["last_skip_base_info"] = base_info
data["last_result"] = "skipped"
# baseline이 전진하면 이전 에피소드의 fail streak은 사라진 변경분에 대한 것 — 리셋해 새 에피소드
# 오염 방지(잔존 streak이 이후 무관한 변경의 조기 escalation을 유발하는 edge 차단).
# gate_key/cache_status는 보존 — 동일 diff 재등장 시 캐시 의미가 그대로 유효하다.
data["fail_count"] = 0
data["parse_fail_count"] = 0
with open(path, "w", encoding="utf-8") as fp:
    json.dump(data, fp, ensure_ascii=False, indent=2)
    fp.write("\n")
' "$STATE_FILE" "$1" "${2:-}" "$(now_iso)"
}
log_target() {
  # cache_status = 에피소드 캐시 축 — "마지막 hook 결과"(last_result)와 다름을 로그 명칭으로 구분
  printf '%s | key=%s | cache_status=%s' "$TRIG_CSV" "$GATE_KEY" "${STATE_STATUS:-new}"
}

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

# ── 2) 검증 윈도우 BASE 결정 ─────────────────────────────────────────────
# BASE 결정이 트리거 가드보다 먼저다: 단절/기준 없음 상태에서는 커밋분의 트리거 변경 여부 자체를
# 열거할 수 없으므로, 트리거 유무와 무관하게 fail-closed 차단이 유일하게 안전하다.
# (트리거 가드는 BASE가 신뢰 가능한 경우에만 의미가 있다.)
CUR_HEAD=""
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  CUR_HEAD="$(git rev-parse HEAD)"
fi
VERIFIED_COMMIT="$(python -c '
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as fp:
        print(str(json.load(fp).get("verified_commit") or ""))
except Exception:
    print("")
' "$STATE_FILE" 2>/dev/null || echo "")"

BASE_KIND=""       # 통과 가능: vc | merge-base | bootstrap-origin | bootstrap-origin-mb | empty-tree / 차단: disconnected | no-baseline
VC_ADVANCE_OK=1    # 이번 윈도우가 BASE..HEAD 전 구간을 커버 → skip/pass 시 vc 전진 허용
if [ -z "$CUR_HEAD" ]; then
  BASE="$EMPTY_TREE"; BASE_KIND="empty-tree"; VC_ADVANCE_OK=0
elif [ -z "$VERIFIED_COMMIT" ]; then
  # 부트스트랩 — baseline ref가 HEAD의 조상이면 그것을 기준으로(미push 커밋 = 미검증 가능 구간을
  # 첫 실행 윈도우에 포함 — "직전에 커밋된 변경이 부트스트랩으로 흡수"되는 사각지대 차단).
  # baseline ref가 없거나 공통 조상이 없으면 fail-closed(no-baseline).
  BASELINE_HASH="$(git rev-parse --verify -q "$BASELINE_REF" 2>/dev/null || true)"
  if [ -n "$BASELINE_HASH" ] && git merge-base --is-ancestor "$BASELINE_HASH" "$CUR_HEAD" 2>/dev/null; then
    BASE="$BASELINE_HASH"; BASE_KIND="bootstrap-origin"
  elif [ -n "$BASELINE_HASH" ] && MB_BOOT="$(git merge-base "$BASELINE_HASH" "$CUR_HEAD" 2>/dev/null)" && [ -n "$MB_BOOT" ]; then
    # baseline ref가 조상은 아니지만 공통 조상이 있는 경우(diverged feature branch) — 공통 조상부터
    # 부트스트랩(조상 강제 시 일반 feature branch에서 영구 차단됨)
    BASE="$MB_BOOT"; BASE_KIND="bootstrap-origin-mb"
  else
    # 기준(vc·baseline ref 공통 조상) 없음 — 커밋 이력을 검증할 방법이 없으므로 단절 이력과 동일하게
    # fail-closed로 차단한다("작업 트리만 검사 후 통과"는 state 삭제/신규 repo에서 커밋된 트리거
    # 변경의 우회 경로였음). 통과 가능한 BASE는 머리 주석의 5종으로 고정.
    NO_BASELINE_MSG="검증 기준 없음(verified_commit·${BASELINE_REF} 공통 조상 부재) — 커밋 이력 검증 불가(강제 통과 아님). 해소: push로 ${BASELINE_REF} 생성(=push된 이력을 신뢰 기준으로 채택), 또는 사람이 전체 커밋 이력의 트리거 변경을 직접 검증 완료한 경우에만 상태 파일($STATE_FILE)에 verified_commit을 현재 HEAD($(printf '%s' "$CUR_HEAD" | cut -c1-12))로 기록(이 기록 자체가 '사람이 이 구간을 검증했다'는 선언이며, 검증 없이 기록하면 baseline이 미검증 이력을 흡수한다)하고 검증 사유를 codex-gate-block.log에 한 줄 남길 것"
    printf '%s | BLOCK(기준 없음) | %s\n' "$(now_iso)" "$NO_BASELINE_MSG" >> "$BLOCK_LOG"
    log_line "blocked(no-baseline)" 0 0 "base=no-baseline head=$(printf '%s' "$CUR_HEAD" | cut -c1-12)"
    emit_system_message "[codex-gate] BLOCK(기준 없음): $NO_BASELINE_MSG"
    {
      echo "[codex-gate] BLOCK(기준 없음) — 종료 보류: $NO_BASELINE_MSG"
    } >&2
    exit 2
  fi
elif git merge-base --is-ancestor "$VERIFIED_COMMIT" "$CUR_HEAD" 2>/dev/null; then
  BASE="$VERIFIED_COMMIT"; BASE_KIND="vc"
else
  # rebase·amend로 vc가 조상이 아님 → 공통 조상부터 보수적 확대 윈도우
  MB="$(git merge-base "$VERIFIED_COMMIT" "$CUR_HEAD" 2>/dev/null || true)"
  if [ -n "$MB" ]; then
    # 정책(고정): merge-base 윈도우는 HEAD의 신규 이력 전체(merge-base..HEAD + 작업 트리)를 커버하므로
    # 검증 완료(pass / 트리거 0 skip) 시 vc 전진을 허용한다. rebase 전 옛 이력은 HEAD에서 도달
    # 불가능하므로 윈도우 커버리지와 무관하다.
    # INFO는 별도 emit하지 않고 최종 결과 메시지에 합친다 — Stop hook stdout은 단일 JSON 기대.
    BASE="$MB"; BASE_KIND="merge-base"
  else
    # 단절 이력 — vc..HEAD 커밋분을 열거·검증할 수 없다(merge-base 부재). 부분 검사 후 SKIP/PASS를
    # 내보내면 "통과처럼 동작"하므로 fail-closed로 게이트를 차단한다.
    # 해소책은 verified_commit 수동 갱신 단일 경로 — state 삭제는 origin 없는 환경에서 부트스트랩
    # 미검증 경로로 빠져 fail-closed 약속을 깨므로 안내하지 않는다.
    DISCONNECT_MSG="verified_commit($(printf '%s' "$VERIFIED_COMMIT" | cut -c1-12))가 HEAD($(printf '%s' "$CUR_HEAD" | cut -c1-12))와 단절 — 커밋분 검증 불가(강제 통과 아님). 해소: 사람이 해당 커밋 구간의 트리거 변경을 직접 검증 완료한 경우에만 상태 파일($STATE_FILE)의 verified_commit을 현재 HEAD로 갱신하고, 검증 사유를 codex-gate-block.log에 한 줄 남길 것"
    printf '%s | BLOCK(단절) | %s\n' "$(now_iso)" "$DISCONNECT_MSG" >> "$BLOCK_LOG"
    log_line "blocked(disconnected)" 0 0 "base=disconnected head=$(printf '%s' "$CUR_HEAD" | cut -c1-12)"
    # stderr(차단 채널 — 기존 FAIL 흐름과 동일)와 systemMessage(structured 소비자용)를 병행 발신
    emit_system_message "[codex-gate] BLOCK(단절 이력): $DISCONNECT_MSG"
    {
      echo "[codex-gate] BLOCK(단절 이력) — 종료 보류: $DISCONNECT_MSG"
    } >&2
    exit 2
  fi
fi
BASE_INFO="base=${BASE_KIND}:$(printf '%s' "$BASE" | cut -c1-12) head=$(printf '%s' "${CUR_HEAD:-(none)}" | cut -c1-12) vc_advance=$VC_ADVANCE_OK"
# 모드별 정보 주석 — 최종 결과 메시지에 합쳐 단일 systemMessage 유지(stdout JSON 1개).
# 단절 이력·기준 없음은 위에서 fail-closed로 차단되어 여기 안 온다.
MERGE_NOTE=""
[ "$BASE_KIND" = "merge-base" ] && MERGE_NOTE=" (rebase/amend 감지 — 공통 조상부터 확대 재검증함)"
[ "$BASE_KIND" = "bootstrap-origin" ] && MERGE_NOTE=" (부트스트랩 — ${BASELINE_REF} 이전 이력은 push된 신뢰 기준으로 간주)"
[ "$BASE_KIND" = "bootstrap-origin-mb" ] && MERGE_NOTE=" (부트스트랩 — ${BASELINE_REF}과의 공통 조상 이전 이력은 push된 신뢰 기준으로 간주)"
# pass 시 write_state에 넘길 vc 전진 값(윈도우 미커버 시 빈 값 = 보존).
# escalated는 검증 미완이므로 항상 빈 값 — 머리 주석의 전진 규칙 참조.
# REVIEW_INPUT(§4)도 같은 $BASE로 diff를 만들므로, 전진 조건과 Codex가 실제로 검토한 범위는
# 구조적으로 동일 윈도우다(전진 조건↔리뷰 범위 결합).
ADVANCE_VC=""
[ "$VC_ADVANCE_OK" = "1" ] && ADVANCE_VC="$CUR_HEAD"

# ── 3) 트리거 가드 — 윈도우(커밋분+작업 트리+미추적)에 도메인 변경이 있을 때만 Codex 호출 ──
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
TRIG_CSV="$(printf '%s' "$TRIGGERED" | grep -v '^$' | sort -u | tr '\n' ',' | sed 's/,$//' || true)"

if [ -z "$TRIG_CSV" ]; then
  # 트리거 대상이 아닌 변경만 있음 → 매번 검토 비용 크므로 스킵.
  # BASE..HEAD+작업트리에 트리거 파일 없음이 확인된 윈도우(조상 BASE)에서만 vc 전진.
  # 의도적으로 vc만 갱신(cache_status/gate_key 미기록): skip에서 full write_state를 하면 gate_key가
  # 비어 직전 passed/escalated 캐시가 파괴된다. vc(baseline 축)와 캐시 축은 독립 축.
  if [ "$VC_ADVANCE_OK" = "1" ]; then
    update_verified_commit "$CUR_HEAD" "$BASE_INFO"
  fi
  log_line "skipped" 0 0 "(no gate-triggering change) | $BASE_INFO | cache_status=preserved"
  emit_system_message "${CODEX_GATE_SKIP_MSG:-[codex-gate] SKIP: 트리거 대상 코드 변경이 없어 Codex 검증을 건너뜁니다.} ($BASE_INFO)$MERGE_NOTE"
  exit 0
fi

# ── 4) 검토 입력 구성 (트리거 파일 diff + 미추적 신규 파일 내용) ──────────
# 트리거 파일만 합류한다 — gate_key(diff_hash)가 비트리거 변경에 흔들리지 않게 하고,
# 전진 조건과 리뷰 범위를 같은 윈도우로 묶는다.
REVIEW_INPUT=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    REVIEW_INPUT="${REVIEW_INPUT}
$(git -c core.quotepath=false diff "$BASE" -- "$f")"
  else
    # 미추적 파일은 diff에 안 잡히므로 내용을 직접 합류
    REVIEW_INPUT="${REVIEW_INPUT}
--- NEW FILE: ${f} ---
$(cat "$REPO_ROOT/$f" 2>/dev/null)"
  fi
done <<EOF
$TRIGGERED
EOF

# ── 5) gate_key 캐시 — 같은 변경분은 같은 gate_key. 통과/확인 필요 상태면 재호출하지 않는다 ──
# gate_key에 prompt + schema + hook 자체 해시를 포함 → diff가 같아도 검토 정책(prompt/schema/hook)이
# 바뀌면 gate_key가 달라져 stale PASS를 재사용하지 않고 새 기준으로 재검증한다.
DIFF_HASH="$(printf '%s' "$REVIEW_INPUT" | python -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
SCHEMA_HASH="$(python -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$SCHEMA" 2>/dev/null || echo nohash)"
SELF_HASH="$(python -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "${BASH_SOURCE[0]:-$0}" 2>/dev/null || echo nohash)"
GATE_KEY="$(python -c 'import hashlib, sys; print(hashlib.sha256(("\0".join(sys.argv[1:])).encode("utf-8")).hexdigest())' "$TRIG_CSV" "$DIFF_HASH" "$CODEX_GATE_PROMPT" "$SCHEMA_HASH" "$SELF_HASH")"

read_state "$GATE_KEY" "$TRIG_CSV"
if [ "$STATE_STATUS" = "passed" ]; then
  log_line "skipped(already_passed)" 0 0 "$(log_target)"
  emit_system_message "[codex-gate] SKIP(already_passed): 같은 변경분은 이미 Codex 검증 PASS 완료. 대상: $TRIG_CSV"
  exit 0
fi
if [ "$STATE_STATUS" = "escalated" ]; then
  log_line "skipped(already_force_passed)" 0 0 "$(log_target)"
  emit_system_message "[codex-gate] SKIP(already_force_passed): 이 변경분은 검증 누적 실패로 게이트가 '강제 통과(사람 확인 필요)' 처리된 상태입니다 — 종료는 허용되지만 Codex 검증을 통과한 것은 아닙니다. 변경분을 수정하면 새 기준으로 재검증합니다. 대상: $TRIG_CSV"
  exit 0
fi

# ── 6) Codex 호출 (fallback: codex exec, read-only) ──────────────────────
rm -f "$LAST_MSG" "$ISSUES_FILE"
set +e
printf '%s' "$REVIEW_INPUT" | codex exec --sandbox read-only \
  --output-schema "$SCHEMA" \
  -o "$LAST_MSG" \
  "$CODEX_GATE_PROMPT" >/dev/null 2>"$CODEX_ERR"
set -e

# ── 7) 결과 파싱 (python) ────────────────────────────────────────────────
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

# ── 7a) 파싱 실패 ────────────────────────────────────────────────────────
if [ "$PARSE_RC" -ne 0 ] || [ -z "$PARSE_OUT" ]; then
  PARSE_FAIL_COUNT=$((PARSE_FAIL_COUNT + 1))
  if [ "$PARSE_FAIL_COUNT" -ge "$PARSE_FAIL_LIMIT" ]; then
    escalate "Codex 응답 파싱 ${PARSE_FAIL_LIMIT}회 연속 실패 — 사람 확인 필요 (triggered: $TRIG_CSV)"
    STATE_STATUS="escalated"
    FAIL_COUNT=0; PARSE_FAIL_COUNT=0   # escalation 발동 → streak 리셋(다음 수정분은 0부터 재누적)
    log_line "parse_error(escalated)" 0 0 "$(log_target) | $BASE_INFO"
    # escalated는 검증 미완 — vc 전진하지 않음(미검증 흡수 차단). 같은 diff 재방문은 gate_key 캐시가 skip.
    write_state "escalated"
    exit 0
  fi
  STATE_STATUS="parse_error"
  write_state "parse_error"
  log_line "parse_error" 0 0 "$(log_target) | $BASE_INFO"
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

# ── 7b) verdict == pass ──────────────────────────────────────────────────
if [ "$VERDICT" = "pass" ]; then
  FAIL_COUNT=0
  PARSE_FAIL_COUNT=0
  STATE_STATUS="passed"
  log_line "pass" "$CRIT_COUNT" "$VIOL_COUNT" "$(log_target) | $BASE_INFO"
  # 윈도우 미커버(empty-tree)는 pass여도 vc 전진 금지(ADVANCE_VC="" = 기존 보존).
  write_state "passed" "$ADVANCE_VC"
  # 단절 이력·기준 없음은 BASE 결정 단계에서 fail-closed로 차단되어 여기 도달하지 않는다.
  emit_system_message "[codex-gate] PASS: Codex 검증 완료 — blocking issue 없음. 대상: $TRIG_CSV ($BASE_INFO)$MERGE_NOTE"
  exit 0
fi

# ── 7c) verdict == fail ──────────────────────────────────────────────────
PARSE_FAIL_COUNT=0   # 파싱은 성공했으므로 연속 파싱 실패 카운터 리셋
FAIL_COUNT=$((FAIL_COUNT + 1))
if [ "$FAIL_COUNT" -ge "$FAIL_LIMIT" ]; then
  escalate "Codex 검증 fail ${FAIL_LIMIT}회 도달 — 사람 확인 필요 (triggered: $TRIG_CSV)"
  STATE_STATUS="escalated"
  FAIL_COUNT=0; PARSE_FAIL_COUNT=0   # escalation 발동 → streak 리셋(다음 수정분은 0부터 재누적)
  log_line "fail(escalated)" "$CRIT_COUNT" "$VIOL_COUNT" "$(log_target) | $BASE_INFO"
  # escalated는 검증 미완 — vc 전진하지 않음(미검증 흡수 차단). 같은 diff 재방문은 gate_key 캐시가 skip.
  write_state "escalated"
  exit 0
fi
STATE_STATUS="failing"
write_state "failing"
log_line "fail" "$CRIT_COUNT" "$VIOL_COUNT" "$(log_target) | $BASE_INFO"
{
  echo "[codex-gate] Codex 검증 FAIL — 종료 보류. 아래 항목을 해소한 뒤 다시 종료하십시오:"
  cat "$ISSUES_FILE" 2>/dev/null
} >&2
exit 2
