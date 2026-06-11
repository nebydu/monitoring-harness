# shared/hooks

codex-gate Stop hook의 **공통 골격**(C1)이 놓이는 디렉터리다.

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
| `CODEX_GATE_DATA_DIR` (경로) | | state/log 보존 위치. plugin 모델에선 `${CLAUDE_PLUGIN_DATA}` 권장 |
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
