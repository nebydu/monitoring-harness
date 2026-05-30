# shared/schemas

향후 공통 `codex-schema.json` (Codex gate 출력 계약)이 놓일 **위치 예약** 디렉터리다.

## 현재 상태 (H0)

- **비어 있다.** H0에서는 스키마를 **복사하지 않고 위치만 예약**한다.

## 근거

세 consumer repo(`hub`/`script-agent`/`monitoring-meta`)의 `.claude/codex-schema.json`은
**byte-for-byte 동일**하다.

스키마 형태(요약):

```json
{
  "type": "object",
  "properties": {
    "verdict":         { "enum": ["pass", "fail"] },
    "critical_issues": { "type": "array", "items": { "type": "string" } },
    "spec_violations": { "type": "array", "items": { "type": "string" } },
    "summary":         { "type": "string" }
  },
  "required": ["verdict", "critical_issues", "spec_violations", "summary"],
  "additionalProperties": false
}
```

→ **공통 1부 후보**(설계: [`../../docs/design.md`](../../docs/design.md) C3).

## 다음 단계

H1에서 공통 `codex-schema.json`을 이 디렉터리에 두고 세 repo 사본과 동등성을 검증한다
(consumer가 참조하도록 바꾸는 것은 H1 범위 밖). → [`../../docs/milestones.md`](../../docs/milestones.md)
