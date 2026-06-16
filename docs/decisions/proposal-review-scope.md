# proposal-review scope 결정 — H4 재해석과 plugin 2축 정의

`proposal-review`(결정 전 제안 리뷰 command)를 plugin에 추가하기 위한 **범위 결정** 기록이다.
구현 전에 이 문서를 먼저 두는 이유: 현행 plugin description과 H4 결정문을 문언 그대로 읽으면
이 기능은 "runtime harness 범위 밖"으로 해석될 수 있어, 범위 재해석을 기록하지 않으면
다음 세션/사람이 H4를 근거로 이 기능을 범위 위반으로 판정하게 된다.

- 발단: 전략 초안 `docs/proposal-review-strategy-draft.md` + 검토 (2026-06-07)
- 관련: `h4-meta-readiness.md`(재해석 대상), `codex-gate-graceful-skip.md`(§2 의도 신호 원칙 재적용)
- 마일스톤: **H6** (milestones.md에 등록 예정)

## 결론 요약

1. **H4 재해석**: H4에서 제외한 것은 *monitoring-meta의 Stop hook 기반 runtime codex-gate 통합*이다.
   proposal-review는 runtime gate가 아니라 **사용자가 명시적으로 호출하는 decision-review command**이므로
   H4 A안(meta 자체 gate 유지)과 충돌하지 않는다.
2. **plugin은 2축으로 정의한다**: ① runtime codex-gate(Stop hook, hub/script-agent 전용) +
   ② decision-review command(`/proposal-review`, on-demand). **meta는 ①에서만 범위 밖**이며,
   ②는 convention profile만 두면 **meta를 포함한 어느 repo든 소비자가 될 수 있다.**
3. profile 부재 처리는 codex-gate와 **반대 방향**: 조용한 skip이 아니라 **degraded 실행 + 명시 warning**.

## 1. 배경 / 문제

### 1.1 기능 동기 (전략 초안 요약)

codex-gate는 "코드 변경 후" 안전장치로 효과가 좋지만, 문서/설계/운영 결정은 **변경 전 분석 단계**에서
문제가 생긴다. 현재는 Claude 제안 → 사용자가 Codex에 수동 복사 → 의견 회신 → 반복 수렴이라는
수동 ping-pong이 필요하다. 이를 `/proposal-review` slash command로 줄인다
(Claude가 proposal 정리 → runner가 read-only `codex exec` → schema 고정 verdict 회신).

### 1.2 범위 충돌 (이 문서가 해소하는 것)

| 문서 | 충돌 문언 |
|---|---|
| `.claude-plugin/plugin.json` | "runtime harness ... **monitoring-meta is out of scope**" |
| `h4-meta-readiness.md` | "이 플러그인은 **런타임(코드 실행) 하네스 전용**" — meta NO-GO의 근거 |

proposal-review는 문서/정책/설계 결정 리뷰 도구라 문언상 이 범위 밖이다. 그런데 결정이 가장 많이
발생하는 repo가 meta이므로, **최대 수요처가 문언상 배제되는 모순**이 생긴다.

## 2. H4 재해석 (결정)

> H4에서 제외(NO-GO)한 것은 **monitoring-meta의 Stop hook 기반 runtime codex-gate 통합**이다.
> 근거였던 "meta gate는 core의 상위집합·범주가 다름"은 **Stop hook 게이팅**에 대한 판단이며 유효하다.
> proposal-review는 runtime gate가 아니라 사용자가 명시 호출하는 decision-review command이므로,
> H4 A안(meta 자체 gate 유지)과 충돌하지 않는다. meta는 자체 codex-gate를 유지한 채
> proposal-review의 소비자가 될 수 있다.

H4 문서 본문은 수정하지 않는다(당시 판단 기록으로 동결). 이 재해석 문서가 현행 해석의 기준이다.

## 3. plugin 2축 정의 (결정)

| | ① codex-gate | ② proposal-review |
|---|---|---|
| 시점 | 변경 **후** 안전장치 | 변경/결정 **전** 합의 장치 |
| 발동 | Stop hook (글로벌 자동) | slash command (사용자 명시 호출) |
| 대상 | 코드/런타임 변경 | 문서·정책·설계·운영 결정 |
| 소비자 | hub, script-agent (**meta 범위 밖** — H4) | profile 둔 모든 repo (**meta 포함 가능**) |
| profile 부재 | 조용히 skip (graceful-skip 결정) | **degraded 실행 + 명시 warning** (§4) |
| 실패 처리 | state/fail streak/escalation (비대화형 탈출 장치) | 없음 — 시끄럽게 실패, 사람이 재시도 (대화형) |

둘을 합치지 않는다. Stop hook이 무거워지면 문서 작업 전체의 마찰이 커진다(전략 초안 결정 유지).

`plugin.json` description은 2축으로 갱신한다:

> Provides runtime codex-gate (Stop hook) for script-agent/hub, and an on-demand
> proposal-review command for design/policy decisions. monitoring-meta remains out of
> scope for runtime codex-gate (H4); proposal-review is available to any repo via
> convention profile, including monitoring-meta.

### 3.1 proposal-review 발동 — 두 모드 (수동 + handoff checkpoint)

§3 표의 "사용자 명시 호출"은 proposal-review의 **첫 발동 모드**다. 이후
`proposal-review-handoff-checkpoint.md` 결정으로 **두 번째 모드(필수 자동 checkpoint)**가 추가됐다.
둘은 같은 command/runner를 쓰는 **공존 모드**이며, 이 절은 그 사실을 문서에 반영해 실제 동작(consumer
`CLAUDE.md` §5)과의 drift를 해소한다.

| 모드 | 발동 | 시점 | SoT |
|---|---|---|---|
| (a) 수동 | `/proposal-review` 사용자 명시 호출 | 임의 | 이 문서 §3·§4 |
| (b) handoff checkpoint | **필수 1회 자동** 호출 | analyzer 직후·implementer 진입 전 | **consumer repo `CLAUDE.md` §5** |

- (b)는 analyzer→implementer 파이프라인을 가진 runtime repo(hub·script-agent)에만 적용된다.
  (infra는 해당 파이프라인이 없는 경량 소비자라 비대상. meta는 runtime 범위 밖 — H4.)
- **codex-gate와 융합하지 않는다(§3 "둘을 합치지 않는다" 유지)**: (b)는 Stop hook에 단계를 더하는
  것이 아니라, 기존 `/proposal-review` command/runner를 파이프라인의 한 지점에서 호출할 뿐이다.
- **(b)도 자동 수렴 loop 없음(§5 유지)**: verdict가 `approve`가 아니면(=`revise`/`block`) 보고 후
  **중단**하고 사람이 중재한다. checkpoint는 게이트일 뿐 수렴 엔진이 아니다.
- 발동 시점·게이트 규칙의 결정 근거는 [`proposal-review-handoff-checkpoint.md`](proposal-review-handoff-checkpoint.md).
  consumer 호출 순서의 SoT는 각 repo `CLAUDE.md` §5다(이 문서는 plugin 범위 정의 — 호출 순서는 consumer 소유).

## 4. profile 부재 = degraded 실행 (결정)

`codex-gate-graceful-skip.md` §2의 **의도 신호 원칙**을 적용하면 codex-gate와 결론이 반대가 된다:

| | codex-gate (Stop hook) | proposal-review (command) |
|---|---|---|
| 발동 | 글로벌 자동 — 의도 신호 없음 | **사용자 명시 호출 = 의도 신호 있음** |
| profile 부재 | 정상 상태(비소비자) → 조용히 exit 0 | repo 문맥 없이도 **실행은 하되, 그 사실을 시끄럽게** |

- profile(`.claude/proposal-review.profile`) 부재 시: 공통 프롬프트만으로 **degraded 실행**.
- **warning은 stderr가 아니라 산출물에 박는다**: verdict JSON에 문맥 상태 필드(예:
  `"context": "none (no profile)"`)로 포함. 이유 — 이 도구의 산출물은 `--out`으로 결정 근거에
  남을 수 있으므로, "repo 문맥 없이 리뷰됐다"는 사실이 산출물 자체에서 읽혀야 한다.
  stderr warning은 중계 과정에서 누락될 수 있다.
- profile의 문맥 문서(`PROPOSAL_REVIEW_CONTEXT_DOCS`) 중 없는 파일은 fail이 아니라 warn 처리
  (형제 repo 상대경로는 workspace 배치 의존 — consumer 책임으로 수용하되 runner는 견고하게).

## 5. MVP 구조 (결정)

```text
commands/proposal-review.md                  # slash command 정의 (Claude 절차 지시)
shared/analysis/proposal-review-runner.sh    # 최소 runner: 입력 조립 → codex exec → JSON stdout
shared/analysis/proposal-review.prompt.md    # 공통 리뷰 프롬프트 (긴 텍스트는 파일로)
shared/schemas/proposal-review-schema.json   # 출력 schema (codex-schema.json 옆, 하이픈 네이밍 일치)
```

- **state 머신 미도입**: codex-gate core의 state/fail streak/escalation은 비대화형 hook의
  탈출 장치다. command는 대화형이므로 가져오지 않는다(과설계). verdict 해석도 Claude가 한다.
- **schema 어휘**: `critical_issues` (기존 codex-schema.json과 통일. `critical_findings` 기각).
- **verdict**: `approve | revise | block` 3값. 경계를 prompt에 명시 —
  `block` = 방향 자체가 틀렸거나 기존 결정 기록과 충돌 / `revise` = 방향은 맞고 보완 필요.
  "판단 불가"는 `missing_context` + `confidence: low`로 표현(4번째 verdict 불필요).
- **`--out` 옵션 MVP 포함**: proposal + verdict를 파일로 남겨 handoff/decisions 흐름에 연결.
- **proposal 전달은 stdin/파일** (argv 금지 — Windows 명령행 길이 제한).
- runner는 core의 교훈 중 **선별** 재사용: `--sandbox read-only`, `--output-schema`,
  `PYTHONIOENCODING=utf-8`, `.gitattributes` LF 보장. schema는 flat + 전 필드 required
  (`skills/codex-gate-authoring` §2 함정).
- **자동 수렴 loop 미도입**: 두 모델 간 ping-pong 자동화는 진동 위험. `revise` 반복은 사람이
  중재한다. 추후 자동화하더라도 반복 상한 + escalation이 선행 조건.

## 6. 미결정 사안

- **Windows shell 실행 경로 1회 실험**: slash command에서 Claude의 Bash tool이 runner를 어떤
  shell로 실행하는지 **배포된 plugin 캐시 기준으로** 1회 확인 후 호출 방식을 확정한다.
  - Git Bash 확인 시 → command md에 `bash "${CLAUDE_PLUGIN_ROOT}/..."` 명시 호출 + 전제를 기록
  - 편차 발견 시 → 기존 `git-bash.cmd` shim 경유로 통일
  - (이번 세션 관측: 이 머신의 Bash tool은 Git Bash로 동작 — 단 1대 관측이라 단정하지 않음.
    hook과 실행 경로가 다름: hook = harness가 cmd로 직접 spawn → shim 필수였음)
  - **소스 기준 실험 완료 (2026-06-07)**: Bash tool에서 runner 전체 파이프라인(가드 4종 +
    degraded/profile 실연동 `codex exec` 2회 + `--out` 아티팩트)을 Git Bash로 실행, 전부 통과.
    같은 제안이 degraded에선 `revise`(medium), consumer-contract.md 문맥 주입 후엔 `block`(high,
    사유 = H5 결정과 충돌)으로 판정 — verdict 경계가 의도대로 작동함을 실증.
    **남은 것은 배포 캐시 경로(`${CLAUDE_PLUGIN_ROOT}` 치환) 기준 1회 재확인뿐.**
  - 부수 관측: MSYS 경로 변환은 **argv로 넘어가는 경로만** Windows 경로로 변환한다.
    python `-c` 스크립트 문자열 안에 박힌 `/tmp/...` 경로는 변환되지 않으므로, runner처럼
    경로를 반드시 argv로 전달해야 한다(현 구현이 그렇게 함 — 유지할 것).
  - **배포 캐시 기준 검증 완료 (2026-06-07, 캐시 `62b896287963`)**: 캐시된 runner 가드 +
    codex-gate 회귀 3종 + 라이브 `/proposal-review` 호출(`${CLAUDE_PLUGIN_ROOT}` 치환 확인) 통과.
    단 marketplace 소스 repo(harness 자신)에서는 `${CLAUDE_PLUGIN_ROOT}`가 캐시가 아니라
    **로컬 repo 경로**로 치환된다(dev 모드) — consumer repo에서는 캐시 경로다.
  - **라이브 검증에서 발견·수정한 함정**: `CLAUDE_PROJECT_DIR`는 **hook 컨텍스트 전용** 주입
    변수다 — command가 쓰는 Bash tool 환경에는 없다. 초기 구현은 이 변수로만 convention 경로를
    풀어 consumer에서 profile이 있어도 항상 degraded로 빠졌다. `git rev-parse --show-toplevel`
    fallback으로 수정(runner). **교훈: hook 주입 변수를 command 경로에서 재사용할 때는 주입
    여부를 반드시 실측할 것.**

## 7. 후속 작업 (H6 체크리스트)

- [x] milestones.md에 H6 등록 ("decision-review command 추가 — scope 재해석 포함")
- [x] `plugin.json` description 2축 갱신 (§3 문안) — marketplace.json도 함께
- [x] README에서 runtime gate / decision-review command 분리 설명
- [x] commands / runner / prompt / schema 구현 (§5) — 가드 4종 + 실연동 2회 스모크 통과
- [x] shell 실행 경로 1회 실험 → 호출 방식 확정 (§6) — **소스 기준 완료**, 배포 캐시 기준 재확인만 남음
- [x] consumer 1곳(hub/script-agent/meta 중)에 profile 두고 실전 1회 → prompt/schema 조정
  — **meta 완료 (2026-06-07)**: `.claude/proposal-review.profile`(문맥 6개 + 통합본 발췌 원칙,
  170KB라 상시 주입 제외). 실전 리뷰 verdict `revise`(medium) — Codex가 "profile 탐색이 미배포
  a455246에 의존"하는 배포 공백을 정확히 지적(§6에서 발견한 함정과 동일 지점). 권고 반영해
  profile에 적용 조건·drift 완화 DoD·dry-run 절차 주석 추가. prompt/schema 조정 필요 없음.
- [x] `docs/proposal-review-strategy-draft.md` → archive 이동 (이 문서가 결정본)
