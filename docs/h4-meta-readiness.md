# H4 — monitoring-meta 적용 여부 판단 (분석 + 권고)

H4는 **판단 단계**다. monitoring-meta가 공통 codex-gate 골격으로 전환 가능한지 분석해 가부를
권고한다. meta repo는 수정하지 않는다(실제 적용은 사람 확인 게이트).

## 결론 요약

**결정: NO-GO 확정 (A안 — meta 자체 gate 유지).** meta의 gate(278줄)는 hub/script-agent(193/195줄)와
달리 **공통 골격의 상위집합(superset)** 으로 진화해 있어, 현재 core로 전환하면 **기능 회귀**가 발생한다.
따라서 meta는 자체 gate를 유지하고 **drift 관리 예외**로 명시한다. core를 meta 수준으로 확장하는
B안(core v2)은 선택적 후속 과제(H6 후보)로 남긴다.

## 1. meta gate가 공통 골격에 없는 기능 (구조적 발산)

| 기능 | meta gate | 공통 core | 영향 |
|---|---|---|---|
| **gate_key 콘텐츠 캐싱** | `passed`/`escalated`를 gate_key(diff+prompt+schema+hook 해시)로 캐시 → 같은 변경분 재Stop 시 `already_passed`/`already_force_passed`로 SKIP | 없음 — 매 Stop마다 Codex 재호출 | **회귀**: 비용 증가, 무의미한 재검증 |
| **2-모드 트리거 + 프롬프트 병합** | spec(adr·docs·handoff/adr) / harness(.claude hooks·settings·schema) 분류 후 두 프롬프트 합산 | 단일 `CODEX_GATE_PROMPT` | **표현 불가**: 단일 주입점으로 병합 못 함 |
| **리치 JSON 상태** | gate_key·triggered·diff_hash·status·updated_at | 2정수 TSV(fail/parse) | 상태 의미 손실 |
| **fail streak 승계** | triggered(파일 집합) 일치 시 diff가 바뀌어도 fail 누적 | triggered 무관, 단순 카운터 | escalation 도달 정책 차이 |
| **per-file diff 리뷰 입력** | 트리거 파일별 `git diff -- $f` | 전체 `git diff` | 입력 구성 차이 |
| **harness 자기검토** | `.claude/hooks/*.sh`·settings·schema 변경을 gate가 스스로 리뷰 | 해당 파일이 plugin에 있어 meta repo엔 없음 | 자기검토 대상 소멸 |
| fail 임계 | `>= 3`(3회차 escalate) | `> FAIL_LIMIT`(기본 3 → 4회차) | `FAIL_LIMIT=2`로 튜닝은 가능(경미) |

상위 3개(캐싱/2-모드/JSON 상태)는 **주입점으로 흡수 불가**한 구조적 차이다.

## 2. 회귀 실증 (샌드박스, 수행함 — meta read-only)

동일 spec 변경에 대해 Stop을 2회 연속 실행:

| | meta-orig | core+근사 profile |
|---|---|---|
| 1st Stop | `0 \| pass` | `0 \| pass` |
| 2nd Stop | `0 \| skipped(already_passed)` | `0 \| pass` (Codex 재호출) |

→ 1회차는 일치하나 2회차에서 **meta는 캐시로 SKIP, core는 재검증**. core 전환 시 meta의 캐싱이 사라져
같은 변경분을 매번 다시 Codex로 검증한다(회귀). 2-모드 프롬프트는 근사조차 단일 프롬프트로 대체됨.

## 3. 추가 고려 (도메인/특성)

- meta는 **코드 미실행**·spec 정합성 도메인이라 build/test 명령이 없다(이건 주입점으로 처리 가능, 문제 아님).
- meta 도메인 판단(spec drift, Open-question을 무심코 결정했는지)은 **금지 원칙상 plugin으로 끌어올리지
  않는다** — 어차피 prompt(consumer delta)에 남는다.
- agent 구성(3역할: analyzer/spec-sync/e2e-tester)은 codex-gate 적용과 별개(C4 영역). H4 판단 대상 아님.

## 4. 권고 및 선택지

**권고: NO-GO** — 현재 공통 골격으로 meta를 전환하지 않는다(회귀 발생).

선택지:
- **A) meta 자체 gate 유지 (근시일 권장)**: meta는 가장 진화한 gate를 그대로 둔다. hub/script-agent만
  plugin으로 공통화된 상태로 마무리. drift 관리 대상에서 meta gate는 예외로 명시.
- **B) core v2로 확장 후 통합 (후속 과제)**: 공통 core에 gate_key 캐싱·2-모드 프롬프트(예: 여러 prompt
  슬롯 + 트리거 분류 주입)·JSON 상태를 흡수해 meta 수준으로 끌어올린다. 그러면 hub/script-agent도 캐싱
  이득을 본다. 단 **hub/sa 동등성 재검증**과 core 대규모 변경이 필요 → 별도 milestone(H6 후보).

> meta 도메인 룰은 어느 경우에도 consumer(meta `.claude/`)에 남는다. plugin은 도메인 결정을 하지 않는다.

## 5. 결정 (사람 확인 게이트)

**A안 확정**: meta는 자체 gate를 유지하고, 공통 plugin codex-gate로 전환하지 않는다. meta gate는
harness drift 관리의 **명시적 예외**다(상위집합이라 공통화가 곧 회귀이므로). B안(core v2 확장)은
선택적 후속 과제로 보류한다. meta repo는 **미수정**.
