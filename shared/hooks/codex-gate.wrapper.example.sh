#!/usr/bin/env bash
# codex-gate.wrapper.example.sh — consumer 측 얇은 wrapper 예시 (H2 prototype)
#
# 역할: (1) 도메인 delta(profile)를 로드하고 (2) 공통 골격(codex-gate-core.sh)을 source 한다.
#       공통 실행 로직은 한 줄도 복제하지 않는다 — delta 주입과 골격 호출만 담당한다.
#
# 이 파일은 "consumer의 .claude/hooks/codex-gate.sh가 어떤 모습이 되는지"를 보여주는 예시이며,
# H2 단계에서 실제 script-agent에 배치할지·골격을 어디서 가져올지(아래 CORE 경로)는 사람이 결정한다.
# 이 repo는 consumer를 수정하지 않는다.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# (1) 도메인 delta 로드 — 배치 방식에 따라 경로만 달라진다.
#     이 예시에서는 consumer가 자신의 profile을 .claude/hooks/codex-gate.profile에 둔다고 가정.
source "$HERE/codex-gate.profile"

# (2) 공통 골격 호출 — CORE 위치는 H2 wiring 결정에 따라 셋 중 하나:
#     a) vendor:   consumer가 골격 사본을 보유 → "$HERE/codex-gate-core.sh"
#     b) relative: harness repo를 상대경로 참조 → "$REPO_ROOT/../monitoring-harness/shared/hooks/codex-gate-core.sh"
#     c) plugin:   plugin 모델 → "${CLAUDE_PLUGIN_ROOT}/hooks/codex-gate-core.sh" (이 경우 wrapper 자체가 거의 불필요)
CORE="${CODEX_GATE_CORE:-$HERE/codex-gate-core.sh}"
# shellcheck source=/dev/null
source "$CORE"
