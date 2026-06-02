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

> **결정(H5, H2-B에서 정련)**: **plugin 모델 + convention 경로** 주입을 wiring 표준으로 채택했다.
> consumer는 profile 델타 파일을 **convention 위치**(`${CLAUDE_PROJECT_DIR}/.claude/codex-gate.profile`)에
> 두기만 하면 되고, 골격/스키마/배선은 plugin이 제공한다. 초기엔 4안(`${user_config.*}`)을 검토했으나,
> per-user config 분리·절대경로 문제(H2-B gotcha)로 인해 **userConfig 없이 convention 자동탐색**으로
> 정련했다. 절차는 [`installation.md`](installation.md) §0/§2. 아래 후보 목록은 결정 근거로 보존한다.

H2에서 다음 중 하나(또는 조합)를 prototype으로 검증한다. **H0에서는 결정하지 않는다.**

1. **env/설정 파일 주입**: consumer `.claude/`에 작은 profile 파일(예: `codex-gate.profile`)을 두고
   공통 골격이 source/parse.
   - 장점: 골격과 delta 물리 분리 명확. 단점: 파일 포맷·로딩 규약 필요.
2. **plugin 설정 + 변수 오버라이드**: plugin manifest/settings에서 변수 노출, consumer가 값만 채움.
   - 장점: Claude Code plugin 표준에 가까움. 단점: 표현 한계(복잡한 프롬프트/리스트).
3. **wrapper 스크립트**: consumer가 얇은 wrapper에서 변수 정의 후 공통 골격 호출.
   - 장점: 가장 단순. 단점: consumer에 보일러플레이트 잔존.
4. **plugin `${user_config.*}` 치환 (plugin-native)**: plugin 모델로 갈 때, hook command는
   `${user_config.*}` / `${CLAUDE_PROJECT_DIR}` / `${ENV_VAR}` 변수 치환을 지원한다. 공통 hook 본문은
   plugin 1부로 두고, consumer는 자신의 설정에서 `user_config` 값만 채워 delta를 주입한다.
   - 장점: Claude Code plugin **공식 주입점**. vendoring 없이 1부 hook 유지. 2안의 표준형이다.
   - 단점: 매우 긴 프롬프트/리스트는 변수 한 칸에 담기 부담 → 긴 텍스트는 plugin 내 파일로 두고
     `user_config`로는 "어느 프로파일을 쓸지" 식의 선택자만 넘기는 절충이 필요.

> 경로 변수: plugin 모델에서는 hook이 `${CLAUDE_PROJECT_DIR}/.claude/...`가 아니라
> `${CLAUDE_PLUGIN_ROOT}/...`를 가리킨다. escalation 카운터 등 **버전 업데이트를 넘어 보존돼야 하는
> 상태**는 `${CLAUDE_PLUGIN_DATA}`에 둔다(업데이트 후에도 유지되는 디렉터리).

## 불변 규칙 (어떤 주입 방식이든 유지)

- 공통부는 **trigger 여부·critical 기준·phase 불변식**을 하드코딩하지 않는다(주입만 받는다).
- consumer는 도메인 값만 제공하고, **실행 로직을 복제하지 않는다**.
- 적용은 항상 **git 원복 가능**해야 한다(consumer `.claude/` 단위 rollback).
- consumer 간 교차 쓰기 금지 등 기존 안전 규칙은 그대로 유지된다.

## 공통부 변경의 sync/업데이트 모델

harness 쪽 공통 hook이 바뀌었을 때 이미 적용된 consumer가 어떻게 새 버전을 받는지는 주입 방식에
따라 다르다. **vendoring 계열(1·3안)** 과 **plugin 계열(2·4안)** 의 sync 모델이 근본적으로 다르다.

| | vendoring (1·3안, 상대경로 source) | plugin/marketplace (2·4안) |
|---|---|---|
| 공통 hook 위치 | consumer가 `../monitoring-harness`를 참조하거나 사본 보유 | marketplace 설치 시 **로컬 cache로 복사**(`~/.claude/plugins/cache`) |
| 동기화 방법 | harness `git pull` 시 즉시 반영 | `/plugin update`(또는 auto-update)로만 반영 — **자동 in-place 아님** |
| 버전 통제 | 없음(항상 HEAD) | version이 cache key. bump/SHA로 통제 |
| 적용 시점 | 다음 hook 실행부터 | 다음 세션 또는 세션 중 `/reload-plugins` 이후 |
| 표준성 | 비표준·취약 | 공식 경로, 구버전 7일 보존(동시 세션 보호) |

### plugin 모델의 버전 전략 (현재 채택: commit-SHA)

version 해석 순서: `plugin.json`의 `version` → marketplace entry `version` → git commit SHA → unknown.

- **explicit semver**(`plugin.json`에 `version` 고정): consumer는 **version을 bump해야만** 업데이트를
  받는다. hook만 고쳐 push하고 bump를 빠뜨리면 `/plugin update`가 "이미 최신"으로 처리해 옛 hook이
  유지된다. → **안정 릴리스(H4 이후 정식 채택)** 용.
- **commit-SHA**(`version` 생략): **커밋마다** 새 버전으로 취급돼 매 커밋이 update 대상. → **빠른 반복
  단계(H2~H4)** 에 적합하며, 현재 H2-B~H4 rollout 표준이다.

> 현재 `plugin.json`/marketplace entry에는 `version`을 두지 않는다. H5 packaging에서 commit-SHA 방식을
> rollout 표준으로 채택했기 때문이다. 정식 릴리스로 전환할 때만 explicit semver를 다시 도입하고,
> 변경 전파가 필요할 때마다 version bump 규율을 적용한다(→ [`installation.md`](installation.md) §4).
