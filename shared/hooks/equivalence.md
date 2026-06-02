# codex-gate 공통 골격 동등성 기록 (H2-A)

`shared/hooks/codex-gate-core.sh`(공통 골격) + `profiles/script-agent.profile.example`(delta)가
script-agent의 현행 `.claude/hooks/codex-gate.sh`와 **동작상 동일**함을 매핑한다.

> H2-A(harness 내부 산출물) 기준의 정적 동등성 매핑이다. 실제 script-agent 적용 후의 런타임 동등성은
> H2-B에서 수행 완료했다(아래 "런타임 동등성" 절 + [`h2b-validation.md`](h2b-validation.md)).

## 추출 원칙

세 repo codex-gate.sh에서 **동일한 실행 로직만** core로 올리고, repo별로 다른 값만 주입점으로 뺐다.
원본 동작을 바꾸지 않는 것이 H2-A의 유일한 목표다(리팩터 아님, 기능 변경 아님).

## 라인 단위 매핑 (script-agent 원본 → core/profile)

| script-agent 원본(codex-gate.sh) | H2 위치 | 비고 |
|---|---|---|
| 경로 정의 `:8-17` | core 경로 블록 | `DATA_DIR` 주입점 추가(기본 `$CLAUDE_DIR` → 동일) |
| `EMPTY_TREE` `:20` | core | 그대로 |
| `log_line`/`emit_system_message`/`escalate` `:23-34` | core | 문자열·인코딩 처리 그대로 |
| state 함수 `:35-44` | core | 그대로 |
| stop-loop 가드 `:46-56` | core | 그대로 |
| 트리거 case-list `:73-82` | **profile** `CODEX_GATE_TRIGGER_GLOBS`/`CODEX_GATE_SKIP_GLOBS` | `case` → `match_any` 루프, 패턴 동작 동일 |
| 스킵 메시지 `:93` | **profile** `CODEX_GATE_SKIP_MSG` | 문자열 그대로 |
| 검토 입력 조립 `:97-109` | core | 그대로 |
| Codex 프롬프트 `:112` | **profile** `CODEX_GATE_PROMPT` | 문자열 그대로 |
| codex exec 호출 `:114-120` | core | `--sandbox read-only`, `--output-schema`, `-o` 그대로 |
| python 파싱 `:122-146` | core | 동일 스크립트 |
| 파싱 실패/escalation `:148-166` | core | 임계 `2` → `CODEX_GATE_PARSE_FAIL_LIMIT`(기본 2) |
| verdict 분기 `:168-195` | core | 임계 `3` → `CODEX_GATE_FAIL_LIMIT`(기본 3) |

## 행위 동등성 포인트

- **트리거/스킵 판정**: 원본은 `case "$f" in` 하드코딩 arm. core는 `match_any`가 동일한 `case` 패턴
  매칭(`*`가 `/`도 매칭)을 glob 목록에 대해 수행. 스킵을 트리거보다 먼저 검사하는 우선순위도 동일.
  profile의 glob 목록이 원본 arm과 1:1 대응 → 같은 파일집합이 트리거된다.
- **임계값**: profile이 `3`/`2`를 명시(생략해도 core 기본값이 `3`/`2`라 결과 동일).
- **출력·exit code**: pass=exit0+systemMessage, fail=exit2(+escalate시 exit0), skip=exit0, parse_error=
  exit2(+escalate시 exit0) — 모두 원본과 동일.
- **schema 경로**: 기본 `$CLAUDE_DIR/codex-schema.json`으로 원본과 동일(H1 공통 1부 참조 전환은 별건).

## 정적 검증 (수행함)

- `bash -n codex-gate-core.sh` 구문 검사 통과.
- `match_any` 패턴 매칭을 대표 경로로 단위 확인:
  `cmd/agent/main.go`·`internal/x.go`·`go.mod`·`root.go` → 트리거,
  `.claude/x`·`docs/x.md`·`analysis/x` → 스킵, `README.md` → 무시(트리거 아님).

## 런타임 동등성 (H2-B에서 수행 완료)

H2-B에서 수행한 런타임 동등성·cutover 결과는 [`h2b-validation.md`](h2b-validation.md) 참고:

- 샌드박스에서 원본 gate vs plugin(entry→profile→core) — pass/fail/parse_error/skip 전부 exit·verdict 일치.
- wiring 표준은 **plugin 모델 + convention 경로** profile로 확정(vendor/relative/user_config 후보 중).
- script-agent cutover 완료(`f1092e3`): native gate 삭제, plugin이 Stop 게이트.
- rollback: script-agent `.claude/`는 git으로 즉시 원복.
