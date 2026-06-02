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

## cutover 완료 (script-agent `f1092e3`)

script-agent는 plugin 전환 cutover를 **완료·커밋**했다. 수행된 절차:

```shell
# 1) marketplace 등록 + project scope 설치 (enabledPlugins 기록)
claude plugin marketplace add /c/workspace/monitoring/monitoring-harness
claude plugin install monitoring-harness@monitoring-harness --scope project   # --config 불필요(convention)
# 2) convention 적용 골격 반영
claude plugin update monitoring-harness
# 3) 재시작 → 동작 확인 → native Stop hook 비활성
#    → settings.json hooks.Stop 제거(PreToolUse·enabledPlugins 유지) + native codex-gate.sh 삭제
# 4) script-agent .claude/settings.json + codex-gate.profile 커밋 (f1092e3)
```

**결과**: script-agent Stop 게이트의 source of execution = **plugin codex-gate(단일)**. native
`.claude/hooks/codex-gate.sh`는 삭제됨.

> profile은 convention 경로(`${CLAUDE_PROJECT_DIR}/.claude/codex-gate.profile`)에서 자동 발견되므로
> `--config`/userConfig가 필요 없다. staging 시 user settings에 저장됐던 `pluginConfigs.profile`(절대경로)은
> 더 이상 읽히지 않는 inert cruft이므로 지워도 된다.

### staging install 실행 결과 (project scope, 수행함)

`claude plugin marketplace add` + `claude plugin install --scope project --config profile=...` 실행됨.

| 항목 | 저장 위치 | 비고 |
|---|---|---|
| marketplace 등록 | user settings `extraKnownMarketplaces` | `directory` 소스 = harness repo |
| `enabledPlugins` | **script-agent `.claude/settings.json` (추적됨)** | 설치 시 JSON 재직렬화(cosmetic) 동반 |
| `pluginConfigs.profile` | **user settings (per-user)** | 절대경로 `C:/.../script-agent/.claude/codex-gate.profile` |
| Version | `89cc7fee7007` (commit-SHA) | 버전 정책과 일치 |

> 위 표는 staging install **시점** 기록이다. 이후 gotcha 해결로 profile 주입이 convention으로 바뀌어
> `pluginConfigs.profile`(절대경로)은 더 이상 읽히지 않는 inert cruft가 됐고, version은 이후 커밋 SHA로
> 갱신된다. **cutover 완료 상태는 아래 "cutover 완료" 절 참고.**

### project scope packaging gotcha — 해결됨 (1·2 구조적 해결, 3은 cutover 절차)

1. **enabledPlugins(공유) ↔ profile config(per-user) 분리 → 해결**: profile 주입을 per-user config가
   아니라 **convention 경로**(`${CLAUDE_PROJECT_DIR}/.claude/codex-gate.profile`)로 바꿨다. `hooks.json`이
   이 경로를 기본 인자로 넘기고, plugin manifest의 `userConfig`는 제거했다. 협업자는 별도 설정 없이
   동작한다(검증: 아래 무인자 convention 케이스 exit 0).
2. **절대경로 → 해결**: `${CLAUDE_PROJECT_DIR}` 기반이라 머신 독립. 절대경로가 사라졌다.
3. **중복 게이트 → 해결(cutover 완료)**: script-agent `f1092e3`에서 native `.claude/hooks/codex-gate.sh`
   삭제 + settings.json Stop hook 제거(`PreToolUse`만 유지)로 단일(plugin) 게이트가 됐다. settings.json
   변경과 plugin 활성화가 같은 재시작에 함께 적용되어 게이트 공백은 없다.

#### convention 해석 재검증 (수행함)

| 케이스 | 결과 |
|---|---|
| A) `hooks.json` convention 인자 전달 | `exit 0 / pass` ✅ |
| B) **무인자 순수 convention**(협업자: per-user config·abspath 없음) | `exit 0 / pass` ✅ |
| C) profile 부재 | `exit 2` + 명확한 구성오류 메시지 ✅ |

> profile 주입이 convention으로 바뀌어, project scope 커밋이 **공유 안전**해졌다(협업자 Stop 안 깨짐).
> (3) native hook 비활성과 settings.json+profile 커밋은 cutover에서 완료됐다(`f1092e3`).

## rollback (cutover 완료 기준)

cutover가 `f1092e3`로 커밋됐으므로 복귀는 git revert + plugin 비활성으로 한다:

- `claude plugin uninstall monitoring-harness` (또는 `enabledPlugins`에서 비활성)
- `git -C ../script-agent revert f1092e3` (native `codex-gate.sh` 복원 + settings.json Stop hook 복귀)
- 필요 시 user settings의 inert `pluginConfigs.profile`·`extraKnownMarketplaces` 정리.
