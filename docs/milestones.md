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

- **목표**: codex-gate.sh 공통 골격 + profile 주입 방식 prototype을 만들고 **script-agent 1개에만**
  시범 적용.
- **산출물**: `shared/hooks/` 공통 골격, script-agent용 profile 예시, 적용 전/후 동작 동등성 기록.
- **하지 않는 것**: hub/meta 적용. script-agent 외 repo 수정.
- **사람 확인 게이트**: script-agent에서 기존 codex-gate와 **동작 동등** 확인 후에만 적용 유지.
- **rollback 기준**: script-agent `.claude/`는 git으로 즉시 원복. plugin 골격은 사본 유지(미참조 상태로 회귀).

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

## H5 — plugin packaging / installation 문서화

- **목표**: plugin 설치·활성화·버전 관리 절차를 문서화하고 manifest를 실제 활성 형태로 정리.
- **산출물**: 설치/적용 가이드, 활성화된 `plugin.json`(hooks/agents 참조 포함), 버전 정책.
- **하지 않는 것**: 검증되지 않은 consumer를 일괄 전환하지 않는다.
- **사람 확인 게이트**: packaging/활성화 manifest 검토.
- **rollback 기준**: manifest를 비활성(H0 형태)으로 되돌리고 consumer는 각자 `.claude/`로 회귀.
