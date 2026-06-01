# shared/hooks

codex-gate Stop hook의 **공통 골격**(C1)이 놓이는 디렉터리다.

## 현재 상태 (H2-A 완료, H2-B 게이트 대기)

- `codex-gate-core.sh` — 공통 골격(prototype). 세 repo 동일 실행 로직만 추출, 도메인 delta는 주입점으로 분리.
- `profiles/script-agent.profile.example` — script-agent delta 주입값 예시(현행 동작 재현).
- `codex-gate.wrapper.example.sh` — consumer 얇은 wrapper 예시(profile 로드 + core source).
- `equivalence.md` — script-agent 현행 gate와의 동등성 매핑/검증 기록.

> **consumer 미적용**: 위 파일은 모두 harness repo 내부 예시다. script-agent `.claude/`는 아직
> 수정하지 않았다(H2-B 시범 적용은 사람 확인 게이트 대상).

## 주입점 (도메인 delta — core가 하드코딩하지 않음)

| 주입점 | 필수 | 의미 |
|---|---|---|
| `CODEX_GATE_TRIGGER_GLOBS` (배열) | ✔ | Codex 검증 발동 경로 glob |
| `CODEX_GATE_SKIP_GLOBS` (배열) | | 발동 제외 경로(트리거보다 우선) |
| `CODEX_GATE_PROMPT` (문자열) | ✔ | Codex 리뷰 지시문(도메인 전체) |
| `CODEX_GATE_SKIP_MSG` (문자열) | | 코드 변경 없음 안내 메시지 |
| `CODEX_GATE_SCHEMA` (경로) | | output-schema. 기본 `$CLAUDE_DIR/codex-schema.json` |
| `CODEX_GATE_DATA_DIR` (경로) | | state/log 보존 위치. plugin 모델에선 `${CLAUDE_PLUGIN_DATA}` 권장 |
| `CODEX_GATE_FAIL_LIMIT` / `CODEX_GATE_PARSE_FAIL_LIMIT` | | escalation 임계(기본 3 / 2) |

공통 골격은 baseline 트리거, stop-loop·pipefail 가드, 리뷰 입력 조립, read-only `codex exec`,
python JSON 파싱, verdict 분기, escalation을 담당한다(C1). 트리거 경로·프롬프트 등은 **주입만** 받는다.

> Windows에서는 Git Bash shim(`git-bash.cmd`)으로 WSL bash 충돌을 회피한다. 저작 주의사항은
> [`../../skills/codex-gate-authoring/SKILL.md`](../../skills/codex-gate-authoring/SKILL.md) 참고.

## 정적 검증 (H2-A에서 수행)

- `bash -n codex-gate-core.sh` / `codex-gate.wrapper.example.sh` 구문 통과.
- 주입점 미주입 시 게이트 임의 통과 없이 설정 오류(exit 2)로 실패함을 확인.
- `match_any` 트리거/스킵 판정이 script-agent 원본 case-list와 동일 결과임을 대표 경로로 확인.

## 다음 단계 (H2-B)

script-agent에 core+profile wiring으로 시범 적용 후 런타임 동등성 확인. wiring 방식(vendor /
relative-path source / plugin user_config)과 settings.json 영향은 **사람 확인 게이트**에서 확정한다.
→ [`equivalence.md`](equivalence.md), [`../../docs/consumer-contract.md`](../../docs/consumer-contract.md),
[`../../docs/milestones.md`](../../docs/milestones.md)
