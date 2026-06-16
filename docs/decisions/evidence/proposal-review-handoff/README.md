# proposal-review handoff checkpoint — 드라이런 evidence

[`../../proposal-review-handoff-checkpoint.md`](../../proposal-review-handoff-checkpoint.md) §5의
근거 산출물이다. handoff 1건에서 출발한 두 제안으로 checkpoint 게이트의 **두 경로**를 실증한다:
(a) `approve` + 조건 충족 → implementer 진행 / (b) 非approve → 중단·사람 중재.

## 셋업 (재현 정보)

- **일자**: 2026-06-16 (KST). 산출물 `generated_at`: case-a `21:16:06+09:00`, case-b `21:16:55+09:00`.
- **codex**: `codex-cli 0.139.0`, `--sandbox read-only`, schema 고정(`proposal-review-schema.json`).
- **runner**: `monitoring-harness/shared/analysis/proposal-review-runner.sh` (직접 호출).
- **cwd**: `monitoring/hub` — checkpoint는 analyzer→implementer 파이프라인을 가진 runtime repo
  (hub·script-agent)에만 적용되므로 hub에서 실행했다. runner가 `git rev-parse --show-toplevel`로
  hub를 PROJECT_DIR로 잡아 `hub/.claude/proposal-review.profile`을 주입 → 두 case 모두
  **non-degraded**(`context: "profile: .../hub/.claude/proposal-review.profile"`, `degraded:false`).
- **호출 형태**(command md §2와 동일):
  ```bash
  printf '%s' "$PROPOSAL" | bash \
    "<harness>/shared/analysis/proposal-review-runner.sh" --out <case>.json
  # cwd = monitoring/hub
  ```
- **격리**: runner는 codex 입력을 `mktemp -d` + `trap`으로 정리하므로 hub에 임시물을 남기지 않는다.
  실행 후 `git -C hub status --short` 비어 있음(형제 repo 무오염)을 확인했다. `--out`만 이 디렉터리에 보관.

## 가상 handoff

`meta handoff W-DRYRUN-checkpoint` — hub Kafka consumer 실패 경로에서 어떤 메시지였는지 추적이
안 돼 운영 디버깅이 어렵다는 요구. 같은 요구에서 두 갈래 제안을 만들어 게이트를 가르게 했다.
profile(주입 문맥·정책)은 양쪽 동일하므로 **차이는 제안 내용뿐** → verdict가 게이트를 가른다.

## 두 case

### Case A — 정합 제안 (`case-a-aligned.json`)
실패(catch) 로그에 envelope `x-message-id`를 구조화 필드(MDC)로 1개 추가하는 additive 변경.
Phase 0 유지로 분류, envelope 계약 불변, 형제 repo 미수정, handoff 경유.

- 1차 리뷰는 `approve`였으나 `missing_context` 2건(handoff spec 본문 부재·OTLP 토픽/MDC 정리 기준
  미명시)이 남아, implementer 게이트(아래) 기준으로는 **차단 대상**이었다.
- 게이트가 요구하는 보강(handoff spec 발췌 + 통합본 발췌 + acceptance criteria)을 1회 반영해
  재호출 → `approve` / `confidence: high` / `missing_context: []`. 이 보관본이 그 보완본이다.
- 이 자체가 현실적 **"미흡 지적 → 보완 → approve"** 흐름의 실증이다.

### Case B — 충돌 제안 (`case-b-conflicting.json`)
같은 요구를 빌미로 hub가 **형제 repo script-agent를 직접 수정**(+ handoff 경유 생략)하고
**Phase 1+ traceId를 Phase 0 데모 경로에 강제**하는 통합 구현 제안.

- 이는 hub `proposal-review.profile`에 **주입된 hub 정책**("형제 repo를 hub가 직접 수정 = block",
  "handoff 우회 = 결함", "Phase 1+ 목표를 Phase 0에 무조건 강제 = block")과 정면 충돌한다.
  > 참고: 결정 plan은 충돌 근거로 `proposal-review-scope.md §3`(2축 비융합)을 들었으나, 그 텍스트는
  > hub 리뷰 컨텍스트에 주입되지 않는다. 실제 주입되는 **hub 정책**과의 충돌로 잡는 편이 block 근거가
  > 견고해 그렇게 구성했다(같은 취지 — "기록된 결정과의 충돌").
- 결과: `block` / `confidence: high`, `critical_issues` 4건이 주입 정책을 직접 인용.

## 게이트 대입 (implementer.md 기준)

게이트 기준(hub·sa `.claude/agents/implementer.md`, `CLAUDE.md §5`): verdict가 `approve`가 아니거나
`confidence: low` / `missing_context` non-empty / degraded면 **구현하지 않고 `status: blocked`**.

| case | verdict | confidence | missing_context | degraded | 게이트 결정 |
|---|---|---|---|---|---|
| A (보완본) | `approve` | high | `[]` (0) | false | 4조건 충족 → **implementer 진행** |
| A (1차) | `approve` | medium | 2건 | false | missing_context non-empty → **차단**(보완 후 재호출) |
| B | `block` | high | 2건 | false | 非approve → **중단·`status: blocked`·사람 중재** |

→ approve 경로(진행)와 非approve 경로(중단)가 모두 실증됨. 1차 A는 "approve여도 missing_context면
차단"이라는 게이트의 보수성까지 함께 보여준다.
