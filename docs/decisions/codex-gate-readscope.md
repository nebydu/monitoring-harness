# codex-gate-readscope — Codex 리뷰 샌드박스 읽기범위 최소권한화 (후속 트랙)

> codex-gate의 Codex 리뷰가 형제 repo 기준 문서를 읽는 방식에 대한 결정 기록 + 후속 작업 spec.
> **임시 조치(A) + 가드 2종은 이미 적용됨**(`feb0331`). 이 문서는 배경·이미 한 것·남은 트랙을
> 추적한다.
>
> 위치 메모: 이 후속 작업은 codex-gate 코어(harness)와 consumer profile(infra/hub/script-agent/
> meta)에 걸친다. handoff 정식 위치는 monitoring-meta지만 **형제 repo 쓰기 가드(pre-write-guard)로
> infra 세션이 meta에 직접 쓸 수 없어**, 게이트를 소유한 harness repo의 설계기록으로 둔다.
> **meta TODO**: §5 트랙 착수 시 meta가 `handoff/codex-gate-readscope/`로 work-id를 정식 등록하고
> consumer profile 일괄 수정을 per-repo handoff로 라우팅한다(이 문서를 근거로).

## 0. 정정 (2026-06-14) — 원인 진단 수정

> 작성 당시 §2의 인과("Windows read-only 샌드박스가 cwd 밖 읽기를 막는다")는 **틀렸다.**
> 실측으로 반증했으므로 결정 기록을 정정한다(이력 보존: §2~§3의 원문은 그대로 두되 본 절을 우선한다).

**확인 사실(2026-06-14 실측):**
- Windows codex 0.139 `[windows] sandbox = "elevated"`는 read-only에서도 형제 repo 읽기를 **OS 레벨에서 막지 않는다**(setup 로그 매회 `read roots delegated`). cwd=infra에서 `../monitoring-meta` 읽기가 `disk-full-read-access` **플래그 유무와 무관하게** 성공(재현 2회 + 옛 stderr의 PowerShell Get-Content "succeeded" 다수).
- 이 monitoring 워크스페이스는 **CI/Linux 실행 이력이 0건**(5 repo 모두 CI 설정 부재, codex-gate는 Stop hook이라 구조적으로 CI 미발동). 즉 phase1-041 증상도 검증도 **100% Windows**.

**인과 정정:**
- §2가 이미 관찰한 **비결정성**("6/11엔 PASS")이 결정적 반증이다 — OS 읽기 차단이면 *항상* 실패해야 한다. 비결정적이라는 건 차단 주체가 OS 샌드박스가 아니라 **Codex 에이전트의 행동**(그 턴에 형제 경로를 읽으려 시도하느냐)이었다는 뜻이다.
- 따라서 (A) `disk-full-read-access`(ac4babe)는 **Windows에선 no-op**이고, Windows phase1-041 false-negative의 근본 원인 수정이 아니다. 테스트도 Windows였다면 플래그를 빼도 통과했을 것 → "플래그 → 통과"의 인과는 성립하지 않는다.
- **실질 해결책은 플래그가 아니라 profile 프롬프트의 명시적 형제 경로**(`../monitoring-meta/...`)다. 현재 모든 consumer profile이 경로를 명시하고 있어 Codex가 정상적으로 읽고 검증한다(escalation/block 로그 0건).

**그래서 (A)를 어떻게 하나:** **롤백하지 않는다.** Windows에선 무해하고, §5 §B에서 비-Windows(Landlock/Seatbelt)로 이전하거나 `--cd`로 범위를 바꾸면 그때는 read-only가 읽기를 실제로 한정하므로 동등한 권한 확보가 필요해진다. 단 §5의 긴급도는 더 낮아진다(현재 Windows에선 (A) 없이도 동작).

## 1. 헤더

| 필드 | 값 |
|---|---|
| work-id | `codex-gate-readscope` |
| 대상 | `monitoring-harness`(코어) + consumer profile(infra/hub/script-agent/meta) |
| 기준 meta commit | `14b4936` (작성 시점) |
| 촉발 | `phase1-041-infra`(T4-2 토픽 분리) Stop 시 codex-gate false-negative |
| 작성일 | 2026-06-13 |
| 관련 | `codex-gate-graceful-skip.md`, meta handoff `codex-gate-commit-window` |

## 2. 배경 / 문제

codex-gate(Stop hook, 골격 `shared/hooks/codex-gate-core.sh`)는 consumer 변경을 Codex로
`--sandbox read-only` 리뷰한다. consumer profile 프롬프트(예: infra `codex-gate.profile`)는
통합본(`../monitoring-meta/docs/master-design.md`)·ADR-0005·kafka-payloads 등 형제 repo
monitoring-meta의 기준 문서 교차검증을 지시한다.

Codex는 cwd=repo 루트(infra)에서 돌고, Windows의 read-only 샌드박스는 cwd 밖
(`../monitoring-meta`) 읽기를 막는다. → phase1-041-infra Stop 검증에서 Codex가 기준 문서를
읽으려다 실패해 "기준 문서 읽을 수 없음" critical로 **fail-closed(false-negative)**. 동형 compose
변경이 6/11엔 PASS했어서, Codex가 문서를 읽으려 시도하는지에 따라 결과가 흔들리는 **비결정성**도
드러났다.

## 3. 이미 적용 — 임시 조치 (A) + 가드 2종 (`feb0331`, 소스 `ac4babe`)

- **(A)** `codex exec`에 `-c 'sandbox_permissions=["disk-full-read-access"]'`. read-only 유지
  (쓰기·네트워크 차단), 디스크 읽기만 전체 허용. codex-cli 0.139.0에서 ../monitoring-meta 판독 실증.
  라이브 캐시 `9eb965ef6edd` 직접 반영.
- **가드①(만료 조건)**: 코어 주석에 "임시 예외 + 만료 조건 + 추적 work-id" 명시.
- **가드②(비밀 가드)**: 프롬프트에 범위 밖·비밀/자격증명 파일 열람 및
  critical_issues/spec_violations 인용 금지 주입.

## 4. proposal-review가 잡은 핵심 (verdict revise, confidence medium)

1. **간접 유출 경로**: 네트워크 차단만으로 불충분 — 읽은 내용이 로그·리뷰 본문·산출물로 샐 수
   있다. (실측: 산출물은 `~/.claude/plugins/data/...` = repo 미커밋. Codex가 비밀을 verdict
   문자열에 인용하면 Stop 메시지로 노출 가능 → 가드②로 완화.)
2. **만료 조건 부재** → 가드①로 명시.
3. **(B) 범위 정정**: cwd=워크스페이스 루트로 올리면 infra+meta만이 아니라 **그 아래 모든
   monitoring repo**(hub·script-agent·monitoring-harness)가 읽힌다. "infra+meta만"은 틀렸다.
   (B)는 홈 비밀(~/.ssh 등)은 제외하나 절대 최소권한은 아님.
4. **프로세스**: 변경이 work-id 추적 밖에서 나갔다 → 이 문서로 추적화.

## 5. 남은 트랙 (착수 시 실행)

### §B 최소권한화 — (A) 교체
- **후보 B1**: Codex `--cd` = 워크스페이스 루트. read-only가 그 아래만 포함(홈 비밀 제외).
  단 모든 consumer profile 프롬프트의 `../monitoring-meta` → `monitoring-meta`, repo 자기 파일
  표기도 `infra/...`로 일괄 수정 필요. **정정된 범위(모든 monitoring repo 포함)를 문서화**할 것.
- **후보 B2**: 전용 리뷰 워크스페이스 — 대상 repo + monitoring-meta만 심볼릭/복사한 격리 디렉터리
  에서 Codex 실행(진짜 최소권한). 복잡도↑.
- DoD: `-c sandbox_permissions=disk-full-read-access` 제거, 대표 consumer 1개 이상에서 기준 문서
  교차검증 PASS 회귀 샘플 확인, profile 경로 수정 체크리스트(누락 시 fail-closed 재발) 통과.

### §C 비결정성 완화 — 필수 발췌 manifest
- 전면 주입(174KB master-design) 대신 work-id별 **필수 발췌 manifest**(관련 handoff + ADR/doc
  발췌만)를 REVIEW_INPUT에 주입. 토큰비용 vs 결정성 절충 기준 정의.

### §D 유출경로 점검
- 산출물(`LAST_MSG`/`ISSUES_FILE`/로그) 저장 위치·접근권한 점검, 실패 메시지 길이 cap, 로그 원문
  파일 내용 출력 금지 확인. (가드②는 프롬프트 레벨 — §D는 코드 레벨 보강.)

## 6. 결정 필요 (meta/사람)

- §B를 B1(cwd-워크스페이스) vs B2(전용 워크스페이스) 중 무엇으로.
- §C manifest 도입 여부(게이트 토큰비용 증가 수용).
- 착수 시점 — 현재 (A)+가드로 unblock 상태라 긴급도 낮음.
