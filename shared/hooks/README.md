# shared/hooks

codex-gate Stop hook과 write-guard PreToolUse hook의 **공통 골격**(C1)이 놓이는 디렉터리다.

## 현재 상태 (H2-B 완료 — script-agent 전환됨)

- `codex-gate-core.sh` — 공통 골격. 세 repo 동일 실행 로직만 추출, 도메인 delta는 주입점으로 분리.
- `profiles/script-agent.profile.example` — script-agent delta 주입값 예시(현행 동작 재현).
- `codex-gate.wrapper.example.sh` — vendor/relative wiring용 얇은 wrapper 예시(plugin 모델에선 불요).
- `equivalence.md` — 정적 동등성 매핑. `h2b-validation.md` — 런타임 동등성·cutover 기록.

> **script-agent 전환 완료**: script-agent는 plugin 모델로 cutover됨(`f1092e3` — native
> `.claude/hooks/codex-gate.sh` 삭제, convention profile 커밋, plugin이 Stop 게이트). hub/meta는 미적용
> (H3/H4 판단 대상). 위 골격 파일은 plugin이 `${CLAUDE_PLUGIN_ROOT}`로 참조한다.

## 주입점 (도메인 delta — core가 하드코딩하지 않음)

| 주입점 | 필수 | 의미 |
|---|---|---|
| `CODEX_GATE_TRIGGER_GLOBS` (배열) | ✔ | Codex 검증 발동 경로 glob |
| `CODEX_GATE_SKIP_GLOBS` (배열) | | 발동 제외 경로(트리거보다 우선) |
| `CODEX_GATE_PROMPT` (문자열) | ✔ | Codex 리뷰 지시문(도메인 전체) |
| `CODEX_GATE_SKIP_MSG` (문자열) | | 코드 변경 없음 안내 메시지 |
| `CODEX_GATE_SCHEMA` (경로) | | output-schema. 기본 `$CLAUDE_DIR/codex-schema.json` |
| `CODEX_GATE_DATA_DIR` (경로) | | state/log 보존 위치. plugin 모델에선 `${CLAUDE_PLUGIN_DATA}` 권장. 주입 시 `<data>/<repo명>-<경로 hash8>/`로 repo별 자동 분리(아래 참고) |
| `CODEX_GATE_FAIL_LIMIT` / `CODEX_GATE_PARSE_FAIL_LIMIT` | | escalation 임계(기본 3 / 2, 도달 시 escalate) |
| `CODEX_GATE_BASELINE_REF` (ref) | | 부트스트랩 신뢰 기준 ref. 기본 `origin/main` |

공통 골격은 검증 윈도우 BASE 결정, 트리거 가드, stop-loop·pipefail 가드, 리뷰 입력 조립, read-only
`codex exec`, python JSON 파싱, verdict 분기, escalation을 담당한다(C1). 트리거 경로·프롬프트 등은
**주입만** 받는다.

## 검증 윈도우 (2026-06-11 — commit-window 사각지대 보완)

종전 BASE=HEAD는 작업 트리 diff만 봐서 **같은 턴에 커밋하면 게이트가 우회**됐다. 이제 상태 파일의
`verified_commit`(vc) 기준으로 **커밋분 + 작업 트리 + 미추적**을 모두 윈도우에 포함한다
(meta `.claude/hooks/codex-gate.sh` reference 이식 — 설계·12라운드 리뷰 기록은
`monitoring-meta/handoff/codex-gate-commit-window/codex-gate-commit-window-000-record.md`).

- 통과 가능한 BASE 5종: `vc` / `merge-base`(rebase·amend) / `bootstrap-origin` /
  `bootstrap-origin-mb`(diverged) / `empty-tree`(HEAD 없음). 그 외 `disconnected`·`no-baseline`은
  **fail-closed(exit 2)** 차단 — 차단 이벤트는 `codex-gate-block.log`에 분리 기록.
- vc 전진: 윈도우가 BASE..HEAD 전 구간을 커버하고 검증이 완료(트리거 0 skip / pass)된 경우만.
  escalated(강제 통과)·차단·fail은 전진하지 않는다.
- 상태 파일은 JSON(`cache_status` = gate_key 캐시 축 / `last_result` = 마지막 hook 결과 축 —
  자동화는 `last_result`만 소비). 구버전 평문 state(`FAIL PARSE`)는 카운터를 승계해 자동 전환된다.

## data dir 분리와 stop 루프 가드 (2026-06-11 proposal-review 보완)

- **레이아웃**: `CODEX_GATE_DATA_DIR` 주입 시 state/log는 `<data>/<repo명>-<repo 절대경로 sha256 앞 8자>/`에
  놓인다. basename만 쓰면 같은 이름의 다른 repo가 state를 공유해 vc 단절 오차단이 재발하기 때문이다.
  디렉터리 안의 `.repo-path` 메타데이터로 소유권을 기록하고, 불일치하면 fail-closed(exit 2)로 차단한다.
- **마이그레이션 없음**: 구 레이아웃(flat 또는 `<repo명>/`)의 state는 소유권을 검증할 수 없어 승계하지
  않는다(fresh bootstrap — vc 공백은 baseline ref 부트스트랩이 안전하게 재검증). 구 디렉터리/flat 파일은
  고아가 되므로 수동 정리 대상이다. 삭제 전 dry-run 목록 확인:
  `ls ~/.claude/plugins/data/harness-monitoring/` 에서 `<repo명>-<hash8>` 형식이 **아닌** 항목만 삭제한다.
- **stop 루프 가드 순서**: core·entry 모두 `stop_hook_active` 판정이 **모든 exit 2 경로보다 앞**이다.
  주입점 오설정·명시 profile 부재 등 구성 오류는 첫 stop(active=false)에서 exit 2로 1회 노출되고,
  재발화(active=true)에서는 종료를 허용해 무한 stop 루프를 막는다. entry는 stdin을 가드에서 한 번 읽고
  core에 herestring으로 재공급한다(core의 `cat` 계약 유지).
- **테스트**: `bash tests/codex-gate-tests.sh` — 격리 스크래치 repo + codex 스텁으로 14개 시나리오
  (커밋 윈도우 사각지대, 루프 가드, basename 충돌, 소유권 충돌, 구 레이아웃 미승계, 단절/기준 없음 차단 등)를
  검증한다. core/entry 수정 시 반드시 실행한다.

> **소비자 opt-in 모델**: plugin Stop hook은 모든 repo에 글로벌로 등록되지만, convention 경로
> `<repo>/.claude/codex-gate.profile`이 **없는 repo는 자동으로 skip된다**(entry가 source 전에 `exit 0`).
> 즉 profile을 두지 않은 repo의 세션 종료를 막지 않는다. 게이팅을 받으려면 그 repo에 profile을 두면 된다
> (opt-in). 단 `CODEX_GATE_PROFILE`을 명시 지정했는데 그 파일이 없으면 오설정으로 보고 `exit 2`로 차단한다.

> Windows에서는 Git Bash shim(`git-bash.cmd`)으로 WSL bash 충돌을 회피한다. 저작 주의사항은
> [`../../skills/codex-gate-authoring/SKILL.md`](../../skills/codex-gate-authoring/SKILL.md) 참고.

## 정적 검증 (H2-A에서 수행)

- `bash -n codex-gate-core.sh` / `codex-gate.wrapper.example.sh` 구문 통과.
- 주입점 미주입 시 게이트 임의 통과 없이 설정 오류(exit 2)로 실패함을 확인.
- `match_any` 트리거/스킵 판정이 script-agent 원본 case-list와 동일 결과임을 대표 경로로 확인.

## H2-B 현황

script-agent에 plugin 모델로 적용·검증 완료(런타임 동등성, project scope 설치). wiring 표준은 **plugin
모델 + convention 경로** profile로 확정(per-user config·절대경로 제거). 라이브 활성화(재시작) + native
Stop hook 비활성만 사용자 세션에 남았다.
→ [`h2b-validation.md`](h2b-validation.md), [`equivalence.md`](equivalence.md),
[`../../docs/installation.md`](../../docs/installation.md)

## write-guard (PreToolUse 쓰기 가드)

`write-guard-core.sh` — Write/Edit/NotebookEdit를 호출 **전**에 검사해 polyrepo 경계 밖 쓰기를
차단하는 두 번째 축(PreToolUse). 진입점은 `../../hooks/write-guard-entry.sh`, 배선은
`../../hooks/hooks.json`의 `PreToolUse`. codex-gate와 동일한 패턴(plugin 골격 + `git-bash.cmd`
shim + convention profile)이다.

- **차단 메커니즘 = `exit 2`** (정본). PreToolUse `exit 2` = 툴 차단 + stderr 사유를 모델에 환류.
  JSON `permissionDecision:deny`는 **Edit/Write에서 무시되는 알려진 버그**가 있어 쓰지 않는다.
- **차단 규칙**(정규화된 경로 기준, 우선순위): ① 자기 `REPO_ROOT/.claude/` = 허용(자동화 설정은
  사람이 관리) → ② 자기 `docs/` = 차단 → ③ `PARENT` 하위이며 자기 repo 밖 = 차단(형제 repo 전체 +
  ground truth meta + 형제 `.claude` 포함) → ④ profile 추가 차단 경로 → ⑤ 그 외 허용. 즉 자기
  repo는 `docs/` 외 전부 허용, profile은 **조이기만** 가능(유도 규칙 약화 불가).
- **경로 정규화**는 python `realpath` 기반 일원화(Windows/MSYS의 `..`·symlink·junction·대소문자
  함정 회피). JSON 파싱 실패·`file_path` 부재는 **판단하지 않고 통과**(차단하지 않음).
- **opt-in 모델**: convention 경로 `<repo>/.claude/write-guard.profile`이 **있는 repo만** 가드한다
  (없으면 entry가 `exit 0` — 무관 프로젝트 미영향). profile이 비어 있어도 유도 규칙은 적용되고,
  `WRITE_GUARD_BLOCK_PATHS`(배열)로 추가 차단 루트만 지정한다. 단 `WRITE_GUARD_PROFILE`을 명시
  지정했는데 부재하면 오설정으로 보고 `exit 2`(fail-closed).

| 주입점 | 필수 | 의미 |
|---|---|---|
| `WRITE_GUARD_BLOCK_PATHS` (배열) | | 추가 차단 루트(상대=repo 기준/절대, subtree 차단). add-only |

**테스트**: `bash tests/write-guard-tests.sh` — 격리 워크스페이스(부모 밑 own + 형제 repo)로 15개
시나리오(자기 docs/형제/ground truth 차단, 자기 코드/`.claude` 허용, 형제 `.claude` 차단, opt-in,
realpath 정규화, 입력 방어, fail-closed 등)를 검증한다. core/entry 수정 시 반드시 실행한다.
