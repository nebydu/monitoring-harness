# codex-schema.json 동등성 검증 노트 (H1)

공통 1부 `shared/schemas/codex-schema.json`을 세 consumer repo의 사본과 비교한 결과를 기록한다.
검증은 **read-only**로 수행했으며, consumer repo는 수정하지 않았다.

## 검증 방법

각 파일에 대해 (1) 원본 sha256, (2) CR 제거 후 정규화 sha256, (3) 크기/CR 개수를 비교했다.

```sh
# 원본 / 정규화 해시
sha256sum <repo>/.claude/codex-schema.json
tr -d '\r' < <repo>/.claude/codex-schema.json | sha256sum
```

## 결과

| 대상 | size(byte) | CR 개수 | EOL | 원본 sha256(앞 12) | 정규화 sha256(앞 12) |
|---|---|---|---|---|---|
| hub | 484 | 22 | **CRLF** | `db5a87afc411` | `ffae44b4b4cd` |
| script-agent | 462 | 0 | LF | `ffae44b4b4cd` | `ffae44b4b4cd` |
| monitoring-meta | 462 | 0 | LF | `ffae44b4b4cd` | `ffae44b4b4cd` |
| **shared (공통 1부)** | 462 | 0 | LF | `ffae44b4b4cd` | `ffae44b4b4cd` |

전체 정규화 sha256: `ffae44b4b4cdb64bd942b31c76dbc97c031e31fa2f4b054286a088137da6041c`

## 판정

- **내용(content)은 세 repo 모두 동일하다.** CR을 제거한 정규화 해시가 전부 일치한다.
- **유일한 차이는 줄바꿈이다.** hub만 CRLF(484B), script-agent·monitoring-meta는 LF(462B).
- H0 설계 문서(C3)가 "byte-for-byte 동일"이라고 한 것은 **EOL 정규화 기준에서만 정확**하다.
  엄밀히는 hub가 CRLF delta를 가진다.

## 공통 1부 정책

- 공통 1부는 **LF**를 기준으로 한다(script-agent·monitoring-meta와 byte-for-byte 일치).
- hub의 CRLF는 줄바꿈 차이일 뿐 스키마 의미 차이가 아니다. consumer 적용 단계(H2~)에서 hub를 공통
  1부로 전환할 때 EOL을 LF로 정규화하면 hub 사본과도 내용상 동등해진다.
- 기준 EOL이 LF임을 보장하기 위해, schema 파일에는 `.gitattributes`로 `*.json text eol=lf`를 둔다.

## H1 범위 확인 (하지 않은 것)

- consumer repo가 이 공통 1부를 **참조하도록 바꾸지 않았다.** 세 repo는 여전히 각자 사본을 사용한다.
- consumer repo 파일을 **수정하지 않았다**(비교는 read-only).
- 다음 단계(H2 codex-gate 골격 prototype, script-agent 시범 적용)는 사람 확인 게이트를 거친다.
