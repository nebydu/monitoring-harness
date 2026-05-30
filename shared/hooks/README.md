# shared/hooks

향후 **codex-gate 공통 골격**(C1)이 놓일 **위치 예약** 디렉터리다.

## 현재 상태 (H0)

- **비어 있다.** H0에서는 **실제 hook 구현 파일을 만들지 않는다.**

## 들어올 것 (공통 골격)

세 repo `codex-gate.sh`에서 동일한 부분만 골격으로 추출한다.

- 경로 정의 / `log_line` / `emit_system_message`(UTF-8 JSON) / `escalate`
- state 카운터(fail / parse-fail), stop-loop 가드, pipefail 가드
- baseline 커밋 트리거, 리뷰 입력 조립
- read-only `codex exec`, python JSON 파싱, verdict 분기, escalation 임계

## 들어오지 않을 것 (consumer delta)

trigger case-list / skip paths / Codex prompt / target 경로 / build·test·run 명령은 **주입점**으로
남긴다(공통부에 하드코딩하지 않음). → [`../../docs/consumer-contract.md`](../../docs/consumer-contract.md)

> Windows 환경에서는 Git Bash shim(`git-bash.cmd`)으로 WSL bash 충돌을 회피한다.
> 저작 시 주의사항은 [`../../skills/codex-gate-authoring/SKILL.md`](../../skills/codex-gate-authoring/SKILL.md) 참고.

## 다음 단계

H2에서 공통 골격 prototype을 만들고 **script-agent에만** 시범 적용한다.
→ [`../../docs/milestones.md`](../../docs/milestones.md)
