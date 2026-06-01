# 설계: shared harness 공통화 후보 (H0, 설계만)

> 이 문서는 **설계만** 기술한다. H0에서는 어떤 것도 구현하지 않는다.
> 공통화 후보를 식별하고, 무엇을 공통부로 올리고 무엇을 consumer delta로 남기는지의 경계만 정의한다.

세 consumer repo(`hub`/`script-agent`/`monitoring-meta`)의 `.claude/` 탐색 결과를 근거로,
공통화 후보를 C1~C4로 나눈다.

---

## C1. hook 골격 (codex-gate.sh)

세 repo의 `codex-gate.sh`는 다음 골격이 **동일**하고, 일부 값만 repo별로 다르다.

### 공통 골격 (plugin 후보)

- 경로 정의 (state / log / escalation / schema / last-message / issues / stderr)
- `log_line()` — `timestamp | verdict | crit_count | viol_count | triggered_files` TSV 기록
- `emit_system_message()` — python으로 UTF-8 JSON 출력 (Windows cp949 회피)
- `escalate()` — force-pass escalation + escalation log 기록
- state 카운터 — `read_state` / `write_state` / `reset_state` (fail / parse-fail 누적)
- **baseline 커밋 트리거** — baseline 대비 변경분 기준 리뷰 입력 조립
- **stop-loop 가드** — 입력 JSON의 `stop_hook_active` 확인 후 조기 종료
- **pipefail 가드** — `set -euo pipefail` + 빈 입력 안전 처리
- **read-only codex exec** — `codex exec --sandbox read-only --output-schema ...`
- **python JSON 파싱** — Codex 응답에서 `verdict` / `critical_issues` / `spec_violations` 추출
- verdict 분기 — pass(reset+emit+exit0) / fail(카운터++ → 임계 초과 시 escalate, 아니면 block)
- parse-fail 처리 — 연속 parse 실패 임계 시 escalate, 성공 시 reset

### repo별 주입점 (consumer delta — 공통부로 올리지 않음)

| 주입점 | hub | script-agent | monitoring-meta |
|---|---|---|---|
| trigger case-list | `src/main/*`, `src/test/*`, `pom.xml` | `cmd/*`, `internal/*`, `go.mod`, `go.sum`, `*.go` | `adr/*.md`, `docs/*.md` |
| skip paths | `.claude/*`, `docs/*`, `analysis/*` | `.claude/*`, `docs/*`, `analysis/*` | `phase0-snapshot/*`, handoff, e2e, `.claude/*` |
| Codex prompt | Java/Spring 7-point review | Go + Kafka 불변식 review | spec/envelope/payload 정합성 |
| 발화 대상 경로 | hub 비즈니스 코드 | script-agent Go 코드 | meta spec 문서 |
| build/test/run 명령 | (Maven 계열) | (Go 계열) | (코드 실행 없음) |

> 주입점은 **plugin이 결정하지 않는다.** consumer가 profile로 주입한다
> (→ [`consumer-contract.md`](consumer-contract.md)).

---

## C2. CLAUDE.md 공통 코어

세 repo의 `.claude/CLAUDE.md`는 §0~§9 섹션 골격이 동일하다. 다음을 **공통 코어 후보**로 본다.

- 언어 규칙 (응답/문서/주석 = 한국어, 식별자 = 영어)
- 위상(phase) 경고 (Phase 0 demo vs Phase 1+ target, ground truth 우선순위)
- 작업 입력 형식 (read-only handoff 경로, work-id 바인딩 계약)
- 금지 사항 (repo 교차 쓰기 금지, 자동 갱신 금지, Open 결정 금지)
- 표준 호출 순서 / 재시도 한도 (analyzer → implementer → tester → reviewer+spec-guardian → refactorer)
- 결과 스키마 (`status | outputs | findings | blockers | next_action`)
- 권한 매트릭스 (역할별 read/write 범위)

### consumer delta (남김)

- 역할 수/구성 (hub·script-agent = 6역할, meta = 3역할)
- write 권한 경로 (`src/**` vs `cmd|internal/**` vs `docs|adr|handoff/**`)
- 도메인 불변식 (모듈 경계 / Job 실행 규칙 / Open·ADR drift)

---

## C3. codex-schema.json

세 repo의 `.claude/codex-schema.json`은 **내용이 동일**하다
(`verdict` / `critical_issues` / `spec_violations` / `summary`, `additionalProperties: false`).
단 줄바꿈은 다르다 — hub만 CRLF(484B), script-agent·monitoring-meta는 LF(462B)다. CR을 제거한
정규화 기준에서 세 repo 해시가 모두 일치한다(엄밀한 byte-for-byte 동일은 아님). H1 검증 결과는
[`../shared/schemas/equivalence-check.md`](../shared/schemas/equivalence-check.md) 참고.

→ **공통 1부 후보**(H1에서 LF 정본으로 확정). H0에서는 복사하지 않고 위치만 예약했고, 실제 공통화는
H1에서 다뤘다 (→ [`../shared/schemas/README.md`](../shared/schemas/README.md)).

---

## C4. agent scaffold

`hub`/`script-agent`는 analyzer / implementer / tester / reviewer / spec-guardian / refactorer
**6역할** 골격이 동일하다 (frontmatter: `name`/`description`/`tools`/`model`, 동일 결과 스키마,
"외부 surface" 섹션).

### 공통화 후보 (골격)

- 6역할 scaffold 골격
- 역할별 도구 권한 형태
- 호출 순서 / 재시도 한도

### consumer delta (남김)

- reviewer **critical** 판정 기준 (예: hub §7.2 β 모듈 경계 위반)
- spec-guardian **도메인 판단** (phase 분류, envelope 헤더 준수 등)
- **phase 불변식** (Phase 0/1 구분, Job 실행 6규칙 등)

> `monitoring-meta`는 3역할(analyzer/spec-sync/e2e-tester)로 6역할과 구성이 달라, 공통 scaffold
> 적용 여부는 별도 판단(H4)으로 미룬다.

---

## skills 후보

### codex-gate-authoring (이번 H0에서 작성)

hook을 작성·수정할 때 참고하는 레시피. 알려진 함정을 명시한다.

- `set -euo pipefail` + `grep` 빈 입력 (빈 매치 시 비정상 종료)
- schema `required` / 400 (스키마 위반 응답)
- SIGPIPE (파이프 조기 종료)
- CRLF (Windows 줄바꿈)
- Windows Git Bash vs WSL bash (PATH 충돌, shim 필요)
- stdout JSON encoding (cp949 vs UTF-8)

→ [`../skills/codex-gate-authoring/SKILL.md`](../skills/codex-gate-authoring/SKILL.md)

### 공유 도메인 참조 데이터 skill (조건부)

- **후보**: envelope 8토픽 payload 표, 모듈 경계 표 (단순 참조 데이터)
- **단**: **안전 판단 룰은 skill로 빼지 않는다.** verdict를 좌우하는 판단(트리거 여부, critical 기준,
  phase 불변식)은 consumer의 `CLAUDE.md`/agent에 남긴다.

---

## 금지 원칙

1. 다음은 **공통부로 끌어올리지 않는다**: 트리거 경로, Codex 프롬프트, reviewer critical 기준,
   phase 불변식, 식별자, build command.
2. **plugin은 도메인 결정을 하지 않는다.** 공통 골격은 "어떻게 실행하는가"만 제공하고,
   "무엇이 위반인가"는 consumer가 정한다.
3. **consumer repo 적용은 H0 범위 밖이다.** (→ [`milestones.md`](milestones.md))
