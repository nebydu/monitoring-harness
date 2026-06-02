# monitoring-harness

`hub`, `script-agent`, `monitoring-meta` 세 repo가 각자의 `.claude/` 아래에서 거의 동일하게
**3벌로 손유지**하던 Claude Code / Codex 하네스 공통부를, 향후 하나의 **shared harness plugin**으로
묶기 위한 후보 repo다.

## 목적

세 consumer repo의 `.claude/` 하네스 공통부(예: `codex-gate.sh` 골격, `codex-schema.json`,
`CLAUDE.md` 코어 섹션, agent scaffold)는 사실상 같은 코드를 손으로 세 번 유지하면서 **drift**가
쌓인다. 이 repo는 그 공통부를 plugin/shared로 끌어올려 **drift를 줄이는 것**을 목표로 한다.

## 현재 상태: H4 완료 — script-agent·hub 전환, meta는 예외

- **진행 완료**: H0 부트스트랩/설계 → H1 공통 스키마 1부 → H2-A codex-gate 공통 골격 →
  H5 plugin packaging → **H2-B script-agent cutover** → **H3 hub cutover** → **H4 meta 판단(NO-GO)**.
- **플러그인은 설치 가능한 형태**다(`.claude-plugin/marketplace.json` + `plugin.json` + `hooks/`).
  공통 골격 `codex-gate-core.sh`, 공통 스키마, codex-gate 저작 skill을 제공한다.
- **script-agent·hub는 plugin으로 전환 완료**(script-agent `f1092e3`, hub `cb347a9` — native
  `.claude/hooks/codex-gate.sh` 삭제, convention profile 커밋, plugin codex-gate가 Stop 게이트).
- **monitoring-meta는 전환하지 않는다(A안 확정)**. meta gate는 공통 골격의 상위집합(콘텐츠 캐싱·
  2-모드 프롬프트 등)이라 전환이 곧 회귀다. meta는 자체 gate를 유지하며 **drift 관리의 명시적 예외**다
  (근거: [`docs/h4-meta-readiness.md`](docs/h4-meta-readiness.md)). 공통화하려면 core v2 확장(B안, 후속).
- 설치/적용/업데이트 절차는 [`docs/installation.md`](docs/installation.md) 참고.

## 적용 원칙

- **공통부**(언어/위상/금지/호출순서·재시도/결과 스키마/권한 매트릭스 코어, codex-gate 골격, 동일 스키마,
  agent 골격)는 plugin/shared로 **이동 가능**하다.
- **도메인 delta**(트리거 경로, Codex 프롬프트, reviewer critical 기준, phase 불변식, 식별자,
  build/test/run 명령)는 **consumer repo에 남긴다**.
- **plugin은 도메인 결정을 하지 않는다.**

## 당장 사용법

> script-agent·hub는 적용 완료. **monitoring-meta 적용은 사람 확인 게이트(H4)를 거쳐** 판단한다.
> 임의로 일괄 적용하지 말 것.

설치/구성/업데이트는 [`docs/installation.md`](docs/installation.md)를 따른다.

## 문서

- [`docs/installation.md`](docs/installation.md) — 설치·적용·업데이트(sync)·버전 정책·rollback
- [`docs/design.md`](docs/design.md) — 공통화 후보(C1~C4) / skills 후보 / 금지 원칙
- [`docs/milestones.md`](docs/milestones.md) — H0~H5 단계 계획·진행 현황
- [`docs/consumer-contract.md`](docs/consumer-contract.md) — wiring 표준 / profile 주입 / sync 모델
- [`shared/hooks/`](shared/hooks/) — 공통 골격 `codex-gate-core.sh` + profile 예시 + 동등성 기록
- [`skills/codex-gate-authoring/SKILL.md`](skills/codex-gate-authoring/SKILL.md) — codex-gate 저작 레시피
