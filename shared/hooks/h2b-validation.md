# H2-B 시범 적용 검증 기록 (script-agent)

H5 wiring 표준(plugin 모델 + consumer profile)으로 script-agent에 codex-gate 공통 골격을 적용했을 때
**기존 gate와 런타임 동작이 동일**함을 검증한다.

## 적용 구성

- consumer delta: `script-agent/.claude/codex-gate.profile` (현행 gate 동작 재현, 골격 미복제).
- plugin 자원: `hooks/codex-gate-entry.sh` → consumer profile + `shared/hooks/codex-gate-core.sh`,
  스키마 = plugin 공통 1부, 상태 = `${CLAUDE_PLUGIN_DATA}`.
- plugin manifest: `userConfig.profile`(type file) 선언 → `--config profile=<경로>` 비대화식 주입.

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
# script-agent repo에서
claude plugin marketplace add /c/workspace/monitoring/monitoring-harness
claude plugin install monitoring-harness@monitoring-harness --scope project \
  --config profile=/c/workspace/monitoring/script-agent/.claude/codex-gate.profile
# 재시작 후: 중복 게이트 방지를 위해 script-agent .claude/settings.json의 기존 Stop hook(codex-gate.sh) 비활성
# 검증: claude plugin list  /  대표 변경에 대해 Stop 동작이 위 표와 동일한지 확인
```

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

### project scope에서 드러난 packaging gotcha (H3 전 해결 필요)

1. **enabledPlugins(project, 공유) ↔ profile config(user, per-user) 분리**: 협업자가 script-agent를
   clone하면 플러그인은 enabled지만 profile config는 없어, 그들 세션에서 hook이 profile 미발견으로
   exit 2(Stop 차단)된다. project 공유에는 profile 주입을 **project 차원**으로 둘 방법이 필요.
2. **절대경로**: profile 경로가 머신 종속(`C:/...`). 공유하려면 상대/프로젝트 변수 기반 경로가 필요.
3. **중복 게이트**: 재시작 후 native Stop hook + plugin Stop hook이 동시에 뜬다(이중 Codex 호출).
   plugin 동작을 재시작 후 확인한 뒤 native Stop hook을 비활성해야 한다.

> 따라서 script-agent `.claude/settings.json` 변경은 **아직 커밋하지 말 것**(위 1~3 미해결 상태로
> 공유되면 협업자 Stop이 깨진다). 단일 머신·단일 사용자 trial 검증 용도로만 둔다.

## rollback

- 활성화 전: `script-agent/.claude/codex-gate.profile` 삭제(미추적). 무영향.
- 활성화 후: `claude plugin uninstall monitoring-harness` + settings.json git 원복 → 기존 gate로 복귀.
