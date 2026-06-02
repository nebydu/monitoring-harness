# 마일스톤: H0 ~ H5

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
- **산출물**: `shared/schemas/codex-schema.json`(LF 정본) + `shared/schemas/equivalence-check.md`
  (동등성 검증 노트) + 루트 `.gitattributes`(`*.json text eol=lf`).
- **하지 않는 것**: consumer가 이 공통 스키마를 **참조하도록 바꾸지 않는다**(여전히 각자 사본 사용).
- **사람 확인 게이트**: 공통 스키마가 세 repo 사본과 동등함을 확인.
- **검증 결과**: 내용은 세 repo 동일(CR 제거 정규화 sha256 일치). 단, hub만 CRLF(484B), 나머지 둘은
  LF(462B). 공통 1부는 LF를 정본으로 채택. consumer 무수정(read-only 비교).
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
- **H2-B 런타임 동등성 검증 완료, 라이브 cutover 대기**:
  wiring 표준(H5: plugin 모델 + consumer profile, 상태 `${CLAUDE_PLUGIN_DATA}`)으로 적용 구성.
  - consumer delta `script-agent/.claude/codex-gate.profile` 스테이징(미추적, inert), manifest에
    `userConfig.profile` 선언.
  - **런타임 동등성 검증 통과**: 샌드박스에서 원본 gate vs plugin(entry→profile→core)을 동일 시나리오로
    비교 — pass/fail/parse_error/skip 전부 exit·verdict 일치([`../shared/hooks/h2b-validation.md`](../shared/hooks/h2b-validation.md)).
  - **라이브 활성화는 미수행**: 플러그인 활성화는 재시작 필요 → 사용자 세션에서 cutover(install
    `--config profile=` + 기존 Stop hook 비활성) 후 검증. script-agent `.claude/hooks/codex-gate.sh`가
    아직 source of execution.

---

## H3 — script-agent 검증 후 hub 적용 여부 판단

- **목표**: H2 시범 적용을 일정 기간 검증한 뒤 hub 적용 여부를 **판단**한다.
- **산출물**: 검증 결과 보고(드리프트/회귀 유무) + hub 적용 가부 결정 기록.
- **하지 않는 것**: 검증 불충분 시 hub 적용을 강행하지 않는다.
- **사람 확인 게이트**: hub 적용 여부는 사람이 결정.
- **rollback 기준**: hub 적용 시에도 hub `.claude/` git 원복으로 즉시 회귀.

---

## H4 — monitoring-meta 적용 여부 판단

- **목표**: meta는 3역할·코드 미실행 등 특성이 달라, 공통 골격 적용 적합성을 별도 **판단**한다.
- **산출물**: meta 적합성 분석 + 적용 가부 결정 기록.
- **하지 않는 것**: meta 도메인 판단(spec drift 등)을 plugin으로 끌어올리지 않는다.
- **사람 확인 게이트**: meta 적용 여부는 사람이 결정.
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
  - **버전 정책 확정**: 빠른 반복(H2~H4)은 commit-SHA(=`version` 생략), 정식 릴리스는 explicit
    semver + bump 규율. `plugin.json` `version` 고정 시 bump 없이는 전파되지 않는 함정을 명시.
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
- **미수행(설치 검증 = H2-B)**: Windows shim 경유 end-to-end Stop hook 실행, `user_config.profile` 선언 키
  확정, `codex exec` 실연동, settings.json 영향. consumer 무수정 유지.
