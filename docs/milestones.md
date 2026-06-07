# 마일스톤: H0 ~ H6

각 단계는 **목표 / 산출물 / 하지 않는 것 / 사람 확인 게이트 / rollback 기준**으로 기술한다.
모든 단계 전환은 사람 확인을 거친다. consumer 적용은 항상 **점진적·역진 가능**해야 한다.

---

## H0 — bootstrap / design only (완료)

- **목표**: 공통화 후보 식별 + 최소 골격(plugin manifest, placeholder, 설계/마일스톤/계약 문서) 작성.
- **산출물**: `.claude-plugin/plugin.json`, `README.md`, `docs/*`, `shared/*/README.md`,
  `skills/codex-gate-authoring/SKILL.md`, `.gitignore`.
- **하지 않는 것**: hook 공통화 구현, agent migration, `codex-schema.json` 복사, consumer 적용.
- **사람 확인 게이트**: 설계(C1~C4) 방향 승인.
- **rollback 기준**: harness repo 내부 파일만 생성 → 디렉터리 삭제로 즉시 원복. consumer 무영향.

---

## H1 — C3 schema 공통화 후보 구현 (consumer 적용 없음) (완료)

- **목표**: 세 repo 동일한 `codex-schema.json`을 `shared/schemas/`에 **공통 1부**로 둔다.
- **산출물**: `shared/schemas/codex-schema.json`(LF 기준) + `shared/schemas/equivalence-check.md`
  (동등성 검증 노트) + 루트 `.gitattributes`(`*.json text eol=lf`).
- **하지 않는 것**: consumer가 이 공통 스키마를 **참조하도록 바꾸지 않는다**(여전히 각자 사본 사용).
- **사람 확인 게이트**: 공통 스키마가 세 repo 사본과 동등함을 확인.
- **검증 결과**: 내용은 세 repo 동일(CR 제거 정규화 sha256 일치). 단, hub만 CRLF(484B), 나머지 둘은
  LF(462B). 공통 1부는 LF를 기준으로 채택. consumer 무수정(read-only 비교).
- **rollback 기준**: `shared/schemas/`·`.gitattributes`만 추가됨 → 파일 삭제로 원복. consumer 무영향.

---

## H2 — C1 codex-gate 공통 골격 prototype (script-agent에만 시범 적용)

H2는 두 부분으로 나뉜다: **H2-A**(harness 내부 골격·profile·동등성 기록, 게이트 없음) /
**H2-B**(script-agent 실제 시범 적용, 사람 확인 게이트).

- **목표**: codex-gate.sh 공통 골격 + profile 주입 방식 prototype을 만들고 **script-agent 1개에만**
  시범 적용.
- **산출물**: `shared/hooks/` 공통 골격, script-agent용 profile 예시, 적용 전/후 동작 동등성 기록.
- **하지 않는 것**: hub/meta 적용. script-agent 외 repo 수정.
- **사람 확인 게이트**: script-agent에서 기존 codex-gate와 **동작 동등** 확인 후에만 적용 유지.
- **rollback 기준**: script-agent `.claude/`는 git으로 즉시 원복. plugin 골격은 사본 유지(미참조 상태로 회귀).

### 진행 현황

- **H2-A 완료**: `shared/hooks/codex-gate-core.sh`(주입점 분리 공통 골격),
  `profiles/script-agent.profile.example`, `codex-gate.wrapper.example.sh`, `equivalence.md` 작성.
  정적 검증(`bash -n`, 주입점 가드 양방향, `match_any` 트리거/스킵 판정 == 원본 case-list) 통과.
- **H2-B 완료 (script-agent cutover 전환 완료)**:
  wiring 표준(H5: plugin 모델 + **convention 경로** profile, 상태 `${CLAUDE_PLUGIN_DATA}`)으로 적용.
  - consumer delta `script-agent/.claude/codex-gate.profile` 커밋됨, project scope 설치(enabledPlugins 기록).
  - **런타임 동등성 검증 통과**: 샌드박스에서 원본 gate vs plugin(entry→profile→core) — pass/fail/parse_error/
    skip 전부 exit·verdict 일치([`../shared/hooks/h2b-validation.md`](../shared/hooks/h2b-validation.md)).
  - **project scope gotcha 해결**: profile을 convention 경로로 바꿔 per-user config·절대경로 제거
    (`userConfig` 삭제). 무인자 convention 케이스 exit 0 검증. → 협업자 공유 안전.
  - **cutover 완료**: script-agent가 commit `f1092e3`에서 native `.claude/hooks/codex-gate.sh` **삭제**,
    settings.json의 Stop hook 제거(`PreToolUse`만 유지)·`enabledPlugins` 기록, profile 커밋. 이제
    **plugin codex-gate가 script-agent Stop 게이트의 source of execution**이다(단일 게이트).

---

## H3 — script-agent 검증 후 hub 적용 여부 판단 (완료 — hub 전환됨)

- **목표**: H2 시범 적용을 일정 기간 검증한 뒤 hub 적용 여부를 **판단**한다.
- **산출물**: 검증 결과 보고(드리프트/회귀 유무) + hub 적용 가부 결정 기록.
- **하지 않는 것**: 검증 불충분 시 hub 적용을 강행하지 않는다.
- **사람 확인 게이트**: hub 적용 여부는 사람이 결정.
- **rollback 기준**: hub 적용 시에도 hub `.claude/` git 원복으로 즉시 회귀.

### 진행 현황

- **분석·실증 완료** → [`archive/h3-hub-readiness.md`](archive/h3-hub-readiness.md):
  - script-agent 적용 검증: cutover 완료(`f1092e3`)·런타임 동등성 통과·회귀 신호 없음.
  - hub gate(193줄)는 공통 골격과 구조 동일, 차이는 주입점뿐(+ cosmetic 변이 2건, 무해).
  - **샌드박스 동등성 실증**(hub read-only): 원본 hub gate vs core+hub profile — src/main pass/fail,
    parse_error, docs skip, pom.xml trigger **5/5 일치**. profile 예시 `profiles/hub.profile.example`.
  - 리스크 점검: PreToolUse `pre-write-guard.sh` 무관, schema CRLF 내용동일, settings.local 무영향,
    project-scope gotcha 해결됨.
  - **권고: GO**(clean 후보) → **사람 승인 후 hub 적용 완료**(`cb347a9`): project scope 설치,
    `hub/.claude/codex-gate.profile` 커밋, native `codex-gate.sh` 삭제, settings.json Stop hook 제거
    (PreToolUse 유지)·enabledPlugins. plugin codex-gate가 hub Stop 게이트(라이브 발화는 재시작 후 적용).

---

## H4 — monitoring-meta 적용 여부 판단 (완료 — A안 확정: meta는 범주 외, 자체 gate 유지)

- **목표**: meta는 3역할·코드 미실행 등 특성이 달라, 공통 골격 적용 적합성을 별도 **판단**한다.
- **산출물**: meta 적합성 분석 + 적용 가부 결정 기록.
- **하지 않는 것**: meta 도메인 판단(spec drift 등)을 plugin으로 끌어올리지 않는다.
- **사람 확인 게이트**: meta 적용 여부는 사람이 결정.

### 진행 현황

- **분석·실증 완료** → [`decisions/h4-meta-readiness.md`](decisions/h4-meta-readiness.md):
  - meta gate(278줄)는 hub/sa(193/195줄)와 달리 **공통 골격의 상위집합**으로 진화 — gate_key 콘텐츠
    캐싱(already_passed/escalated SKIP), 2-모드 트리거+프롬프트 병합, 리치 JSON 상태가 core에 없음.
  - **회귀 실증**(meta read-only): 동일 변경 Stop 2회 — meta는 2회차 `skipped(already_passed)`,
    core+profile은 `pass`(Codex 재호출). core 전환 시 캐싱 손실 = 회귀.
  - **결정: NO-GO 확정(A안)** — 이 플러그인은 **런타임(코드 실행) 하네스 전용**이고, meta는 코드 미실행·
    spec 판정 도메인이라 **범주 외**다(드리프트 예외가 아니라 범주 경계). meta는 자체 gate를 유지한다.
    B) core v2로 확장 후 통합은 meta 정식 통합이 필요해질 때만 착수하는 선택적 후속 과제(H6 후보)로 보류.
  - meta 도메인 룰은 consumer에 잔류. meta repo **미수정**.
- **rollback 기준**: meta `.claude/` git 원복으로 즉시 회귀.

---

## H5 — plugin packaging / installation 문서화 (완료)

- **목표**: plugin 설치·활성화·**업데이트(sync) 절차**·버전 관리 정책을 문서화하고 manifest를 실제
  활성 형태로 정리.
- **산출물**:
  - 설치/적용 가이드(`/plugin marketplace add` → `/plugin install`), 활성화된 `plugin.json`
    (hooks/agents 참조 포함).
  - **sync/업데이트 모델 문서화**: 공통 hook 변경 → consumer 반영 경로.
    - plugin은 cache로 복사되므로 in-place 자동 동기화가 아니다. `/plugin update`(또는 auto-update)로만
      반영되고, 세션 중에는 `/reload-plugins` 후 새 hook이 적용된다(이전엔 구 버전 경로 유지).
    - hook 경로는 `${CLAUDE_PLUGIN_ROOT}`, 업데이트를 넘어 보존할 상태(escalation 카운터 등)는
      `${CLAUDE_PLUGIN_DATA}`.
  - **버전 정책 확정**: commit-SHA(=`version` 생략)를 현행 채택(롤아웃 후에도 유지), 정식 릴리스/외부
    배포 시 explicit semver + bump 규율(미결 선택). `plugin.json` `version` 고정 시 bump 없이는 전파되지
    않는 함정을 명시.
    (상세 비교 → [`consumer-contract.md`](consumer-contract.md) "공통부 변경의 sync/업데이트 모델")
- **하지 않는 것**: 검증되지 않은 consumer를 일괄 전환하지 않는다.
- **사람 확인 게이트**: packaging/활성화 manifest + sync·버전 정책 검토.
- **rollback 기준**: manifest를 비활성(H0 형태)으로 되돌리고 consumer는 각자 `.claude/`로 회귀.

### 진행 현황 (완료)

- **마켓플레이스**: `.claude-plugin/marketplace.json`(단일 플러그인). `claude plugin validate --strict` 통과.
- **활성 manifest**: `.claude-plugin/plugin.json`에서 `version` 제거(commit-SHA 채택), author/repository 추가.
- **plugin hook 배선**: `hooks/hooks.json`(Stop) + `hooks/codex-gate-entry.sh`(consumer profile + 공통 골격
  결합, 스키마=plugin 공통 1부, 상태=`${CLAUDE_PLUGIN_DATA}`) + `hooks/git-bash.cmd`(Windows shim).
- **가이드**: [`installation.md`](installation.md) — 설치/구성/업데이트(sync)/버전 정책/rollback + wiring 표준.
- **정적 검증**: JSON parse(plugin/marketplace/hooks), `bash -n` entry, `claude plugin validate --strict` 통과.
- **H2-B에서 적용 완료**: native Stop hook 비활성·plugin 전환 cutover 완료(script-agent `f1092e3`),
  profile 주입은 convention으로 확정(userConfig 불요). script-agent·hub 모두 라이브 Stop 발화·`codex exec`
  실연동 확인 완료.

---

## H6 — proposal-review: decision-review command 추가 (scope 재해석 포함)

> H4의 "core v2 확장(B안)" 후속 후보와는 별개 트랙이다. H6은 meta gate 통합이 아니라
> **plugin의 2축화**(runtime gate + decision-review command)다.

- **목표**: 적용 전 운영/설계/정책 제안을 Codex로 교차 리뷰하는 `/proposal-review` slash command를
  추가한다. 기존 수동 ping-pong(Claude 제안 → 사용자가 Codex에 복사 → 의견 회신 → 반복)을 줄인다.
- **범위 재해석(선행 결정)**: H4가 제외한 것은 *meta의 Stop hook 기반 runtime codex-gate 통합*이고,
  proposal-review는 runtime gate가 아닌 명시 호출 command이므로 H4 A안과 충돌하지 않는다.
  **meta 포함 모든 repo가 convention profile로 소비자가 될 수 있다**
  (근거: [`decisions/proposal-review-scope.md`](decisions/proposal-review-scope.md)).
- **산출물**: `commands/proposal-review.md`, `shared/analysis/proposal-review-runner.sh`(+prompt),
  `shared/schemas/proposal-review-schema.json`, scope 결정 문서, plugin.json 2축 description.
- **하지 않는 것**: Stop hook 자동 발동(문서 작업 마찰), codex-gate core의 state/escalation 이식(과설계),
  두 모델 간 자동 수렴 loop(진동 위험 — 반복은 사람이 중재).
- **사람 확인 게이트**: scope 재해석 승인(완료), 구현 후 consumer 실전 1회 결과 검토.
- **rollback 기준**: commands/·shared/analysis/·schema 파일 삭제로 원복. codex-gate 경로와 독립
  (entry/core/hooks.json 무변경). consumer는 profile 파일 삭제만으로 이탈.

### 진행 현황

- **scope 결정 완료** → [`decisions/proposal-review-scope.md`](decisions/proposal-review-scope.md):
  H4 재해석 + plugin 2축 정의 + profile 부재 = degraded 실행(시끄럽게) + MVP 구조 확정.
- **MVP 구현 완료**: command + 최소 runner(state 없음, `--out` 아티팩트 옵션) + prompt + schema
  (`critical_issues` 어휘 통일, flat + 전 필드 required). `bash -n`·JSON parse·plugin validate 통과
  (version 경고는 commit-SHA 정책의 기존 트레이드오프).
- **스모크 테스트 통과(소스 기준, Git Bash 실연동)**: 가드 4종(빈 stdin/오인자/명시 profile
  부재=exit 2) + `codex exec` 2회 — 같은 제안이 degraded `revise`(medium) → consumer-contract.md
  문맥 주입 후 `block`(high, H5 결정 충돌 사유)으로 판정돼 verdict 경계 실증. `--out` 아티팩트 정상.
- **plugin manifest 2축 갱신**: plugin.json/marketplace.json description, README 분리 설명.
  전략 초안은 `archive/proposal-review-strategy-draft.md`로 이동(결정본 = scope 결정 문서).
- **배포 캐시 기준 검증 완료**(캐시 `62b896287963`): 캐시 runner 가드·codex-gate 회귀 3종·라이브
  `/proposal-review` 호출 통과. 라이브 검증에서 `CLAUDE_PROJECT_DIR`(hook 전용 변수) 함정 발견 →
  `git rev-parse` fallback으로 수정(`a455246`, scope 결정 §6에 교훈 기록).
- **consumer 실전 1회 완료(meta)**: `.claude/proposal-review.profile`(문맥 6개, 통합본 발췌 원칙)
  주입 리뷰 동작 확인. verdict `revise` 권고를 profile에 반영. prompt/schema 조정 불요.
- 남은 것: 각 머신에서 `/plugin update`로 `a455246`+ 반영(이전 캐시에서는 command가 degraded로만
  동작 — 깨지진 않음).
