# codex-gate graceful skip — profile 부재 처리 결정 기록

plugin codex-gate Stop hook이 **profile 없는 repo에서 세션 종료를 막던 문제**(exit 2)를
고치며 내린 설계 결정의 기록이다. 코드 변경은 `hooks/codex-gate-entry.sh` 가드 1곳이지만,
그 안에 hook 엔지니어링 결정 여러 개가 응축되어 있어 판단 근거를 남긴다.

- 반영 커밋: `b200cd5` (`hooks/codex-gate-entry.sh` + `shared/hooks/README.md`)
- 발단: monitoring-meta(비소비자 repo)의 세션 종료가 plugin 구성 오류로 매번 차단됨
- 지시서: `monitoring-meta/handoff/harness-codex-gate-graceful-skip/harness-codex-gate-graceful-skip.md` (완료 보고 포함)

## 결론 요약

**"profile 없음 = 오류"에서 "profile 없음 = 소비자 아님(조용히 skip)"으로.**
게이트는 opt-in 모델이 되고, fail-closed(Stop 차단)는 게이팅 의도가 확인된 경우로 한정한다.
명시 오설정(`CODEX_GATE_PROFILE` 지정 후 부재)만 기존대로 exit 2로 차단한다.

## 1. 글로벌 hook의 실패 방향 — fail-closed 적용 범위 한정

Stop hook은 plugin 특성상 user 레벨 활성 시 **모든 repo에 글로벌 등록**된다. 기존 코드는
"profile 부재"를 무조건 fail-closed(exit 2 = Stop 차단)로 처리해 **소비자가 아닌 repo까지
인질**이 됐다.

수정 후 fail-closed는 **게이팅 의도가 확인된 경우에만** 적용한다. 의도가 없는 repo는
fail-open(exit 0). 안전장치는 그 안전장치를 켠 대상에게만 작동해야 한다(blast-radius 한정).

## 2. 의도 신호로 오류와 정상 상태 구분

같은 "파일 없음"이 두 가지 의미를 가진다:

| 경로 결정 방식 | 의도 신호 | 해석 | 동작 |
|---|---|---|---|
| convention 자동 탐색(`<repo>/.claude/codex-gate.profile`) 실패 | 없음 | 정상 상태(비소비자) | exit 0 |
| `CODEX_GATE_PROFILE` 명시 지정 후 부재 | 있음 | 진짜 오설정/오타 | exit 2 + stderr 진단 |

구현 핵심은 `EXPLICIT_PROFILE` 변수의 분리 캡처(`entry.sh`) — PROFILE이 **어느 경로로
결정됐는지** 추적해야 이 구분이 가능하다. 오타를 조용히 삼키지 않으면서(명시 지정은 여전히
시끄럽게 실패) 비소비자를 막지도 않는다.

## 3. opt-in 소비자 모델 — 배포와 활성화의 분리

"plugin 설치됨(user 레벨 글로벌)" ≠ "이 repo가 게이팅됨(repo에 profile 존재)".

활성화 스위치가 **repo 안의 convention 파일**이므로 git으로 공유된다 — 협업자가 clone만
해도 같은 게이팅을 받고, per-user 설정이나 절대경로가 필요 없다. monitoring-meta가 쓰던
`enabledPlugins: {"harness@monitoring": false}` 같은 per-project settings 회피책이
불필요해진 이유다(해당 override는 meta `b284013`에서 제거 완료).

## 4. 노이즈 규율 — hot path에서의 침묵

skip 분기는 **비소비자 repo의 모든 세션 종료마다** 타는 hot path다. skip 메시지 1줄도
누적되면 noise라 `{"systemMessage":...}` 출력 옵션은 검토 후 **의도적으로 기각**했다
(지시서 §3.1에 결정 근거). 반대로 exit 2 쪽은 stderr 진단 메시지를 유지한다 —
**조용한 성공, 시끄러운 실패**.

## 5. 레이어 경계 보존 — entry에서 막고 core는 무변경

가드가 `source` **이전**에 위치하므로 core의 필수 주입점 검증·도메인 로직·profile 계약은
전부 무변경이다. entry = packaging 관심사(profile 해석·skip), core = 게이트 골격이라는
H5 패키징 분리가 그대로 유지되고, 회귀 검증 범위도 entry 가드로 한정할 수 있었다.

`set -euo pipefail`(nounset) 하에서 `${CODEX_GATE_PROFILE:-}` 기본값 확장으로 unset
변수를 안전하게 캡처한다 — `skills/codex-gate-authoring`이 다루는 알려진 함정 준수.

## 6. 배포 검증 — "소스 고침"이 아니라 "배포본이 동작함"까지

polyrepo 변경의 닫힌 루프로 진행했다:

1. meta 지시서(handoff) → harness 구현(`b200cd5`)
2. **캐시 해시 = 커밋 해시**(`~/.claude/plugins/cache/monitoring/harness/b200cd5bc148/`)로
   배포본 추적, 새 가드 존재를 grep으로 확인
3. 배포된 캐시 스크립트로 3개 시나리오 직접 실행:
   profile 부재 → exit 0·출력 0바이트 / 명시 오경로 → exit 2 / profile 존재 → source 진입
4. meta의 임시 회피책 제거(meta `b284013`) → 완료 보고 커밋(meta `9825980`)

현재 meta는 user 레벨 plugin 활성 + profile 부재로 plugin hook이 graceful skip하고,
게이팅은 자체 `.claude/hooks/codex-gate.sh`가 수행한다(이중 게이팅 없음 — H4 A안 유지).
