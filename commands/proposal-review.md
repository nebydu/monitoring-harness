---
description: 적용 전 운영/설계/정책 제안을 Codex로 교차 리뷰 (결정 전 합의 장치)
argument-hint: "[제안 문서 경로 (생략 시 현재 대화의 제안을 정리)]"
---

# /proposal-review — 결정 전 제안 교차 리뷰

사용자가 적용 전 분석 단계에서 명시적으로 호출하는 decision-review command다.
codex-gate(변경 후 안전장치)와 다르다 — 이것은 **변경/결정 전 합의 장치**다.
경계와 결정 근거: `docs/decisions/proposal-review-scope.md` (harness repo).

## 절차

### 1. proposal 정리

- 인자(`$ARGUMENTS`)로 파일 경로가 주어지면: 그 파일을 읽어 proposal 본문으로 쓴다.
- 인자가 없으면: **현재 대화에서 검토 대상인 제안**을 아래 구조로 정리한다.

```yaml
context:          # 어떤 상황에서 나온 제안인가
proposal:         # 제안 내용 (구체적으로)
alternatives:     # 검토했던 대안과 기각 이유
assumptions:      # 이 제안이 전제하는 가정
risks:            # 식별된 리스크와 되돌리기 경로
decision_needed:  # 정확히 무엇을 결정해야 하는가
```

빈 필드는 비워두지 말고 "없음" 또는 "미검토"로 명시한다 (Codex가 공백과 누락을 구분하게).

### 2. runner 실행

proposal을 **stdin으로** 전달한다 (argv 금지 — 명령행 길이 제한). Bash tool로:

```bash
printf '%s' "$PROPOSAL" | bash "${CLAUDE_PLUGIN_ROOT}/shared/analysis/proposal-review-runner.sh"
```

- 사용자가 결정 근거 기록을 원하면 `--out <파일경로>`를 붙인다 (proposal + verdict JSON 아티팩트).
- 리뷰가 길어질 수 있으니 timeout을 5분 이상으로 호출한다.
- repo에 `.claude/proposal-review.profile`이 없으면 runner가 degraded로 실행되고 출력 JSON의
  `context` 필드에 그 사실이 남는다. **사용자에게 degraded 사실을 반드시 전달한다.**

### 3. 결과 해석 및 보고

runner의 stdout JSON을 해석해 사용자에게 보여준다:

| verdict | 의미 | 행동 |
|---|---|---|
| `approve` | 방향 맞음, 적용 가능 | recommended_changes 소개 후 사용자 확인 대기 |
| `revise` | 방향 맞음, 보완 필요 | **적용하지 않는다.** critical_issues/recommended_changes 기반으로 제안을 다듬어 사용자와 논의 |
| `block` | 방향 자체가 틀림 | **적용하지 않는다.** 근거(summary)를 보여주고 방향 재검토를 사용자와 논의 |

- `confidence: low` + `missing_context`가 있으면: 그 정보를 보강해 재호출할지 사용자에게 묻는다.
- verdict는 **자문(advisory)이다** — 최종 결정은 항상 사람이 한다. block이어도 사용자가 근거를
  보고 진행을 선택할 수 있다.
- 재호출 반복은 사용자 판단으로만 한다 (자동 수렴 loop 금지 — scope 결정 §5).

## 실패 처리

runner가 exit 2/3으로 실패하면 stderr 내용을 사용자에게 그대로 보여준다. 재시도는 사용자 판단.
조용히 넘어가지 않는다.
