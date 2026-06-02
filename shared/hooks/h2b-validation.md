# H2-B 시범 적용 검증 기록 (script-agent)

H5 wiring 표준(plugin 모델 + consumer profile)으로 script-agent에 codex-gate 공통 골격을 적용했을 때
**기존 gate와 런타임 동작이 동일**함을 검증한다.

## 적용 구성

- consumer delta: `script-agent/.claude/codex-gate.profile` (현행 gate 동작 재현, 골격 미복제).
- plugin 자원: `hooks/codex-gate-entry.sh` → consumer profile + `shared/hooks/codex-gate-core.sh`,
  스키마 = plugin 공통 1부, 상태 = `${CLAUDE_PLUGIN_DATA}`.
- profile 주입: **convention 경로**(`${CLAUDE_PROJECT_DIR}/.claude/codex-gate.profile`) 자동 탐색.
  (초기엔 `userConfig.profile` 검토 → gotcha로 제거하고 convention으로 확정. 아래 "gotcha 해결" 참고.)

## 런타임 동등성 테스트 (수행함, 무위험 샌드박스)

script-agent 레이아웃을 모사한 임시 git repo에서, **원본 `codex-gate.sh`** 와
**plugin 경로(entry→profile→core)** 를 동일 시나리오·동일 입력(stub `codex`)으로 실행해 비교했다.
실제 script-agent 작업트리·라이브 hook은 건드리지 않았다.

| 시나리오 | 원본 (exit\|verdict) | plugin (exit\|verdict) | 일치 |
|---|---|---|---|
| 코드 변경 + pass | `0 \| pass` | `0 \| pass` | ✅ |
| 코드 변경 + fail | `2 \| fail` | `2 \| fail` | ✅ |
| 코드 변경 + 파싱실패 | `2 \| parse_error` | `2 \| parse_error` | ✅ |
| docs만 변경 (스킵) | `0 \| skipped` | `0 \| skipped` | ✅ |

trigger/skip 판정, verdict 분기, exit code, 로그 verdict 토큰이 **전 시나리오 일치**.
(정적 검증은 [`equivalence.md`](equivalence.md): `bash -n`, 주입점 가드, `match_any`==원본 case-list.)

## 라이브 cutover (활성화 — 사용자 세션 필요)

플러그인 활성화는 **재시작이 필요**(`plugin update`는 "restart required")하여 본 세션에서 활성·검증이
불가하다. 아래는 즉시 실행 가능한 cutover 절차다.

```shell
# 1) (이미 수행) marketplace 등록 + project scope 설치
claude plugin marketplace add /c/workspace/monitoring/monitoring-harness
claude plugin install monitoring-harness@monitoring-harness --scope project   # --config 불필요(convention)

# 2) 골격 수정분 반영 (convention 적용된 hooks.json/entry/manifest)
claude plugin update monitoring-harness

# 3) 재시작 → 동작 확인(대표 변경에서 Stop이 동등성 표대로) → 정상이면 native Stop hook 비활성
#    script-agent/.claude/settings.json 의 hooks.Stop 블록 제거 (PreToolUse·enabledPlugins 유지)

# 4) 검증: claude plugin list / Stop 동작 / 그 뒤 script-agent settings.json + .claude/codex-gate.profile 커밋
```

> profile은 convention 경로(`${CLAUDE_PROJECT_DIR}/.claude/codex-gate.profile`)에서 자동 발견되므로
> `--config`/userConfig가 필요 없다. 앞서 user settings에 저장된 `pluginConfigs.profile`(절대경로)은
> 더 이상 읽히지 않는 inert cruft이므로 지워도 된다.

### staging install 실행 결과 (project scope, 수행함)

`claude plugin marketplace add` + `claude plugin install --scope project --config profile=...` 실행됨.

| 항목 | 저장 위치 | 비고 |
|---|---|---|
| marketplace 등록 | user settings `extraKnownMarketplaces` | `directory` 소스 = harness repo |
| `enabledPlugins` | **script-agent `.claude/settings.json` (추적됨)** | 설치 시 JSON 재직렬화(cosmetic) 동반 |
| `pluginConfigs.profile` | **user settings (per-user)** | 절대경로 `C:/.../script-agent/.claude/codex-gate.profile` |
| Version | `89cc7fee7007` (commit-SHA) | 버전 정책과 일치 |

**활성화 안 됨(재시작 필요)**: 본 세션에선 hook이 아직 안 뜬다. 기존 `.claude/hooks/codex-gate.sh`가
계속 source of execution.

### project scope packaging gotcha — 해결됨 (1·2 구조적 해결, 3은 cutover 절차)

1. **enabledPlugins(공유) ↔ profile config(per-user) 분리 → 해결**: profile 주입을 per-user config가
   아니라 **convention 경로**(`${CLAUDE_PROJECT_DIR}/.claude/codex-gate.profile`)로 바꿨다. `hooks.json`이
   이 경로를 기본 인자로 넘기고, plugin manifest의 `userConfig`는 제거했다. 협업자는 별도 설정 없이
   동작한다(검증: 아래 무인자 convention 케이스 exit 0).
2. **절대경로 → 해결**: `${CLAUDE_PROJECT_DIR}` 기반이라 머신 독립. 절대경로가 사라졌다.
3. **중복 게이트 → cutover 절차로 해결**: native Stop hook과 plugin Stop hook 동시 발화를 막으려면
   재시작·검증 후 script-agent `.claude/settings.json`의 native Stop hook을 비활성한다(아래 절차).
   재시작 전에 미리 끄면 게이트 공백이 생기므로 **순서가 중요**하다.

#### convention 해석 재검증 (수행함)

| 케이스 | 결과 |
|---|---|
| A) `hooks.json` convention 인자 전달 | `exit 0 / pass` ✅ |
| B) **무인자 순수 convention**(협업자: per-user config·abspath 없음) | `exit 0 / pass` ✅ |
| C) profile 부재 | `exit 2` + 명확한 구성오류 메시지 ✅ |

> profile 주입이 convention으로 바뀌어, project scope 커밋이 **공유 안전**해졌다(협업자 Stop 안 깨짐).
> 단 (3) native hook 비활성은 재시작·검증 후 수행해야 하므로, settings.json 커밋은 그 cutover와 함께 한다.

## rollback

- 활성화 전: `script-agent/.claude/codex-gate.profile` 삭제(미추적). 무영향.
- 활성화 후: `claude plugin uninstall monitoring-harness` + settings.json git 원복 → 기존 gate로 복귀.
