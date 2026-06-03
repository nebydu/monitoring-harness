# 설치 · 적용 · 업데이트 가이드 (H5 packaging)

monitoring-harness 플러그인의 설치/활성화/구성/업데이트(sync)/버전 정책/rollback을 정리한다.

> **적용 범위**: 이 플러그인은 **런타임(코드 실행) 하네스 전용**이다.
> **현재 상태(롤아웃 완료)**: **script-agent**(`f1092e3`)·**hub**(`cb347a9`)는 이 플러그인으로 전환 완료.
> **monitoring-meta는 범주 외**라 적용하지 않는다 — 코드 미실행·spec 판정 도메인이고 그 gate는 공통
> 골격의 상위집합이라, 드리프트 예외가 아니라 애초에 대상이 아니다(H4,
> [`h4-meta-readiness.md`](h4-meta-readiness.md)). 아래 절차는 sa/hub가 따른 적용 표준이며, 신규 consumer가
> **런타임 하네스라면** 동일하게 쓴다.

## 0. 구성 개요 (wiring 표준)

이 플러그인이 채택한 wiring 표준은 **plugin 모델 + consumer profile 주입**이다
(후보 비교: [`consumer-contract.md`](consumer-contract.md)).

| 자원 | 소유 | 위치 |
|---|---|---|
| 공통 골격 `codex-gate-core.sh` | **plugin** | `shared/hooks/codex-gate-core.sh` |
| 공통 스키마 `codex-schema.json` | **plugin** | `shared/schemas/codex-schema.json` (H1 공통 1부) |
| plugin 진입점 / Stop hook 배선 | **plugin** | `hooks/codex-gate-entry.sh`, `hooks/hooks.json` |
| 도메인 delta(트리거/스킵/프롬프트/임계) | **consumer** | consumer repo의 profile 파일 (예: `.claude/codex-gate.profile`) |
| 보존 상태(escalation 카운터·log) | runtime | `${CLAUDE_PLUGIN_DATA}` (업데이트를 넘어 유지, `harness@monitoring` 기준 data key는 `monitoring-harness`) |

핵심: **plugin은 도메인 결정을 하지 않는다.** consumer는 profile(델타)만 제공하고 실행 로직은
복제하지 않는다.

## 1. 마켓플레이스 추가 · 설치

이 repo는 단일 플러그인 마켓플레이스다(`.claude-plugin/marketplace.json`). **마켓플레이스 이름은
`monitoring`, 플러그인 이름은 `harness`** 이므로 plugin id는 **`harness@monitoring`** 이다(= `plugin@marketplace`).

```shell
# 마켓플레이스 등록 — repo 경로로 add 하면 manifest의 name(=monitoring)으로 등록된다
/plugin marketplace add nebydu/monitoring-harness
#   또는 로컬:  /plugin marketplace add ../monitoring-harness

# 플러그인 설치 (project 스코프로 넣으면 repo 협업자 전체에 적용됨)
/plugin install harness@monitoring --scope project
```

- repo/디렉터리 이름은 여전히 `monitoring-harness`지만, **마켓플레이스 등록명은 `monitoring`**(manifest의
  `name`)이다. 설치/업데이트 명령은 등록명·plugin id(`harness@monitoring`)를 쓴다.
- `--scope project`는 consumer `.claude/settings.json`의 `enabledPlugins`에 `harness@monitoring`으로
  기록되어, repo를 clone한 사람 모두에게 적용된다. 개인 시험용은 스코프 생략(user 스코프).

## 2. consumer 구성 (profile 한 파일 — convention)

consumer는 **델타 profile 한 파일**만 둔다. 골격/스키마/배선은 plugin에서 온다. **별도 plugin config는
필요 없다** — 플러그인은 profile을 **convention 경로**에서 자동으로 찾는다:

```
${CLAUDE_PROJECT_DIR}/.claude/codex-gate.profile
```

- profile 작성 — 템플릿은 [`../shared/hooks/profiles/script-agent.profile.example`](../shared/hooks/profiles/script-agent.profile.example).
  consumer repo의 `.claude/codex-gate.profile`로 복사 후 도메인 값(트리거/스킵/프롬프트)을 채워
  **repo에 커밋**한다(협업자 공유).
- per-user 설정·절대경로가 필요 없으므로, project scope로 설치해도 협업자 환경에서 그대로 동작한다.
- 비표준 위치를 써야 하면 `CODEX_GATE_PROFILE` 환경변수로만 덮어쓴다(테스트/예외용, 공유 비권장).

> profile에는 도메인 프롬프트가 들어가므로 **consumer repo에 남는다**. plugin에 도메인 프롬프트를
> 넣지 않는다(금지 원칙).

## 3. 업데이트 (sync) — 자동 in-place 아님

플러그인은 설치 시 로컬 cache(`~/.claude/plugins/cache`)로 **복사**된다. harness의 hook을 고쳐
push해도 그 자체로는 consumer에 반영되지 않는다.

```shell
/plugin marketplace update monitoring            # 마켓플레이스 카탈로그 갱신
/plugin update harness@monitoring                # 플러그인 새 버전 받기 (또는 auto-update)
/reload-plugins                                 # 세션 중이면 새 hook으로 전환 (안 하면 구 버전 경로 유지)
```

- 세션 중 업데이트는 `/reload-plugins` 전까지 이전 버전 hook 경로를 계속 쓴다.
- 경로는 `${CLAUDE_PLUGIN_ROOT}` 기준이라, 업데이트 시 새 cache 버전으로 자동 해석된다.

## 4. 버전 정책

version은 "업데이트 여부"를 정하는 cache key다(해석 순서: plugin.json `version` → marketplace entry
`version` → git commit SHA → unknown).

- **현행: commit-SHA 방식.** `plugin.json`/marketplace에 `version`을 **두지 않는다**. → harness에 커밋이
  올라갈 때마다 새 버전으로 취급되어 consumer가 `/plugin update`로 즉시 최신 골격을 받는다. 롤아웃이
  끝난 지금도(sa·hub 전환 완료) 내부 도구로서 이 방식을 유지한다 — 골격 수정의 무마찰 전파가 이점.
- **선택: explicit semver 전환(미결 결정).** 정식 릴리스/외부 배포로 가면 `plugin.json`에 `version`을
  고정하고, 전파가 필요할 때마다 **반드시 bump**한다(bump 없는 커밋은 전파되지 않음 — 대표적 함정).
  semver 규약(MAJOR/MINOR/PATCH) + `CHANGELOG.md` 권장. 전환 시점·필요성은 운영자 판단.

> 참고: H0~H1 manifest의 `version: 0.1.0`은 H5에서 제거했다(commit-SHA 채택). semver 전환 시 다시 명시.
> 현재 sa·hub 설치는 각자 설치 시점의 commit-SHA에 pin되어 있어, 골격 변경은 각 repo에서
> `/plugin update`로 받는다.

## 5. rollback

- **플러그인 미적용으로 복귀**: consumer에서 `/plugin uninstall harness@monitoring` 또는
  `enabledPlugins`에서 비활성화 → consumer는 기존 `.claude/` 하네스로 회귀(기존 파일은 그대로 두므로
  즉시 source of execution으로 복귀).
- **packaging 자체 rollback**: harness의 `hooks/`·marketplace.json·active manifest를 제거하면
  H0 bootstrap 형태(비활성)로 되돌아간다. consumer 무영향.
- cache는 업데이트/제거 시 구 버전 디렉터리를 7일 보존(동시 세션 보호) 후 자동 정리.

## 6. 검증 현황

- **수행**: `plugin.json`·`marketplace.json`·`hooks/hooks.json` JSON parse, `codex-gate-entry.sh`
  `bash -n`, `claude plugin validate --strict`.
- **수행(H2-B)**: 샌드박스 런타임 동등성(원본 gate vs plugin 경로, pass/fail/parse_error/skip 일치) +
  convention profile 해석(인자/무인자/부재) — [`../shared/hooks/h2b-validation.md`](../shared/hooks/h2b-validation.md).
  project scope 설치도 수행(enabledPlugins 기록 확인).
- **적용·라이브 검증(완료)**: script-agent·hub 모두 cutover 완료(native Stop hook 비활성 포함)했고,
  두 repo 모두 라이브 Stop 동작 테스트 완료. Windows Git Bash shim 경유 발화·`codex exec` 실연동이
  실환경에서 확인됨.

참고: 플러그인 일반 동작은 [Claude Code 플러그인 문서](https://code.claude.com/docs/en/plugins),
sync/버전 상세는 [plugins-reference](https://code.claude.com/docs/en/plugins-reference).
