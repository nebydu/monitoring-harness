#!/usr/bin/env bash
# write-guard-entry.sh — plugin 진입점 (PreToolUse 쓰기 가드)
#
# 역할: consumer 델타(write-guard.profile) + plugin 골격(write-guard-core)을 결합해 쓰기 가드를
#   실행한다. codex-gate-entry와 동일한 convention profile 발견 방식이다.
#
# 호출: hooks/hooks.json의 PreToolUse hook이 git-bash.cmd 경유로 이 스크립트를 부른다.
#       첫 인자 = consumer profile 경로(기본: ${CLAUDE_PROJECT_DIR}/.claude/write-guard.profile).
#
# opt-in 모델: convention profile이 "있는" repo만 가드한다(profile 존재 = 게이팅 의도). 없으면
#   조용히 통과(exit 0) — PreToolUse는 글로벌 발동이므로 비소비자(무관 프로젝트)의 쓰기를 막지
#   않는다. profile이 비어 있어도(추가 차단 경로 미지정) 골격의 유도 규칙은 그대로 적용된다.
#   단, CODEX와 동일하게 CODEX_… 대신 WRITE_GUARD_PROFILE을 "명시 지정"했는데 그 파일이 없으면
#   진짜 오설정 → 보안 통제라 fail-closed(exit 2 = 차단)한다.
set -uo pipefail

INPUT="$(cat)"

EXPLICIT_PROFILE="${WRITE_GUARD_PROFILE:-}"
PROFILE="${EXPLICIT_PROFILE:-${1:-${CLAUDE_PROJECT_DIR:-}/.claude/write-guard.profile}}"
if [ -z "$PROFILE" ] || [ ! -f "$PROFILE" ]; then
  if [ -n "$EXPLICIT_PROFILE" ]; then
    echo "[write-guard] 구성 오류: 지정한 WRITE_GUARD_PROFILE을 찾지 못함 ('$EXPLICIT_PROFILE'). 경로를 확인하세요." >&2
    exit 2
  fi
  # convention 경로에 profile 없음 = 비소비자 → 조용히 통과(쓰기 허용)
  exit 0
fi

# plugin 자원 위치 — 런타임에는 CLAUDE_PLUGIN_ROOT가 환경변수로 주입된다.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# consumer 델타 로드 → 공통 골격 실행 (stdin은 §위에서 읽었으므로 herestring으로 재공급)
# shellcheck source=/dev/null
source "$PROFILE"
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/shared/hooks/write-guard-core.sh" <<< "$INPUT"
