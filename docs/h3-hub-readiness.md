# H3 — hub 적용 여부 판단 (검증 보고 + 권고)

H3는 **판단 단계**다. script-agent(H2-B) 적용을 검증하고, hub가 같은 plugin 모델로 전환 가능한지
분석해 **가부를 권고**한다. hub repo는 수정하지 않는다(실제 적용은 사람 확인 게이트).

## 1. script-agent(H2-B) 적용 검증

- **cutover 완료·커밋**(`f1092e3`): native `.claude/hooks/codex-gate.sh` 삭제, settings.json Stop hook
  제거(`PreToolUse`만 유지)·`enabledPlugins` 기록, convention profile 커밋. plugin codex-gate가 단일
  Stop 게이트.
- **런타임 동등성 통과**(H2-B): 원본 gate vs plugin(entry→profile→core) — pass/fail/parse_error/skip 일치.
- **회귀 신호**: 게이트 로직(트리거/스킵/verdict/exit/escalation)이 동등하고 구조 변경이 없어, 기능 회귀
  요인이 없다. 장기 운영 관측은 달력 시간이 필요하나, 현재까지 부정 신호 없음.
- **gotcha 해결**: project scope의 per-user config·절대경로 문제는 convention 경로 주입으로 제거됨.

→ script-agent 적용은 **안정적**이며, hub 판단의 전제(검증된 1개 consumer)가 충족된다.

## 2. hub gate 구조 분석 (read-only)

hub `.claude/hooks/codex-gate.sh`(193줄)는 script-agent 원본(195줄)과 **실행 골격이 동일**하다.
경로 정의·`log_line`·state·stop-loop·트리거 가드·검토 입력 조립·`codex exec`·python 파싱·verdict
분기·escalation 임계(fail>3 / parse≥2)가 공통 골격과 일치한다. 차이는 **주입점뿐**:

| 항목 | hub delta |
|---|---|
| trigger | `src/main/*`, `src/test/*`, `pom.xml` |
| skip | `.claude/*`, `docs/*`, `analysis/*` (script-agent와 동일) |
| skip 메시지 | "src/main, src/test, pom.xml ..." |
| prompt | Java/Spring, §7.2 β 모듈 경계, `mvn package` |
| 임계값 | fail 3 / parse 2 (= core 기본값) |

### cosmetic 변이 2개 (기능 무관, blocker 아님)

1. `emit_system_message`: hub는 `python ... sys.stdout.reconfigure(encoding="utf-8")`, core는
   `PYTHONIOENCODING=utf-8 python ...`. **둘 다 UTF-8 출력 — 동작 동일.**
2. `escalate` 메시지: hub는 `"게이트 강제 통과..."`(접두어 없음), core는 `"[codex-gate] 게이트 강제
   통과..."`. **system message 문구만 다름**(게이트 판정/exit 불변). core로 가면 escalate 문구에
   `[codex-gate]` 접두어가 붙어 pass/skip 메시지와 일관돼지는 정도(개선).

## 3. 동등성 실증 (샌드박스, 수행함 — hub read-only)

hub 레이아웃 모사 repo에서 원본 hub gate vs plugin(core + `hub.profile.example`) 비교:

| 시나리오 | 원본 | plugin | 일치 |
|---|---|---|---|
| src/main 변경 + pass | `0\|pass` | `0\|pass` | ✅ |
| src/main 변경 + fail | `2\|fail` | `2\|fail` | ✅ |
| 파싱 실패 | `2\|parse_error` | `2\|parse_error` | ✅ |
| docs만 변경(스킵) | `0\|skipped` | `0\|skipped` | ✅ |
| pom.xml 변경(트리거) | `0\|pass` | `0\|pass` | ✅ |

→ 공통 골격 + hub profile이 hub 현행 gate를 **완전히 재현**한다. 구조적 갭 없음.
(profile 예시: [`../shared/hooks/profiles/hub.profile.example`](../shared/hooks/profiles/hub.profile.example))

## 4. 리스크 / 주의

- **PreToolUse `pre-write-guard.sh`**: hub 고유 PreToolUse 가드로, codex-gate(Stop)와 무관. plugin은
  Stop hook만 제공하므로 **충돌·영향 없음**(script-agent의 `deny-write-paths.sh`가 그대로 남은 것과 동일).
- **schema CRLF**: hub `codex-schema.json`은 CRLF(484B)지만 내용은 공통 1부와 동일(정규화 sha 일치).
  plugin이 LF 공통 1부를 제공하므로 전환 시 일관됨.
- **`settings.local.json`**: hub 로컬 설정. plugin enablement(project scope)와 무관, 영향 없음.
- **중복 게이트**: 전환 시 script-agent와 동일하게 native Stop hook 비활성 필요(cutover 절차). 순서:
  설치 → `/plugin update` → 재시작·검증 → native hook 비활성 → 커밋.

## 5. 권고: **GO** → 적용 완료 (`cb347a9`)

> **적용됨**: 사람 승인 후 hub를 plugin으로 전환 완료(`cb347a9`) — project scope 설치,
> `hub/.claude/codex-gate.profile` 커밋, native `codex-gate.sh` 삭제, settings.json Stop hook 제거
> (PreToolUse 유지). 라이브 Stop 발화는 재시작 후 적용. 아래는 권고 당시 근거.


hub는 script-agent와 동일한 구조라 **clean 후보**다. 공통 골격이 hub gate를 완전히 재현함을 실증했고,
구조적 갭·기능 회귀 요인이 없으며, project-scope gotcha는 이미 해결됐다. cosmetic 변이 2건은 무해(1건은
경미한 개선).

**미해결 판단 요소(사람 몫)**: script-agent의 운영 기간이 충분한지(달력 시간), hub를 지금 전환할지 H4
이후로 둘지.

## 6. 적용 시 절차 (요약, 적용 결정 시)

[`installation.md`](installation.md) 표준을 hub에 적용:
1. hub repo에서 `claude plugin marketplace add` + `install --scope project`(--config 불필요, convention).
2. `hub/.claude/codex-gate.profile` 작성([`hub.profile.example`](../shared/hooks/profiles/hub.profile.example) 복사) + 커밋.
3. `/plugin update` → 재시작 → 대표 변경(src/main, pom.xml)에서 Stop 동등 동작 확인.
4. native `.claude/hooks/codex-gate.sh` 삭제 + settings.json Stop hook 제거(PreToolUse 유지) → 커밋.

**rollback**: `claude plugin uninstall` + hub `.claude/` git 원복 → 기존 gate로 즉시 회귀.
