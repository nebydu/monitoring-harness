# monitoring-harness

`hub`, `script-agent`, `monitoring-meta` 세 repo가 각자의 `.claude/` 아래에서 거의 동일하게
**3벌로 손유지**하던 Claude Code / Codex 하네스 공통부를, 향후 하나의 **shared harness plugin**으로
묶기 위한 후보 repo다.

## 목적

세 consumer repo의 `.claude/` 하네스 공통부(예: `codex-gate.sh` 골격, `codex-schema.json`,
`CLAUDE.md` 코어 섹션, agent scaffold)는 사실상 같은 코드를 손으로 세 번 유지하면서 **drift**가
쌓인다. 이 repo는 그 공통부를 plugin/shared로 끌어올려 **drift를 줄이는 것**을 목표로 한다.

## 적용 범위: 2축 — runtime gate + decision-review command

이 플러그인은 두 축을 제공한다 (근거: [`docs/decisions/proposal-review-scope.md`](docs/decisions/proposal-review-scope.md)):

| | ① codex-gate | ② proposal-review |
|---|---|---|
| 시점 | 변경 **후** 안전장치 | 변경/결정 **전** 합의 장치 |
| 발동 | Stop hook (자동) | `/proposal-review` command (명시 호출) |
| 대상 | 코드/런타임 변경 | 문서·정책·설계·운영 결정 |
| 소비자 | **script-agent·hub 전용** (전환 완료) | profile 둔 모든 repo (**meta 포함 가능**) |

①의 대상은 **코드를 실행하는 런타임 하네스**다. **monitoring-meta는 코드를 실행하지 않고
spec 일관성을 판정**하는 다른 범주라 ①의 적용 대상이 아니다(드리프트 "예외"가 아니라 범주 경계,
H4). 단 ②는 runtime gate가 아니므로 meta도 convention profile만 두면 소비자가 될 수 있다.

## 현재 상태: H6 진행 — 런타임 하네스(sa·hub) 전환 완료 + proposal-review 추가

- **진행 완료**: H0 부트스트랩/설계 → H1 공통 스키마 1부 → H2-A codex-gate 공통 골격 →
  H5 plugin packaging → **H2-B script-agent cutover** → **H3 hub cutover** → **H4 meta 범주 판단**
  → **H6 proposal-review** (scope 결정·MVP 구현 완료, consumer 실전 검증 남음).
- **플러그인은 설치 가능한 형태**다(`.claude-plugin/marketplace.json` + `plugin.json` + `hooks/`).
  공통 골격 `codex-gate-core.sh`, 공통 스키마, `/proposal-review` command, codex-gate 저작 skill을
  제공한다.
- **script-agent·hub는 plugin으로 전환 완료**(script-agent `f1092e3`, hub `cb347a9` — native
  `.claude/hooks/codex-gate.sh` 삭제, convention profile 커밋, plugin codex-gate가 Stop 게이트).
  두 repo 모두 라이브 Stop 동작 테스트까지 확인했다.
- **monitoring-meta는 적용 대상이 아니다(범주 외)**. meta는 코드 미실행·spec 판정 도메인이고, 그
  gate는 공통 골격의 상위집합(콘텐츠 캐싱·2-모드 프롬프트 등)으로 진화해 있다. 즉 meta는 *드리프트
  관리에 실패한 예외*가 아니라, 애초에 이 런타임 하네스 플러그인의 **범주가 아닌** 산출물이다
  (근거: [`docs/decisions/h4-meta-readiness.md`](docs/decisions/h4-meta-readiness.md)). meta까지 정식 통합이 **필요해질 때만**
  core v2 확장(B안, 후속)을 검토한다.
- 설치/적용/업데이트 절차는 [`docs/installation.md`](docs/installation.md) 참고.

## 적용 원칙

- **공통부**(언어/작업 상태/금지/호출순서·재시도/결과 스키마/권한 매트릭스 코어, codex-gate 골격, 동일 스키마,
  agent 골격)는 plugin/shared로 **이동 가능**하다.
- **도메인 delta**(트리거 경로, Codex 프롬프트, reviewer critical 기준, phase 불변식, 식별자,
  build/test/run 명령)는 **consumer repo에 남긴다**.
- **plugin은 도메인 결정을 하지 않는다.**

## 당장 사용법

> 대상은 **런타임 하네스**다. script-agent·hub는 적용 완료. **monitoring-meta는 범주 외**라 적용하지
> 않는다(H4). 새 consumer가 코드 실행 하네스라면 동일 절차로 적용한다.

설치/구성/업데이트는 [`docs/installation.md`](docs/installation.md)를 따른다.

## 문서

- [`docs/installation.md`](docs/installation.md) — 설치·적용·업데이트(sync)·버전 정책·rollback
- [`docs/milestones.md`](docs/milestones.md) — H0~H6 단계 계획·진행 현황
- [`docs/consumer-contract.md`](docs/consumer-contract.md) — wiring 표준 / profile 주입 / sync 모델
- [`docs/decisions/`](docs/decisions/) — 현재 운영 결정 근거
- [`docs/archive/`](docs/archive/) — 완료된 분석·초기 설계 기록
- [`shared/hooks/`](shared/hooks/) — 공통 골격 `codex-gate-core.sh` + profile 예시 + 동등성 기록
- [`shared/analysis/`](shared/analysis/) — `/proposal-review` runner + 공통 프롬프트
- [`skills/codex-gate-authoring/SKILL.md`](skills/codex-gate-authoring/SKILL.md) — codex-gate 저작 레시피
