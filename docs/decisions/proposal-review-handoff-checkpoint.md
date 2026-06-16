# proposal-review를 handoff 파이프라인의 필수 checkpoint로 승격

meta handoff 기반 runtime repo 작업에서 **implementer 진입 전 1회 proposal-review를 필수**로
거치도록 승격하는 결정 기록이다. 기존에 사람이 손으로 하던 `plan → proposal-review` 습관을
flow에 흡수해, analyzer 산출물이 검토 없이 구현으로 직행하지 않게 한다.

- 발단: 수동 plan→proposal-review 습관의 flow 흡수 (analyzer→implementer 사이 검토 공백)
- 관련: `proposal-review-scope.md`(2축 정의·비합치 원칙), `codex-gate-graceful-skip.md`(의도 신호),
  `h4-meta-readiness.md`(meta 범주)
- 교정 메모: 원안은 이 checkpoint의 evidence를 ROADMAP **DoD-7**에 연결했으나, DoD-7은
  source_ref drift 관심사라 **범주 오류**다. 본 문서는 그 연결을 제거한 교정안이다(§4 비범위 참조).

## 결론 요약

1. **필수 checkpoint**: meta handoff 기반 runtime repo 작업은 **implementer 진입 전** analyzer
   산출물을 `proposal-review`로 **1회** 검토한다(필수). verdict가 **`approve`가 아니면(=`revise`/`block`)
   구현하지 않는다** — 사람이 중재한다.
2. **자동 수렴 loop 없음**: `revise` 반복을 모델끼리 자동 ping-pong하지 않는다(scope §5 결정 유지 —
   진동 위험). checkpoint는 게이트일 뿐, 수렴 엔진이 아니다.
3. **2축 비합치 보존**: codex-gate(Stop hook)에 **융합하지 않는다.** 기존 `/proposal-review`
   command/runner를 **그대로 재사용**할 뿐이다(scope §3 "둘을 합치지 않는다").

## 1. 결정 상세 — checkpoint 위치와 게이트 규칙

적용 대상은 **analyzer→implementer 파이프라인을 가진 runtime repo**(hub, script-agent)다.
(infra는 해당 파이프라인이 없는 경량 소비자라 이 checkpoint 대상이 아니다 — codex-gate/write-guard만
사용. meta는 runtime codex-gate 범위 밖 — H4.)

```text
meta handoff(작업 spec) → [runtime repo] analyzer 산출물
        → ★ proposal-review 1회 (필수 checkpoint) ★
              approve     → implementer 진입(구현)
              revise/block → 중단, 사람이 중재(재분석 또는 결정 보정)
```

- **1회**다 — 자동 재시도/수렴 loop 없음. `revise`/`block`이면 사람이 개입한다.
- `block`/`revise` 경계는 scope §5 정의를 따른다(`block`=방향·기존 결정 충돌 / `revise`=방향 맞고 보완).
- 판단 불가는 `missing_context` + `confidence: low`로 표현된다(verdict 4번째 값 없음 — scope §5).

## 2. 근거

- 현행은 Claude 제안 → 사람이 수동으로 proposal-review 호출 → 진행 판단이라는 **비공식 습관**이다.
  공식 checkpoint가 아니면 바쁠 때 생략돼 검토 없이 구현으로 직행하는 사각지대가 생긴다.
- analyzer→implementer 경계는 "방향이 굳기 직전" 지점이라, 변경 **전** 합의 장치인 proposal-review의
  설계 의도(scope §1.1)와 정확히 맞는다. 새 메커니즘이 아니라 **기존 습관의 flow 편입**이다.

## 3. 2축 비합치 보존 (scope §3 재확인)

이 승격은 **codex-gate에 새 단계를 더하는 것이 아니다.** Stop hook(codex-gate)은 그대로 두고,
이미 있는 `/proposal-review` command/runner(`shared/analysis/proposal-review-runner.sh`)를
파이프라인의 한 지점에서 호출할 뿐이다.

- Stop hook에 검토 단계를 융합하면 문서/분석 작업 전체의 마찰이 커진다(scope §3 "둘을 합치지 않는다",
  전략 초안 결정). 그 원칙을 깨지 않는다.
- 즉 plugin **2축 정의는 불변**이다: ① codex-gate(Stop) / ② proposal-review(command). 이 결정은
  ②의 **호출 시점을 파이프라인에 고정**할 뿐, 축을 늘리거나 합치지 않는다.

## 4. 비범위 (엮지 않는 것)

- **ROADMAP DoD-7(source_ref drift 없음)**: 별개 관심사다. checkpoint evidence를 DoD-7에 연결하는
  것은 범주 오류라 **하지 않는다**(원안 교정 사유). checkpoint는 "구현 전 방향 검토"이고, DoD-7은
  "산출물의 source_ref 정합"이다 — 서로 다른 축.
- **Phase 1 도메인 backlog(T-항목)**: 이 결정은 프로세스 게이트이지 도메인 작업이 아니다. T-항목과
  분리해 추적한다.

## 5. Evidence (검증 상태)

- **검증 예정 (아직 미실시)**: handoff 1건 드라이런으로 두 경로를 실증한 뒤 결과를 여기 연결한다 —
  (a) `approve` → implementer 진행 / (b) 非approve(`revise`/`block`) → 중단·사람 중재.
  - 현재 이 결정에 연결된 드라이런 산출물은 없다. (추측으로 채우지 않는다.)
  - 드라이런 시 `proposal-review --out` 아티팩트(top-level `verdict`/`degraded`)를 근거로 남기고,
    그 경로를 본 절에 링크한다.

## 6. 영향 파일 (후속 — 본 작업 범위 밖)

이 결정을 반영하려면 아래가 갱신돼야 한다. **이 커밋에서는 수정하지 않는다**(decisions 새 파일만).

- `hub/CLAUDE.md` §5 / `script-agent/CLAUDE.md` §5 — 호출 순서에 implementer 전 proposal-review
  필수 checkpoint 1줄 추가.
- `hub/.claude/agents/implementer.md` / `script-agent/.claude/agents/implementer.md` — 진입 전제로
  "analyzer 산출물의 proposal-review `approve`"를 명시.
- `proposal-review-scope.md`(scope 문서, 직전 작업 item 8의 대상) — 2축 정의에 "②의 호출 시점이
  파이프라인 checkpoint로 고정됨"을 한 줄 보강(축 추가 아님).
- (decisions `README.md` 색인 항목 추가 — 본 파일 등록. 역시 후속.)
