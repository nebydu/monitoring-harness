---
name: codex-gate-authoring
description: monitoring repos의 codex-gate Stop hook을 작성·수정할 때 참고하는 레시피. set -euo pipefail 빈 입력, schema required/400, SIGPIPE, CRLF, Git Bash vs WSL, stdout JSON 인코딩 등 알려진 함정을 다룬다.
---

# codex-gate-authoring

monitoring 계열 repo(`hub`/`script-agent`/`monitoring-meta`)의 `codex-gate.sh`(Codex gate Stop hook)를
**작성하거나 수정할 때** 참고하는 짧은 레시피다.

> **H0 주의**: 이 skill은 문서일 뿐, **실제 hook 구현 파일을 만들지 않는다.**
> 또한 어떤 작업에서도 **consumer repo의 파일을 직접 수정하지 않는다**(아래 마지막 절 참고).

## 언제 이 skill을 쓰는가

- codex-gate Stop hook 골격을 새로 짜거나 손볼 때
- hook이 의도와 다르게 block/escalate 되거나, JSON 출력이 깨질 때
- Windows(Git Bash) 환경에서 hook이 동작하지 않을 때

## hook 작성 체크리스트

- [ ] `stop_hook_active`를 먼저 확인해 **stop 루프**를 차단한다(무한 재발화 방지).
- [ ] 트리거/스킵 경로는 **하드코딩하지 말고 주입점**으로 둔다(도메인 delta는 consumer 소유).
- [ ] Codex는 항상 `--sandbox read-only`로 호출한다(리뷰가 파일을 바꾸지 않게).
- [ ] verdict 분기: pass → reset+emit+exit0, fail → 카운터++ 후 임계 초과 시 escalate.
- [ ] fail / parse-fail 카운터는 **state 파일**에 영속화하고, 성공 시 reset한다.
- [ ] escalation 임계를 두어 **영구 block 루프**를 막는다(force-pass + escalation log).
- [ ] force-pass/escalate는 로그에만 남기지 말고 `systemMessage`로도 노출한다.
- [ ] 로그는 `log_line`으로 한 줄 TSV(`timestamp | verdict | crit | viol | files`)로 남긴다.

## 함정 (반드시 확인)

### 1. `set -euo pipefail` + grep 빈 입력
`grep`이 매치 0건이면 exit code 1 → `set -e`에서 스크립트가 죽는다.
빈 매치를 정상 처리하려면 `grep ... || true` 또는 `if grep -q ...; then` 패턴을 쓴다.

### 2. schema required / 400
`codex-schema.json`의 `required`(`verdict`/`critical_issues`/`spec_violations`/`summary`)를
모두 충족하지 못하거나 `additionalProperties: false`를 위반하면 응답이 거부될 수 있다.
스키마와 프롬프트의 출력 계약을 일치시킨다.

### 3. SIGPIPE
파이프 뒤 소비자가 먼저 종료하면 생산자가 SIGPIPE로 죽어 `pipefail`에서 실패로 잡힌다.
긴 출력을 `head` 등으로 자를 때 주의하고, 필요하면 임시 파일을 경유한다.

### 4. CRLF
Windows 체크아웃에서 `.sh`가 CRLF가 되면 `#!/usr/bin/env bash`가 깨진다.
hook 스크립트는 LF로 유지한다(`.gitattributes`로 `*.sh text eol=lf` 권장).

### 5. Windows Git Bash vs WSL bash
Windows PATH에 WSL `bash.exe`가 먼저 잡히면 Git Bash 스크립트가 실패한다.
`git-bash.cmd` shim으로 `%ProgramFiles%\Git\bin\bash.exe`를 명시적으로 호출한다.

### 6. stdout JSON 인코딩
Windows 콘솔 기본 코드페이지(cp949)로 JSON을 내보내면 한글/UTF-8이 깨진다.
JSON 출력은 python으로 **UTF-8 인코딩**해서 내보낸다(`emit_system_message` 패턴).

### 7. force-pass/escalate 노출
연속 fail/parse-fail 임계 초과로 force-pass할 때는 escalation log 기록만으로 끝내지 않는다.
`emit_system_message`로 "게이트 강제 통과 — 사람 확인 필요"를 함께 출력해, 사용자가 즉시 볼 수 있게 한다.

## dry-run 예시

실제 block 없이 골격을 점검하는 방법(개념 예시):

```bash
# 1) 트리거 판정만 확인 (Codex 호출 없이 어떤 파일이 발동시키는지)
DRY_RUN=1 bash .claude/hooks/codex-gate.sh < sample-stop-input.json

# 2) JSON 파싱부만 점검 (저장된 마지막 응답으로 verdict 추출 확인)
python - <<'PY'
import json
d = json.load(open(".claude/.codex-last-message.json", encoding="utf-8"))
print(d.get("verdict"), len(d.get("critical_issues", [])), len(d.get("spec_violations", [])))
PY
```

> `DRY_RUN`은 골격이 지원할 때만 동작한다. 골격을 새로 짤 때 **Codex exec를 건너뛰는 dry-run 경로**를
> 넣어두면 디버깅이 쉽다.

## consumer repo 수정 금지 원칙

- 이 skill을 따르더라도 **consumer repo(`hub`/`script-agent`/`monitoring-meta`)의 파일을 직접 수정하지 않는다.**
- 공통 골격은 plugin/shared에서 작성하고, consumer는 **주입점(profile)**으로만 도메인 값을 제공한다.
- consumer 적용은 milestone(H2~)에서 **사람 확인 게이트**를 거쳐 진행하며, 항상 git 원복 가능해야 한다.
