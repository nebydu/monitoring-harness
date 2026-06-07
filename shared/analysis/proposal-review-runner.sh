#!/usr/bin/env bash
# proposal-review-runner.sh — /proposal-review command 실행부 (H6)
#
# 역할: proposal(stdin) + consumer profile 문맥(선택)을 조립해 Codex read-only 리뷰를 1회 실행하고,
#       schema 고정 verdict JSON에 runner 메타(context 상태)를 합쳐 stdout으로 낸다.
#
# codex-gate core와 의도적으로 다른 점 (docs/decisions/proposal-review-scope.md §5):
#   - state/fail streak/escalation 없음 — command는 대화형이라 실패하면 시끄럽게 실패하고
#     사람이 재시도한다. verdict 해석도 호출자(Claude)가 한다.
#   - profile 부재 = 조용한 skip이 아니라 degraded 실행 + 그 사실을 출력 JSON에 박는다(scope §4).
#     단 PROPOSAL_REVIEW_PROFILE 명시 지정 후 부재는 오설정 → exit 2 (의도 신호 원칙).
#
# 사용:  printf '%s' "$PROPOSAL" | proposal-review-runner.sh [--out <file>]
#   - proposal은 반드시 stdin (argv 금지 — Windows 명령행 길이 제한)
#   - --out: proposal + verdict를 JSON 파일로도 남긴다 (결정 근거 기록용)
#
# profile (선택): $PROPOSAL_REVIEW_PROFILE → ${CLAUDE_PROJECT_DIR}/.claude/proposal-review.profile
#   주입점: PROPOSAL_REVIEW_CONTEXT_DOCS (배열) 문맥 문서 경로 / PROPOSAL_REVIEW_POLICY (문자열) repo 정책
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SCHEMA="${PROPOSAL_REVIEW_SCHEMA:-$PLUGIN_ROOT/shared/schemas/proposal-review-schema.json}"
PROMPT_FILE="$PLUGIN_ROOT/shared/analysis/proposal-review.prompt.md"

# ── 인자 ─────────────────────────────────────────────────────────────────
OUT_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT_FILE="${2:?[proposal-review] --out에 파일 경로가 필요합니다}"; shift 2 ;;
    *) echo "[proposal-review] 알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done

# ── proposal 입력 (stdin) ─────────────────────────────────────────────────
PROPOSAL="$(cat)"
if [ -z "$PROPOSAL" ]; then
  echo "[proposal-review] 입력 오류: stdin proposal이 비어 있음" >&2
  exit 2
fi

# ── profile 로드 — 부재 시 degraded (조용히 skip하지 않는다) ───────────────
EXPLICIT_PROFILE="${PROPOSAL_REVIEW_PROFILE:-}"
PROFILE="${EXPLICIT_PROFILE:-${CLAUDE_PROJECT_DIR:-}/.claude/proposal-review.profile}"
CONTEXT_STATUS="none (no profile — degraded review)"
PROPOSAL_REVIEW_POLICY=""
PROPOSAL_REVIEW_CONTEXT_DOCS=()
if [ -n "$PROFILE" ] && [ -f "$PROFILE" ]; then
  # shellcheck source=/dev/null
  source "$PROFILE"
  CONTEXT_STATUS="profile: $PROFILE"
elif [ -n "$EXPLICIT_PROFILE" ]; then
  # 명시 지정 후 부재 = 오설정 (codex-gate-entry와 동일한 의도 신호 원칙)
  echo "[proposal-review] 구성 오류: 지정한 PROPOSAL_REVIEW_PROFILE을 찾지 못함 ('$EXPLICIT_PROFILE')." >&2
  exit 2
else
  echo "[proposal-review] WARNING: profile 없음('${PROFILE:-unset}') — repo 문맥 없이 degraded 리뷰를 수행합니다." >&2
fi

# ── 리뷰 입력 조립: 문맥 문서(있는 것만) → 정책 → proposal ─────────────────
INPUT=""
DOCS_USED=""
if [ "${#PROPOSAL_REVIEW_CONTEXT_DOCS[@]}" -gt 0 ]; then
  for doc in "${PROPOSAL_REVIEW_CONTEXT_DOCS[@]}"; do
    [ -z "$doc" ] && continue
    if [ -f "$doc" ]; then
      INPUT="${INPUT}--- CONTEXT DOC: ${doc} ---
$(cat "$doc")

"
      DOCS_USED="${DOCS_USED}${doc}"$'\n'
    else
      # 형제 repo 상대경로 등 workspace 배치 의존 — fail이 아니라 warn (scope §4)
      echo "[proposal-review] WARNING: 문맥 문서 없음, 건너뜀: $doc" >&2
    fi
  done
fi
if [ -n "$PROPOSAL_REVIEW_POLICY" ]; then
  INPUT="${INPUT}--- REPO POLICY ---
${PROPOSAL_REVIEW_POLICY}

"
fi
INPUT="${INPUT}--- PROPOSAL (리뷰 대상) ---
${PROPOSAL}"

# ── Codex 호출 (read-only, schema 고정) ──────────────────────────────────
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
LAST_MSG="$TMP_DIR/last-message.json"
CODEX_ERR="$TMP_DIR/stderr.txt"

set +e
printf '%s' "$INPUT" | codex exec --sandbox read-only \
  --output-schema "$SCHEMA" \
  -o "$LAST_MSG" \
  "$(cat "$PROMPT_FILE")" >/dev/null 2>"$CODEX_ERR"
CODEX_RC=$?
set -e

if [ "$CODEX_RC" -ne 0 ] || [ ! -s "$LAST_MSG" ]; then
  {
    echo "[proposal-review] codex exec 실패 (rc=$CODEX_RC). stderr 마지막 부분:"
    tail -c 400 "$CODEX_ERR" 2>/dev/null || true
    echo ""
  } >&2
  exit 2
fi

# ── 결과 병합: context 상태를 verdict JSON에 박아 stdout (+ --out 아티팩트) ─
# PYTHONIOENCODING=utf-8: Windows cp949 콘솔에서 non-CP949 문자 UnicodeEncodeError 방지
printf '%s' "$PROPOSAL" | PYTHONIOENCODING=utf-8 python -c '
import json, sys, datetime
last_msg, status, docs_nl, out_file = sys.argv[1:5]
try:
    with open(last_msg, encoding="utf-8") as fp:
        review = json.load(fp)
except Exception as e:
    head = open(last_msg, encoding="utf-8", errors="replace").read(200)
    sys.stderr.write("[proposal-review] Codex 응답 파싱 실패: %s\n원본 앞 200자: %s\n" % (e, head))
    sys.exit(3)
docs = [d for d in docs_nl.split("\n") if d]
result = {"context": status, "context_docs": docs}
result.update(review)
print(json.dumps(result, ensure_ascii=False, indent=2))
if out_file:
    artifact = {
        "generated_at": datetime.datetime.now().astimezone().isoformat(),
        "context": status,
        "context_docs": docs,
        "proposal": sys.stdin.read(),
        "review": review,
    }
    with open(out_file, "w", encoding="utf-8") as g:
        json.dump(artifact, g, ensure_ascii=False, indent=2)
' "$LAST_MSG" "$CONTEXT_STATUS" "$DOCS_USED" "$OUT_FILE"
