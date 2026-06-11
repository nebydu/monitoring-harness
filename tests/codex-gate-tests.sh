#!/usr/bin/env bash
# codex-gate-tests.sh — codex-gate core/entry 시나리오 테스트
#
# 격리 스크래치 repo + codex 스텁(PATH shim)으로 게이트 골격을 검증한다. 실제 codex를 호출하지 않는다.
# 실행: bash tests/codex-gate-tests.sh   (Git Bash / bash. git·python 필요)
#
# 커버 시나리오 (2026-06-11 proposal-review 권고 4종 = S1·S2 / S3 / S9 / S10·S11 포함):
#   S1  stop_hook_active=true + 주입점 오설정 → exit 0 (루프 가드가 구성 오류 차단보다 우선)
#   S2  stop_hook_active=false + 주입점 오설정 → exit 2 (오설정은 첫 stop에서 1회 노출)
#   S3  entry: 명시 CODEX_GATE_PROFILE 부재 — active=false → exit 2 / active=true → exit 0 (루프 없음)
#   S4  entry: convention profile 없음(비소비자) → 조용히 exit 0
#   S5  부트스트랩 + 트리거 외 변경만 → SKIP + vc 전진
#   S6  같은 턴 커밋(클린 트리) → 검증 윈도우가 커밋분 포착 → PASS + vc 전진 (사각지대 해소 증명)
#   S7  동일 diff 재방문 → already_passed 캐시 skip
#   S8  fail verdict → exit 2 차단 → FAIL_LIMIT 도달 시 escalate(exit 0) + vc 비전진 + 재방문 skip
#   S9  basename 충돌 repo 2개 → 서로 다른 data dir(<repo명>-<hash8>)로 분리, 오차단 없음
#   S10 data dir 소유권 메타데이터(.repo-path) 불일치 → exit 2 fail-closed
#   S11 구 레이아웃(<repo명>/) state 미승계 — fresh bootstrap, 구 디렉터리 불변
#   S12 단절 이력(vc가 HEAD와 공통 조상 없음) → BLOCK exit 2 + block log 기록
#   S13 기준 없음(origin·vc 모두 부재) → BLOCK exit 2
#   S14 entry: convention profile 경유 end-to-end SKIP (stdin herestring 재공급 경로)
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(dirname "$TESTS_DIR")"
CORE="$HARNESS_ROOT/shared/hooks/codex-gate-core.sh"
ENTRY="$HARNESS_ROOT/hooks/codex-gate-entry.sh"
SCHEMA="$HARNESS_ROOT/shared/schemas/codex-schema.json"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DATA_ROOT="$WORK/data"
mkdir -p "$DATA_ROOT" "$WORK/bin" "$WORK/origins" "$WORK/repos"

# ── codex 스텁 — -o 인자 경로에 CODEX_STUB_FILE 내용(기본 pass)을 쓴다 ────
cat > "$WORK/bin/codex" <<'STUB'
#!/usr/bin/env bash
out=""; prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  prev="$a"
done
cat >/dev/null   # REVIEW_INPUT 소비 (생산자 SIGPIPE 방지)
if [ -n "${CODEX_STUB_FILE:-}" ] && [ -f "$CODEX_STUB_FILE" ]; then
  cp "$CODEX_STUB_FILE" "$out"
else
  printf '{"verdict":"pass","critical_issues":[],"spec_violations":[],"summary":"stub pass"}' > "$out"
fi
STUB
chmod +x "$WORK/bin/codex"
export PATH="$WORK/bin:$PATH"

# ── driver — consumer wrapper처럼 profile → core 순서로 source ────────────
DRIVER="$WORK/driver.sh"
cat > "$DRIVER" <<'DRV'
#!/usr/bin/env bash
set -euo pipefail
PROFILE_PATH="${1:-}"
CORE_PATH="$2"
if [ -n "$PROFILE_PATH" ] && [ -f "$PROFILE_PATH" ]; then
  # shellcheck source=/dev/null
  source "$PROFILE_PATH"
fi
# shellcheck source=/dev/null
source "$CORE_PATH"
DRV

# ── 테스트용 profile ──────────────────────────────────────────────────────
PROFILE_OK="$WORK/ok.profile"
cat > "$PROFILE_OK" <<'PRF'
CODEX_GATE_TRIGGER_GLOBS=( "src/*" "*.go" )
CODEX_GATE_SKIP_GLOBS=( ".claude/*" "docs/*" )
CODEX_GATE_PROMPT="테스트 프롬프트"
PRF
PROFILE_BROKEN="$WORK/broken.profile"   # TRIGGER_GLOBS 누락 = 주입점 오설정
printf 'CODEX_GATE_PROMPT="프롬프트만 있음"\n' > "$PROFILE_BROKEN"

printf '{"verdict":"fail","critical_issues":["스텁 critical"],"spec_violations":[],"summary":"stub fail"}' \
  > "$WORK/stub-fail.json"

# ── assert/실행 헬퍼 ──────────────────────────────────────────────────────
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
run_core() { # repo stop_active profile [datadir]
  local repo="$1" active="$2" profile="$3" datadir="${4:-$DATA_ROOT}"
  printf '{"stop_hook_active": %s}' "$active" \
    | ( cd "$repo" && CODEX_GATE_DATA_DIR="$datadir" CODEX_GATE_SCHEMA="$SCHEMA" \
        bash "$DRIVER" "$profile" "$CORE" ) >"$WORK/out.txt" 2>"$WORK/err.txt"
  RC=$?
  OUT="$(cat "$WORK/out.txt")"; ERR="$(cat "$WORK/err.txt")"
}
run_entry() { # repo stop_active
  local repo="$1" active="$2"
  printf '{"stop_hook_active": %s}' "$active" \
    | ( cd "$repo" && CLAUDE_PROJECT_DIR="$repo" CLAUDE_PLUGIN_ROOT="$HARNESS_ROOT" \
        CLAUDE_PLUGIN_DATA="$DATA_ROOT" bash "$ENTRY" ) >"$WORK/out.txt" 2>"$WORK/err.txt"
  RC=$?
  OUT="$(cat "$WORK/out.txt")"; ERR="$(cat "$WORK/err.txt")"
}

make_repo() { # uid name parent → stdout=repo 경로 (bare origin + base 커밋 push)
  local uid="$1" name="$2" parent="$3"
  local origin="$WORK/origins/$uid.git" repo="$parent/$name"
  mkdir -p "$parent"
  git init -q --bare -b main "$origin"
  git init -q -b main "$repo"
  ( cd "$repo" \
    && git config user.email codex-gate-test@local && git config user.name codex-gate-test \
    && git config core.autocrlf false \
    && git remote add origin "$origin" \
    && printf 'base\n' > base.txt && git add base.txt && git commit -qm base \
    && git push -q origin main && git fetch -q origin )
  printf '%s' "$repo"
}
data_dir_for() { # repo → core와 동일 규칙의 keyed data dir
  local root h
  root="$(git -C "$1" rev-parse --show-toplevel)"
  h="$(printf '%s' "$root" | python -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:8])')"
  printf '%s/%s-%s' "$DATA_ROOT" "$(basename "$root")" "$h"
}
state_field() { # state_file field
  python -c 'import json, sys; print(str(json.load(open(sys.argv[1], encoding="utf-8")).get(sys.argv[2]) or ""))' \
    "$1" "$2" 2>/dev/null || true
}
head_of() { git -C "$1" rev-parse HEAD; }

# ════ S1/S2 — stop 루프 가드 vs 주입점 오설정 ════════════════════════════
CFG="$(make_repo cfg cfgrepo "$WORK/repos")"
run_core "$CFG" true "$PROFILE_BROKEN"
assert_eq "S1 active=true + 오설정 → exit 0 (루프 가드 우선)" 0 "$RC"
assert_eq "S1 차단 출력 없음" "" "$OUT$ERR"
run_core "$CFG" false "$PROFILE_BROKEN"
assert_eq "S2 active=false + 오설정 → exit 2 (1회 노출)" 2 "$RC"
assert_contains "S2 구성 오류 안내" "$ERR" "구성 오류"

# ════ S3/S4 — entry 가드·opt-in ══════════════════════════════════════════
PLAIN="$(make_repo plain plainrepo "$WORK/repos")"
export CODEX_GATE_PROFILE="$WORK/missing.profile"
run_entry "$PLAIN" false
assert_eq "S3 명시 profile 부재 + active=false → exit 2" 2 "$RC"
assert_contains "S3 구성 오류 안내" "$ERR" "구성 오류"
run_entry "$PLAIN" true
assert_eq "S3 명시 profile 부재 + active=true → exit 0 (루프 없음)" 0 "$RC"
unset CODEX_GATE_PROFILE
run_entry "$PLAIN" false
assert_eq "S4 convention profile 없음(비소비자) → exit 0" 0 "$RC"
assert_eq "S4 조용히 skip(출력 없음)" "" "$OUT$ERR"

# ════ S5 — 부트스트랩 + 트리거 외 변경 SKIP + vc 전진 ════════════════════
MAIN="$(make_repo main mainrepo "$WORK/repos")"
HEAD0="$(head_of "$MAIN")"
printf 'memo\n' > "$MAIN/notes.txt"   # 미추적·비트리거
run_core "$MAIN" false "$PROFILE_OK"
assert_eq "S5 비트리거 변경만 → exit 0" 0 "$RC"
assert_contains "S5 SKIP 메시지" "$OUT" "SKIP"
assert_contains "S5 부트스트랩 BASE" "$OUT" "bootstrap-origin"
MAIN_STATE="$(data_dir_for "$MAIN")/.codex-gate-state"
assert_eq "S5 vc 전진(HEAD0)" "$HEAD0" "$(state_field "$MAIN_STATE" verified_commit)"

# ════ S6 — 같은 턴 커밋 사각지대: 클린 트리에서 커밋분 트리거 ════════════
printf 'package main\n' > "$MAIN/app.go"
( cd "$MAIN" && git add app.go && git commit -qm "trigger change" )
HEAD1="$(head_of "$MAIN")"
run_core "$MAIN" false "$PROFILE_OK"
assert_eq "S6 커밋분 트리거 → 스텁 pass → exit 0" 0 "$RC"
assert_contains "S6 PASS 메시지" "$OUT" "PASS"
assert_eq "S6 vc 전진(HEAD1)" "$HEAD1" "$(state_field "$MAIN_STATE" verified_commit)"

# ════ S7 — 동일 diff 재방문 already_passed ═══════════════════════════════
printf 'package main // v2\n' > "$MAIN/app.go"   # 미커밋 트리거 변경
run_core "$MAIN" false "$PROFILE_OK"
assert_eq "S7 미커밋 트리거 pass → exit 0" 0 "$RC"
run_core "$MAIN" false "$PROFILE_OK"
assert_eq "S7 동일 diff 재방문 → exit 0" 0 "$RC"
assert_contains "S7 already_passed 캐시" "$OUT" "already_passed"

# ════ S8 — fail 차단 → escalate → 재방문 skip, vc 비전진 ═════════════════
export CODEX_STUB_FILE="$WORK/stub-fail.json"
printf 'package main // v3\n' > "$MAIN/app.go"
run_core "$MAIN" false "$PROFILE_OK"
assert_eq "S8 fail verdict → exit 2 차단" 2 "$RC"
assert_contains "S8 FAIL 안내" "$ERR" "FAIL"
assert_eq "S8 fail_count=1" "1" "$(state_field "$MAIN_STATE" fail_count)"
export CODEX_GATE_FAIL_LIMIT=2
printf 'package main // v4\n' > "$MAIN/app.go"   # 새 diff — streak은 triggered 일치로 승계
run_core "$MAIN" false "$PROFILE_OK"
assert_eq "S8 FAIL_LIMIT 도달 → escalate exit 0" 0 "$RC"
assert_contains "S8 강제 통과 노출" "$OUT" "강제 통과"
assert_eq "S8 escalated는 vc 비전진(HEAD1 유지)" "$HEAD1" "$(state_field "$MAIN_STATE" verified_commit)"
run_core "$MAIN" false "$PROFILE_OK"
assert_eq "S8 escalated 재방문 → exit 0" 0 "$RC"
assert_contains "S8 already_force_passed 캐시" "$OUT" "already_force_passed"
unset CODEX_STUB_FILE CODEX_GATE_FAIL_LIMIT

# ════ S9 — basename 충돌 repo 2개 → data dir 분리 ════════════════════════
A1="$(make_repo alpha1 alpha "$WORK/repos/p1")"
A2="$(make_repo alpha2 alpha "$WORK/repos/p2")"
run_core "$A1" false "$PROFILE_OK"
assert_eq "S9 alpha(1) → exit 0" 0 "$RC"
run_core "$A2" false "$PROFILE_OK"
assert_eq "S9 alpha(2) 같은 basename → exit 0 (단절 오차단 없음)" 0 "$RC"
ALPHA_DIRS="$(find "$DATA_ROOT" -maxdepth 1 -type d -name 'alpha-*' | wc -l | tr -d ' ')"
assert_eq "S9 keyed data dir 2개로 분리" "2" "$ALPHA_DIRS"

# ════ S10 — 소유권 메타데이터 불일치 → fail-closed ═══════════════════════
printf '%s' "/bogus/other-repo" > "$(data_dir_for "$A1")/.repo-path"
run_core "$A1" false "$PROFILE_OK"
assert_eq "S10 .repo-path 불일치 → exit 2" 2 "$RC"
assert_contains "S10 소유권 충돌 안내" "$ERR" "소유권 충돌"
printf '%s' "$(git -C "$A1" rev-parse --show-toplevel)" > "$(data_dir_for "$A1")/.repo-path"   # 원복

# ════ S11 — 구 레이아웃(<repo명>/) 미승계 fresh bootstrap ════════════════
LEG="$(make_repo legacy legacyrepo "$WORK/repos")"
mkdir -p "$DATA_ROOT/legacyrepo"
printf '{"verified_commit": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}' > "$DATA_ROOT/legacyrepo/.codex-gate-state"
run_core "$LEG" false "$PROFILE_OK"
assert_eq "S11 구 레이아웃 무시 → fresh bootstrap exit 0" 0 "$RC"
assert_eq "S11 구 state 불변" '{"verified_commit": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}' \
  "$(cat "$DATA_ROOT/legacyrepo/.codex-gate-state")"
assert_eq "S11 새 keyed dir에 vc 기록" "$(head_of "$LEG")" \
  "$(state_field "$(data_dir_for "$LEG")/.codex-gate-state" verified_commit)"

# ════ S12 — 단절 이력 BLOCK ══════════════════════════════════════════════
DISC="$(make_repo disc discrepo "$WORK/repos")"
EMPTY_TREE_OBJ="$(git -C "$DISC" mktree </dev/null)"
ORPHAN="$(cd "$DISC" && git commit-tree "$EMPTY_TREE_OBJ" -m orphan </dev/null)"
mkdir -p "$(data_dir_for "$DISC")"
printf '{"verified_commit": "%s"}' "$ORPHAN" > "$(data_dir_for "$DISC")/.codex-gate-state"
run_core "$DISC" false "$PROFILE_OK"
assert_eq "S12 단절 이력 → exit 2" 2 "$RC"
assert_contains "S12 단절 안내" "$ERR" "단절"
[ -f "$(data_dir_for "$DISC")/codex-gate-block.log" ]
assert_eq "S12 block log 기록" 0 "$?"

# ════ S13 — 기준 없음(origin·vc 부재) BLOCK ══════════════════════════════
NOOR="$WORK/repos/noorigin"
git init -q -b main "$NOOR"
( cd "$NOOR" && git config user.email codex-gate-test@local && git config user.name codex-gate-test \
  && git config core.autocrlf false \
  && printf 'base\n' > base.txt && git add base.txt && git commit -qm base )
run_core "$NOOR" false "$PROFILE_OK"
assert_eq "S13 기준 없음 → exit 2" 2 "$RC"
assert_contains "S13 기준 없음 안내" "$ERR" "기준 없음"

# ════ S14 — entry end-to-end (herestring 재공급 경로) ════════════════════
ENT="$(make_repo entry entryrepo "$WORK/repos")"
mkdir -p "$ENT/.claude"
cp "$PROFILE_OK" "$ENT/.claude/codex-gate.profile"
run_entry "$ENT" false
assert_eq "S14 entry convention profile → exit 0" 0 "$RC"
assert_contains "S14 core까지 도달(SKIP)" "$OUT" "SKIP"

# ── 요약 ──────────────────────────────────────────────────────────────────
echo ""
echo "총 ${TOTAL} asserts, 실패 ${FAILED}"
[ "$FAILED" -eq 0 ] || exit 1
