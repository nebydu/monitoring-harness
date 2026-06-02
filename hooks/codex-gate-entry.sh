#!/usr/bin/env bash
# codex-gate-entry.sh — plugin 진입점 (H5 packaging)
#
# 역할: consumer 델타(profile) + plugin 골격(core)을 결합해 Codex gate를 실행한다.
#   - 도메인 값(트리거/스킵/프롬프트)은 consumer profile에만 존재한다(plugin은 도메인 결정을 하지 않는다).
#   - 공통 골격/공통 스키마는 plugin이 제공한다.
#   - escalation 카운터 등 보존 상태는 업데이트를 넘어 사는 ${CLAUDE_PLUGIN_DATA}에 둔다.
#
# 호출: hooks/hooks.json의 Stop hook이 git-bash.cmd 경유로 이 스크립트를 부른다.
#       첫 인자 = consumer profile 경로(plugin config user_config.profile에서 주입).
set -euo pipefail

# 1) consumer profile 경로: 첫 인자(우선) → CODEX_GATE_PROFILE → CLAUDE_PLUGIN_OPTION_PROFILE
#    (plugin userConfig.profile는 ${user_config.profile} 인자이자 CLAUDE_PLUGIN_OPTION_PROFILE 환경변수로 주입됨)
PROFILE="${1:-${CODEX_GATE_PROFILE:-${CLAUDE_PLUGIN_OPTION_PROFILE:-}}}"
if [ -z "$PROFILE" ] || [ ! -f "$PROFILE" ]; then
  echo "[codex-gate] 구성 오류: consumer profile 경로 미지정/없음 ('$PROFILE'). plugin config(user_config.profile)를 확인하세요." >&2
  exit 2
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
