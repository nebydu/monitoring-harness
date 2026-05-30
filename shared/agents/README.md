# shared/agents

향후 **agent scaffold**(C4)가 놓일 **위치 예약** 디렉터리다.

## 현재 상태 (H0)

- **비어 있다.** H0에서는 agent migration을 하지 않는다.

## 들어올 것 (공통 골격)

`hub`/`script-agent`가 공유하는 **6역할** scaffold 골격:

`analyzer` / `implementer` / `tester` / `reviewer` / `spec-guardian` / `refactorer`

- frontmatter 형태(`name` / `description` / `tools` / `model`)
- 역할별 도구 권한 형태
- 호출 순서 / 재시도 한도
- 공통 결과 스키마(`status | outputs | findings | blockers | next_action`)

## 들어오지 않을 것 (consumer delta)

- reviewer **critical** 판정 기준 (예: 모듈 경계 위반)
- spec-guardian **도메인 판단** (phase 분류, envelope 헤더 준수 등)
- **phase 불변식** (Phase 0/1 구분, Job 실행 규칙 등)

도메인 룰은 **consumer의 `CLAUDE.md`/agent에 남긴다.**

> `monitoring-meta`는 3역할(analyzer/spec-sync/e2e-tester)로 구성이 달라, 공통 scaffold 적용 여부는
> H4에서 별도 판단한다. → [`../../docs/milestones.md`](../../docs/milestones.md)
