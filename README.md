# monitoring-harness

`hub`, `script-agent`, `monitoring-meta` 세 repo가 각자의 `.claude/` 아래에서 거의 동일하게
**3벌로 손유지**하던 Claude Code / Codex 하네스 공통부를, 향후 하나의 **shared harness plugin**으로
묶기 위한 후보 repo다.

## 목적

세 consumer repo의 `.claude/` 하네스 공통부(예: `codex-gate.sh` 골격, `codex-schema.json`,
`CLAUDE.md` 코어 섹션, agent scaffold)는 사실상 같은 코드를 손으로 세 번 유지하면서 **drift**가
쌓인다. 이 repo는 그 공통부를 plugin/shared로 끌어올려 **drift를 줄이는 것**을 목표로 한다.

## 현재 상태: H0 (bootstrap)

- **부트스트랩 + 설계 문서만** 존재한다. 실제 hook 공통화 구현, agent migration, consumer 적용은
  하지 않았다.
- **아직 어떤 consumer repo에도 적용하지 않았다.** 기존 `hub`/`script-agent`/`monitoring-meta`의
  `.claude/`가 계속 **source of execution**이다.
- plugin manifest(`.claude-plugin/plugin.json`)는 hooks/agents/settings를 **활성화하지 않은**
  최소 형태다.

## 적용 원칙

- **공통부**(언어/위상/금지/호출순서·재시도/결과 스키마/권한 매트릭스 코어, codex-gate 골격, 동일 스키마,
  agent 골격)는 plugin/shared로 **이동 가능**하다.
- **도메인 delta**(트리거 경로, Codex 프롬프트, reviewer critical 기준, phase 불변식, 식별자,
  build/test/run 명령)는 **consumer repo에 남긴다**.
- **plugin은 도메인 결정을 하지 않는다.**

## 당장 사용법

> **아직 설치하거나 적용하지 마세요.**

이 repo는 현재 **설계 검토와 milestone 관리용**이다. 실제 적용은 이후 단계(H1~)에서 사람 확인 게이트를
거쳐 진행한다.

## 문서

- [`docs/design.md`](docs/design.md) — 공통화 후보(C1~C4) / skills 후보 / 금지 원칙
- [`docs/milestones.md`](docs/milestones.md) — H0~H5 단계 계획
- [`docs/consumer-contract.md`](docs/consumer-contract.md) — consumer profile 주입 방식 후보
- [`skills/codex-gate-authoring/SKILL.md`](skills/codex-gate-authoring/SKILL.md) — codex-gate 저작 레시피
