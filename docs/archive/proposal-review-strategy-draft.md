# proposal-review 전략 검토 요청

monitoring-harness에 `proposal-review` 기능을 추가하는 전략을 검토해줘.

## 배경

현재 `codex-gate`는 코드 변경 후 Stop hook에서 Codex가 자동 리뷰를 수행하는 구조라서 효과가 좋다.
하지만 문서/설계/운영 결정은 코드 변경 이후보다 "변경 전 분석 단계"에서 문제가 생기는 경우가 많다.

실제 업무 흐름은 다음처럼 수동 ping-pong이 필요했다.

1. Claude가 운영/설계 제안을 함
2. 그 제안을 사용자가 Codex에 복사해서 재검토
3. Codex 의견을 다시 Claude에 전달
4. 몇 번 반복해서 두 모델 의견이 수렴하면 적용

이 수동 절차를 harness 엔지니어링 관점에서 줄이고 싶다.

## 제안 방향

`codex-gate`와 별도로, plugin slash command 기반의 `proposal-review`를 추가한다.

예상 사용 방식:

```text
/proposal-review
/proposal-review docs/decisions/h6-core-v2-proposal.md
```

이 기능은 Stop hook처럼 모든 문서 변경을 자동 차단하는 게 아니라, 사용자가 적용 전 분석 단계에서 명시적으로 호출하는 command형 도구로 시작한다.

## 목표

`proposal-review`는 "문서 변경 후 리뷰"가 아니라 "결정 전 제안 리뷰"를 담당한다.

대상 예시:

- 운영 정책 변경
- version 정책 변경
- plugin 구조 변경
- H4/H5/H6 같은 milestone 판단
- archive/decision 문서 이동
- A/B/C안 중 선택이 필요한 결정
- Claude 제안을 바로 repo에 반영하기 전에 다른 모델 검토가 필요한 경우

단순 오타, 링크 수정, 문장 다듬기까지 자동 gate를 걸지는 않는다.

## 구조 제안

plugin 내부에 다음 구조를 추가한다.

```text
monitoring-harness/
  commands/
    proposal-review.md
  shared/
    analysis/
      proposal-review.schema.json
      proposal-review.prompt.md
      proposal-review-runner.sh
```

역할:

- `commands/proposal-review.md`
  - Claude Code slash command 정의
  - 사용자가 `/proposal-review` 호출 시 Claude가 따라야 하는 절차 설명
- `shared/analysis/proposal-review-runner.sh`
  - Codex를 read-only로 호출하는 실행부
  - proposal 입력을 받아 schema 기반 JSON verdict를 받음
- `shared/analysis/proposal-review.schema.json`
  - Codex 응답 형식 고정
- `shared/analysis/proposal-review.prompt.md`
  - Codex에게 줄 공통 리뷰 프롬프트

## 예상 흐름

1. 사용자가 `/proposal-review` 호출
2. Claude가 현재 요청/변경 의도/대안/가정/리스크를 proposal 형태로 정리
3. runner가 `codex exec`를 read-only로 실행
4. Codex가 아래 verdict 중 하나를 반환
   - `approve`
   - `revise`
   - `block`
5. Claude가 Codex 리뷰 결과를 사용자에게 보여줌
6. `revise`나 `block`이면 적용하지 않고 제안을 다시 다듬음

## 입력 스키마 초안

proposal에는 최소 다음 필드를 둔다.

```yaml
context:
proposal:
alternatives:
assumptions:
risks:
decision_needed:
```

## 출력 스키마 초안

Codex 응답은 JSON으로 고정한다.

```json
{
  "verdict": "approve | revise | block",
  "critical_findings": [],
  "missing_context": [],
  "recommended_changes": [],
  "confidence": "low | medium | high"
}
```

## repo별 문맥 주입

공통 command/runner에는 도메인 정책을 하드코딩하지 않는다.

repo별 문맥은 consumer repo의 convention profile로 주입한다.

예:

```text
.claude/proposal-review.profile
```

예시:

```bash
PROPOSAL_REVIEW_CONTEXT_DOCS=(
  "../monitoring-meta/docs/통합본_v0_9.md"
  "docs/installation.md"
  "docs/milestones.md"
)

PROPOSAL_REVIEW_POLICY="runtime harness plugin 정책 변경은 script-agent/hub 영향과 meta 제외 결정을 함께 검토한다."
```

## codex-gate와의 경계

- `codex-gate`
  - 변경 후 안전장치
  - Stop hook 기반
  - 코드/런타임 변경 중심
- `proposal-review`
  - 변경 전 합의 장치
  - slash command 기반
  - 문서/정책/설계/운영 결정 중심

둘을 합치지 않는다. Stop hook이 무거워지면 문서 작업 전체의 마찰이 커지기 때문이다.

## 검토 요청

다음 관점에서 이 전략을 검토해줘.

1. Claude Code plugin command 구조로 구현 가능한가?
2. `commands/proposal-review.md` + runner + schema 구조가 적절한가?
3. repo별 profile 주입 모델이 `codex-gate`의 consumer profile 모델과 일관적인가?
4. `codex exec` read-only 호출을 command에서 사용하는 방식에 문제가 없는가?
5. 자동 loop를 바로 넣지 않고 수동 command로 시작하는 판단이 맞는가?
6. verdict를 `approve | revise | block`으로 두는 게 충분한가?
7. 이 기능이 monitoring-harness의 범위를 벗어나지는 않는가?
8. 더 단순하거나 더 안전한 MVP 구조가 있다면 제안해줘.
