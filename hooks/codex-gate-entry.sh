#!/usr/bin/env bash
# codex-gate-entry.sh — plugin 진입점 (H5 packaging)
#
# 역할: consumer 델타(profile) + plugin 골격(core)을 결합해 Codex gate를 실행한다.
#   - 도메인 값(트리거/스킵/프롬프트)은 consumer profile에만 존재한다(plugin은 도메인 결정을 하지 않는다).
#   - 공통 골격/공통 스키마는 plugin이 제공한다.
#   - escalation 카운터 등 보존 상태는 업데이트를 넘어 사는 ${CLAUDE_PLUGIN_DATA}에 둔다.
#
# 호출: hooks/hooks.json의 Stop hook이 git-bash.cmd 경유로 이 스크립트를 부른다.
#       첫 인자 = consumer profile 경로(기본: ${CLAUDE_PROJECT_DIR}/.claude/codex-gate.profile = convention).
set -euo pipefail

# 1) consumer profile 경로 결정 (우선순위: override env → 인자(convention) → CLAUDE_PROJECT_DIR convention)
#    - 기본은 consumer repo의 convention 위치다. per-user config나 절대경로가 필요 없어 협업자 공유에 안전하다.
#    - 비표준 위치를 쓰려면 CODEX_GATE_PROFILE 환경변수로만 덮어쓴다(테스트/예외용).
#
#    profile 부재 처리 — opt-in 소비자 모델:
#      - convention 경로(인자/CLAUDE_PROJECT_DIR)에 profile이 없으면 = 이 repo는 plugin codex-gate
#        소비자가 아님 → 조용히 skip(exit 0). Stop hook은 글로벌 발동이므로, 소비자가 아닌 repo의
#        세션 종료를 막지 않는다.
#      - 단, 사용자가 CODEX_GATE_PROFILE을 명시 지정했는데 그 파일이 없으면 = 진짜 오설정/오타
#        → 기존대로 차단(exit 2).
EXPLICIT_PROFILE="${CODEX_GATE_PROFILE:-}"
PROFILE="${EXPLICIT_PROFILE:-${1:-${CLAUDE_PROJECT_DIR:-}/.claude/codex-gate.profile}}"
if [ -z "$PROFILE" ] || [ ! -f "$PROFILE" ]; then
  if [ -n "$EXPLICIT_PROFILE" ]; then
    echo "[codex-gate] 구성 오류: 지정한 CODEX_GATE_PROFILE을 찾지 못함 ('$EXPLICIT_PROFILE'). 경로를 확인하세요." >&2
    exit 2
  fi
  # convention 경로에 profile 없음 = 소비자 아님 → 조용히 skip(노이즈 없이 Stop 정상 진행)
  exit 0
fi

# 2) plugin 자원 위치 — 런타임에는 CLAUDE_PLUGIN_ROOT/CLAUDE_PLUGIN_DATA가 환경변수로 주입된다.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export CODEX_GATE_SCHEMA="${CODEX_GATE_SCHEMA:-$PLUGIN_ROOT/shared/schemas/codex-schema.json}"
export CODEX_GATE_DATA_DIR="${CODEX_GATE_DATA_DIR:-${CLAUDE_PLUGIN_DATA:-}}"

# 3) consumer 델타 로드 → 공통 골격 실행
#    (Stop hook 입력 JSON은 stdin으로 흘러 core의 `cat`이 읽는다 — source는 stdin을 보존한다)
# shellcheck source=/dev/null
source "$PROFILE"
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/shared/hooks/codex-gate-core.sh"
