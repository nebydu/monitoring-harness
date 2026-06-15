#!/usr/bin/env bash
# write-guard-tests.sh — write-guard core/entry 시나리오 테스트
#
# 격리 스크래치 워크스페이스(부모 밑 own + 형제 repo)로 PreToolUse 쓰기 가드를 검증한다.
# 실제 툴 호출 없이 PreToolUse 페이로드 JSON을 stdin으로 흘려 종료코드/stderr를 확인한다.
# 실행: bash tests/write-guard-tests.sh   (Git Bash / bash. git·python 필요)
#
# 커버 시나리오:
#   W1  자기 docs/ 쓰기              → exit 2 (자기 문서 보호)
#   W2  자기 src/ 쓰기               → exit 0 (자기 코드 허용)
#   W3  ../monitoring-meta 쓰기      → exit 2 (ground truth 보호)
#   W4  ../hub 쓰기                  → exit 2 (형제 repo 보호)
#   W5  자기 .claude/ 쓰기           → exit 0 (자동화 설정 항상 허용)
#   W6  ../hub/.claude/ 쓰기         → exit 2 (형제 .claude는 교차쓰기로 차단)
#   W7  entry: convention profile 부재 → exit 0 (비소비자 — 가드 안 함)
#   W8  entry: 빈 profile 존재       → 유도 규칙 활성 → 자기 docs exit 2
#   W9  profile 추가 차단 경로       → 해당 경로 exit 2 / 비대상 exit 0
#   W10 잘못된 JSON stdin            → exit 0 (판단하지 않음)
#   W11 file_path 없음               → exit 0
#   W12 상대경로(docs/x)             → exit 2 (repo 기준 해소)
#   W13 realpath 정규화              → src/../docs/x = exit 2 / docs/../src/x = exit 0
#   W14 entry: 명시 WRITE_GUARD_PROFILE 부재 → exit 2 (fail-closed)
#   W15 PARENT 밖 경로               → exit 0 (가드 범위 외)
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(dirname "$TESTS_DIR")"
CORE="$HARNESS_ROOT/shared/hooks/write-guard-core.sh"
ENTRY="$HARNESS_ROOT/hooks/write-guard-entry.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── 워크스페이스 레이아웃: WORK/ws(=PARENT) 밑 own + 형제(meta·hub), WORK/outside(=PARENT 밖) ──
WS="$WORK/ws"
OWN="$WS/own"
META="$WS/monitoring-meta"
HUB="$WS/hub"
OUTSIDE="$WORK/outside"
mkdir -p "$OWN" "$META/adr" "$HUB/src" "$HUB/.claude" "$OWN/docs" "$OWN/src" "$OWN/.claude" "$OWN/config/secret" "$OWN/config/public" "$OUTSIDE"
git -C "$OWN" init -q   # show-toplevel 용 (커밋 불필요 — 가드는 path 기반)

# ── driver — consumer wrapper처럼 profile → core 순서로 source ────────────
DRIVER="$WORK/driver.sh"
cat > "$DRIVER" <<'DRV'
#!/usr/bin/env bash
set -uo pipefail
PROFILE_PATH="${1:-}"
CORE_PATH="$2"
if [ -n "$PROFILE_PATH" ] && [ -f "$PROFILE_PATH" ]; then
  # shellcheck source=/dev/null
  source "$PROFILE_PATH"
fi
# shellcheck source=/dev/null
source "$CORE_PATH"
DRV

# ── profile들 ──────────────────────────────────────────────────────────────
PROFILE_EMPTY="$WORK/empty.profile"
: > "$PROFILE_EMPTY"
PROFILE_EXTRA="$WORK/extra.profile"
printf 'WRITE_GUARD_BLOCK_PATHS=( "config/secret" )\n' > "$PROFILE_EXTRA"

# ── assert 헬퍼 ─────────────────────────────────────────────────────────────
TOTAL=0; FAILED=0
assert_eq() { # desc expected actual
  TOTAL=$((TOTAL + 1))
  if [ "$2" = "$3" ]; then echo "ok   - $1"
  else FAILED=$((FAILED + 1)); echo "FAIL - $1 (expected='$2' actual='$3')"; fi
}
assert_contains() { # desc haystack needle
  TOTAL=$((TOTAL + 1))
  case "$2" in
    *"$3"*) echo "ok   - $1" ;;
    *) FAILED=$((FAILED + 1)); echo "FAIL - $1 (출력에 '$3' 없음: $(printf '%s' "$2" | head -c 200))" ;;
  esac
}

RC=0; OUT=""; ERR=""
mk_json() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1"; }

run_core() { # repo profile file_path
  local repo="$1" profile="$2" fp="$3"
  mk_json "$fp" | ( cd "$repo" && bash "$DRIVER" "$profile" "$CORE" ) >"$WORK/out.txt" 2>"$WORK/err.txt"
  RC=$?; OUT="$(cat "$WORK/out.txt")"; ERR="$(cat "$WORK/err.txt")"
}
run_core_raw() { # repo profile raw_stdin
  local repo="$1" profile="$2" raw="$3"
  printf '%s' "$raw" | ( cd "$repo" && bash "$DRIVER" "$profile" "$CORE" ) >"$WORK/out.txt" 2>"$WORK/err.txt"
  RC=$?; OUT="$(cat "$WORK/out.txt")"; ERR="$(cat "$WORK/err.txt")"
}
run_entry() { # repo file_path [explicit_profile_env]
  local repo="$1" fp="$2" explicit="${3:-}"
  mk_json "$fp" | ( cd "$repo" && CLAUDE_PROJECT_DIR="$repo" CLAUDE_PLUGIN_ROOT="$HARNESS_ROOT" \
      WRITE_GUARD_PROFILE="$explicit" bash "$ENTRY" ) >"$WORK/out.txt" 2>"$WORK/err.txt"
  RC=$?; OUT="$(cat "$WORK/out.txt")"; ERR="$(cat "$WORK/err.txt")"
}

# ════ W1~W6 — 유도 규칙 (빈 profile) ═════════════════════════════════════
run_core "$OWN" "$PROFILE_EMPTY" "docs/note.md"
assert_eq      "W1 자기 docs/ → exit 2" 2 "$RC"
assert_contains "W1 사유=문서" "$ERR" "문서"

run_core "$OWN" "$PROFILE_EMPTY" "src/main.go"
assert_eq "W2 자기 src/ → exit 0" 0 "$RC"
assert_eq "W2 무출력" "" "$OUT$ERR"

run_core "$OWN" "$PROFILE_EMPTY" "../monitoring-meta/adr/x.md"
assert_eq      "W3 ../monitoring-meta → exit 2" 2 "$RC"
assert_contains "W3 사유=형제" "$ERR" "형제"

run_core "$OWN" "$PROFILE_EMPTY" "../hub/src/x.go"
assert_eq "W4 ../hub → exit 2" 2 "$RC"

run_core "$OWN" "$PROFILE_EMPTY" ".claude/settings.json"
assert_eq "W5 자기 .claude/ → exit 0 (항상 허용)" 0 "$RC"

run_core "$OWN" "$PROFILE_EMPTY" "../hub/.claude/settings.json"
assert_eq "W6 형제 .claude → exit 2 (교차쓰기 차단)" 2 "$RC"

# ════ W7/W8/W14 — entry opt-in ═══════════════════════════════════════════
# W7: convention profile 부재 (OWN/.claude/write-guard.profile 없음) → 비소비자 통과
run_entry "$OWN" "docs/note.md"
assert_eq "W7 convention profile 부재 → exit 0 (비소비자)" 0 "$RC"
assert_eq "W7 무출력" "" "$OUT$ERR"

# W8: convention profile 존재(빈 파일) → 유도 규칙 활성
cp "$PROFILE_EMPTY" "$OWN/.claude/write-guard.profile"
run_entry "$OWN" "docs/note.md"
assert_eq "W8 빈 profile 존재 → 자기 docs exit 2" 2 "$RC"
run_entry "$OWN" "src/main.go"
assert_eq "W8 빈 profile 존재 → 자기 src exit 0" 0 "$RC"
rm -f "$OWN/.claude/write-guard.profile"

# W14: 명시 WRITE_GUARD_PROFILE 부재 → fail-closed
run_entry "$OWN" "src/main.go" "$WORK/missing.profile"
assert_eq      "W14 명시 profile 부재 → exit 2 (fail-closed)" 2 "$RC"
assert_contains "W14 구성 오류 안내" "$ERR" "구성 오류"

# ════ W9 — profile 추가 차단 경로 (add-only) ═════════════════════════════
run_core "$OWN" "$PROFILE_EXTRA" "config/secret/keys.txt"
assert_eq      "W9 추가 차단 경로 → exit 2" 2 "$RC"
assert_contains "W9 사유=profile 지정" "$ERR" "profile 지정"
run_core "$OWN" "$PROFILE_EXTRA" "config/public/readme.txt"
assert_eq "W9 비대상(config/public) → exit 0" 0 "$RC"

# ════ W10/W11 — 입력 방어 ════════════════════════════════════════════════
run_core_raw "$OWN" "$PROFILE_EMPTY" 'not a json{'
assert_eq "W10 잘못된 JSON → exit 0 (판단 안 함)" 0 "$RC"
run_core_raw "$OWN" "$PROFILE_EMPTY" '{"tool_name":"Write","tool_input":{}}'
assert_eq "W11 file_path 없음 → exit 0" 0 "$RC"

# ════ W12 — 상대경로 repo 기준 해소 ══════════════════════════════════════
run_core "$OWN" "$PROFILE_EMPTY" "docs/sub/deep.md"
assert_eq "W12 상대경로 docs/ → exit 2" 2 "$RC"

# ════ W13 — realpath 정규화(.. 붕괴) ═════════════════════════════════════
run_core "$OWN" "$PROFILE_EMPTY" "src/../docs/sneak.md"
assert_eq "W13 src/../docs → docs로 정규화 → exit 2" 2 "$RC"
run_core "$OWN" "$PROFILE_EMPTY" "docs/../src/ok.go"
assert_eq "W13 docs/../src → src로 정규화 → exit 0" 0 "$RC"

# ════ W15 — PARENT 밖 경로 (가드 범위 외) ════════════════════════════════
run_core "$OWN" "$PROFILE_EMPTY" "$OUTSIDE/x.txt"
assert_eq "W15 PARENT 밖 절대경로 → exit 0 (범위 외)" 0 "$RC"

# ════ W16 — 실제 production 입력 형태: Windows 절대 역슬래시 경로 ═════════
# Claude Code(Windows)는 tool_input.file_path에 'C:\...' 역슬래시 절대경로를 넘긴다. 위 케이스는
# 상대·MSYS 슬래시만 써서 이 형태를 안 밟는다 — realpath/normcase가 역슬래시 절대경로에서도
# REPO_ROOT(forward-slash, git --show-toplevel)와 동일 정규형으로 수렴하는지 검증한다.
if command -v cygpath >/dev/null 2>&1; then
  # JSON은 python json.dumps로 만든다(역슬래시 이스케이프를 정확히 처리 — sed 수동 이스케이프 함정 회피).
  run_core_win() { # repo profile win_path
    PYTHONIOENCODING=utf-8 python -c 'import json,sys; sys.stdout.write(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1]}}))' "$3" \
      | ( cd "$1" && bash "$DRIVER" "$2" "$CORE" ) >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?; OUT="$(cat "$WORK/out.txt")"; ERR="$(cat "$WORK/err.txt")"
  }
  run_core_win "$OWN" "$PROFILE_EMPTY" "$(cygpath -w "$OWN/docs/win.md")"
  assert_eq "W16 Windows 절대 docs → exit 2"  2 "$RC"
  run_core_win "$OWN" "$PROFILE_EMPTY" "$(cygpath -w "$OWN/src/win.go")"
  assert_eq "W16 Windows 절대 src → exit 0"   0 "$RC"
  run_core_win "$OWN" "$PROFILE_EMPTY" "$(cygpath -w "$META/adr/win.md")"
  assert_eq "W16 Windows 절대 형제 → exit 2"  2 "$RC"
else
  echo "skip - W16 (cygpath 없음 — 비-Windows 환경)"
fi

# ── 요약 ──────────────────────────────────────────────────────────────────
echo ""
echo "총 ${TOTAL} asserts, 실패 ${FAILED}"
[ "$FAILED" -eq 0 ] || exit 1
