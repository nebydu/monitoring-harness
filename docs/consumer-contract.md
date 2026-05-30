# consumer 계약: profile 주입 방식 후보 (H0, 후보 설계)

> 이 문서는 공통 골격(plugin/shared)을 쓰면서 **도메인 delta를 어떻게 주입할지**의 후보를 정리한다.
> H0에서는 계약의 **방향**만 정하고, 실제 주입 메커니즘은 H2에서 prototype으로 검증한다.

## 책임 경계

| 주체 | 책임 |
|---|---|
| **plugin/shared (공통부)** | "어떻게 실행하는가" — codex-gate 골격, state/escalation 로직, JSON 파싱, 공통 스키마, agent 골격 |
| **consumer repo (delta)** | "무엇이 위반인가" — 트리거 경로, 프롬프트, critical 기준, phase 불변식, 식별자, build/test 명령 |

핵심 원칙: **plugin은 도메인 결정을 하지 않는다.** 공통 골격은 도메인 값을 *주입받아* 동작한다.

## 주입점 (consumer가 제공)

공통 codex-gate 골격(C1)이 동작하려면 consumer가 다음을 profile로 제공해야 한다.

| 주입점 | 의미 | 예시 (repo별) |
|---|---|---|
| `trigger_paths` | Codex 리뷰를 발동시키는 변경 경로 | hub `src/main/*` / sa `cmd/*`,`*.go` / meta `adr/*.md` |
| `skip_paths` | 발동에서 제외할 경로 | `.claude/*`, `docs/*`, `analysis/*` 등 |
| `codex_prompt` | Codex에 줄 리뷰 지시문 | Java review / Go+Kafka 불변식 / spec 정합성 |
| `target_paths` | 리뷰 입력으로 모을 대상 경로 | 비즈니스 코드 / spec 문서 |
| `build_test_run` | 빌드·테스트·실행 명령 | Maven 계열 / Go 계열 / (없음) |

## profile 주입 방식 후보

H2에서 다음 중 하나(또는 조합)를 prototype으로 검증한다. **H0에서는 결정하지 않는다.**

1. **env/설정 파일 주입**: consumer `.claude/`에 작은 profile 파일(예: `codex-gate.profile`)을 두고
   공통 골격이 source/parse.
   - 장점: 골격과 delta 물리 분리 명확. 단점: 파일 포맷·로딩 규약 필요.
2. **plugin 설정 + 변수 오버라이드**: plugin manifest/settings에서 변수 노출, consumer가 값만 채움.
   - 장점: Claude Code plugin 표준에 가까움. 단점: 표현 한계(복잡한 프롬프트/리스트).
3. **wrapper 스크립트**: consumer가 얇은 wrapper에서 변수 정의 후 공통 골격 호출.
   - 장점: 가장 단순. 단점: consumer에 보일러플레이트 잔존.

## 불변 규칙 (어떤 주입 방식이든 유지)

- 공통부는 **trigger 여부·critical 기준·phase 불변식**을 하드코딩하지 않는다(주입만 받는다).
- consumer는 도메인 값만 제공하고, **실행 로직을 복제하지 않는다**.
- 적용은 항상 **git 원복 가능**해야 한다(consumer `.claude/` 단위 rollback).
- consumer 간 교차 쓰기 금지 등 기존 안전 규칙은 그대로 유지된다.
