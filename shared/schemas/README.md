# shared/schemas

Codex gate 출력 계약인 공통 `codex-schema.json` **1부**가 놓이는 디렉터리다.

## 현재 상태 (H1 완료)

- `codex-schema.json` — 공통 1부 (정본). **LF**, 462B, sha256 `ffae44b4b4cd…`.
- `equivalence-check.md` — 세 consumer 사본과의 동등성 검증 노트.
- consumer는 아직 이 1부를 **참조하지 않는다**(여전히 각자 사본 사용). 참조 전환은 H2~ 범위.

## 동등성 요약

세 consumer repo(`hub`/`script-agent`/`monitoring-meta`)의 `.claude/codex-schema.json`은
**내용이 동일**하다(CR 제거 정규화 시 sha256 전부 일치). 유일한 차이는 줄바꿈으로, hub만 CRLF(484B),
나머지 둘은 LF(462B)다. 공통 1부는 LF를 정본으로 삼는다. 상세는 [`equivalence-check.md`](equivalence-check.md).

> 루트 `.gitattributes`의 `*.json text eol=lf` 규칙으로 정본 EOL을 LF로 고정한다.

스키마 형태(요약):

```json
{
  "type": "object",
  "properties": {
    "verdict":         { "type": "string", "enum": ["pass", "fail"] },
    "critical_issues": { "type": "array", "items": { "type": "string" } },
    "spec_violations": { "type": "array", "items": { "type": "string" } },
    "summary":         { "type": "string" }
  },
  "required": ["verdict", "critical_issues", "spec_violations", "summary"],
  "additionalProperties": false
}
```

→ 설계 근거: [`../../docs/design.md`](../../docs/design.md) C3.

## 다음 단계

H2에서 codex-gate 공통 골격 prototype을 만들고 script-agent에 시범 적용할 때, 이 공통 1부를 참조하도록
전환할지 검토한다(사람 확인 게이트). → [`../../docs/milestones.md`](../../docs/milestones.md)
