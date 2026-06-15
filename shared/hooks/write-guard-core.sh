#!/usr/bin/env bash
# write-guard-core.sh — PreToolUse 쓰기 가드 공통 골격 (Git Bash 전용)
#
# 이 파일은 consumer repo들이 공유하는 "동일 실행 로직"만 추출한 공통 골격이다. codex-gate와
# 같은 패턴(plugin 골격 + git-bash.cmd shim + convention profile)을 따른다. plugin은 도메인
# 결정을 하지 않으며, repo별 추가 차단 경로만 아래 주입점으로 받는다.
#
# 목적: 자기 repo의 docs·형제 repo·ground truth(monitoring-meta)로의 Write/Edit/NotebookEdit를
#   호출 "전"에 차단한다(polyrepo 경계 보호 — 모든 sub-agent 공통).
#
# 차단 메커니즘 = exit 2 (정본). PreToolUse에서 exit 2 = 툴 호출 차단 + stderr 사유를 모델에
#   환류. JSON permissionDecision:deny는 Edit/Write에서 무시되는 알려진 버그가 있어 쓰지 않는다.
#
# 차단 규칙 (정규화된 target T 기준, 우선순위 순):
#   1) T가 REPO_ROOT/.claude/ 하위        → 허용 (자동화 설정은 사람이 관리 가능해야 함 — 기존 결정)
#   2) T가 REPO_ROOT/docs/ 하위           → 차단 (자기 문서)
#   3) T가 PARENT 하위이며 REPO_ROOT 밖   → 차단 (형제 repo 전체 = meta·hub·script-agent… + 형제 .claude)
#   4) T가 WRITE_GUARD_BLOCK_PATHS 하위    → 차단 (repo별 추가 차단; add-only)
#   5) 그 외                               → 허용 (자기 repo 코드, PARENT 밖 경로는 이 가드 범위 외)
#   → 자기 repo는 docs/ 외 전부 허용. profile은 "조이기"만 가능(유도 규칙을 약화할 수 없음).
#
# ── 주입점 (선택, profile이 제공) ──────────────────────────────────────────
#   WRITE_GUARD_BLOCK_PATHS  (배열, 선택)  추가 차단 루트. 상대=repo 기준, 절대 모두 가능.
#                                          지정 루트의 subtree 전체를 차단한다(glob 아님 — 경로 prefix).
#
# 경로 정규화는 python realpath 기반으로 일원화한다(Windows/MSYS의 ..·symlink·junction·대소문자
# 함정 회피). jq 미설치 환경이라 JSON 파싱도 python으로 한다.
set -uo pipefail   # -e 미사용: python 종료코드를 그대로 전파(차단=2 / 허용=0)

INPUT="$(cat)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# stdin(PreToolUse 페이로드 JSON)은 고정해 python으로 넘기고, REPO_ROOT·추가 차단 경로는 argv로 전달.
printf '%s' "$INPUT" | python -c '
import sys, json, os
# Windows python 기본 stderr(cp949)에서 한글/em-dash 크래시 방지
sys.stderr.reconfigure(encoding="utf-8")

def norm(p):
    # realpath: ..·symlink·junction 해소 / normcase: Windows 대소문자·슬래시 정규화
    return os.path.normcase(os.path.realpath(p))

def under(child, parent):
    return child == parent or child.startswith(parent + os.sep)

repo_arg  = sys.argv[1]
extra_raw = [a for a in sys.argv[2:] if a]   # WRITE_GUARD_BLOCK_PATHS (빈 항목 제거)

repo       = norm(repo_arg)
parent     = os.path.dirname(repo)
own_claude = norm(os.path.join(repo_arg, ".claude"))
own_docs   = norm(os.path.join(repo_arg, "docs"))
extra      = [norm(p if os.path.isabs(p) else os.path.join(repo_arg, p)) for p in extra_raw]

try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)   # 파싱 실패 = 판단하지 않음(차단 안 함)

ti = data.get("tool_input") or {}
fp = ti.get("file_path") or ti.get("notebook_path") or ti.get("path") or ""
if not fp:
    sys.exit(0)

fp_abs = fp if os.path.isabs(fp) else os.path.join(repo_arg, fp)   # 상대경로는 repo 기준
target = norm(fp_abs)

def block(reason):
    sys.stderr.write(
        "[write-guard] 쓰기 금지 경로 — " + reason + ": " + fp +
        "\n(자기 repo 코드·.claude는 허용. ground truth/문서/형제 repo는 보호된다.)\n")
    sys.exit(2)

if under(target, own_claude):
    sys.exit(0)                                    # 1) 자기 .claude 항상 허용
if under(target, own_docs):
    block("자기 repo 문서(docs/) 보호")            # 2) 자기 docs
if under(target, parent) and not under(target, repo):
    block("형제 repo/ground truth 교차쓰기 차단")  # 3) 형제 전체
for b in extra:
    if under(target, b):
        block("profile 지정 차단 경로")            # 4) repo별 추가 차단
sys.exit(0)                                        # 5) 그 외 허용
' "$REPO_ROOT" "${WRITE_GUARD_BLOCK_PATHS[@]:-}"
exit $?
