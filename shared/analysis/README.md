# shared/analysis — proposal-review 공통부

`/proposal-review` command(결정 전 제안 교차 리뷰)의 공통 실행부가 놓이는 디렉터리다.
범위·경계 결정은 [`../../docs/decisions/proposal-review-scope.md`](../../docs/decisions/proposal-review-scope.md) 참고.

| 파일 | 역할 |
|---|---|
| `proposal-review-runner.sh` | 최소 runner: 입력 조립 → read-only `codex exec` → verdict JSON stdout |
| `proposal-review.prompt.md` | Codex 공통 리뷰 프롬프트 (verdict 경계 정의 포함) |

출력 schema는 [`../schemas/proposal-review-schema.json`](../schemas/proposal-review-schema.json)
(schema는 codex-schema.json과 같은 곳에 모은다 — repo convention).

> **codex-gate와의 경계**: codex-gate는 변경 **후** 안전장치(Stop hook, 자동), proposal-review는
> 결정 **전** 합의 장치(command, 명시 호출). runner에 state/escalation이 없는 것은 의도된 설계다 —
> command는 대화형이라 실패하면 시끄럽게 실패하고 사람이 재시도한다.

consumer 문맥 주입(선택): `<repo>/.claude/proposal-review.profile`에
`PROPOSAL_REVIEW_CONTEXT_DOCS`(배열)·`PROPOSAL_REVIEW_POLICY`(문자열)를 정의한다.
profile이 없으면 degraded 실행되고 그 사실이 출력 JSON `context` 필드에 남는다.
