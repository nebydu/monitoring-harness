#!/usr/bin/env bash
# Claude Code 상태 표시줄(2줄): 모델, 세션 시간, 컨텍스트, 5시간 사용량을 표시한다.
# jq가 없는 환경에서도 동작하도록 stdin JSON 파싱은 Python으로 처리한다.
python -c '
import json
import os
import sys
import time

# Windows 콘솔 기본 인코딩으로 인한 박스 문자 깨짐을 줄인다.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

try:
    payload = sys.stdin.read()
    data = json.loads(payload)
except Exception:
    sys.exit(0)

RESET = "\033[0m"
CYAN = "\033[1;36m"
GREEN = "\033[1;32m"
YELLOW = "\033[1;33m"
ORANGE = "\033[38;5;208m"
RED = "\033[1;31m"
GRAY = "\033[38;5;248m"
FAINT = "\033[38;5;240m"
WHITE = "\033[1;37m"


def sep():
    return FAINT + "  ·  " + RESET


def color_for_usage(percent, warning_color=ORANGE):
    if percent >= 85:
        return RED
    if percent >= 60:
        return warning_color
    return GREEN


model = data.get("model") or {}
model_name = model.get("display_name") or model.get("id") or "unknown"

context_window = data.get("context_window") or {}
window_size = context_window.get("context_window_size") or 0
used_pct = context_window.get("used_percentage")
remaining_pct = context_window.get("remaining_percentage")
window_label = ("%dk" % round(window_size / 1000)) if window_size else "--k"

if isinstance(used_pct, (int, float)) and isinstance(remaining_pct, (int, float)):
    used_rounded = round(used_pct)
    remaining_rounded = round(remaining_pct)
    filled = max(0, min(10, int(used_pct / 10)))
    bar = "█" * filled + "░" * (10 - filled)
    bar_color = color_for_usage(used_pct)
    context_block = (
        GRAY + "ctx " + RESET
        + bar_color + bar + RESET
        + GRAY + " " + RESET
        + WHITE + str(used_rounded) + "%" + RESET
        + GRAY + " used  " + RESET
        + GREEN + str(remaining_rounded) + "%" + RESET
        + GRAY + " left" + RESET
        + GRAY + "  [" + window_label + "]" + RESET
    )
else:
    context_block = (
        GRAY + "ctx ░░░░░░░░░░ --% used  --% left  [" + window_label + "]" + RESET
    )

# 세션 ID별 시작 시각을 기록해 Claude Code statusline 호출 사이의 경과 시간을 계산한다.
session_id = data.get("session_id") or "default"
stamp_file = os.path.join(
    os.path.expanduser("~"), ".claude", ".session-start-" + session_id[:16]
)
now_ts = time.time()

if not os.path.exists(stamp_file):
    try:
        os.makedirs(os.path.dirname(stamp_file), exist_ok=True)
        with open(stamp_file, "w", encoding="utf-8") as stamp:
            stamp.write(str(now_ts))
        start_ts = now_ts
    except Exception:
        start_ts = now_ts
else:
    try:
        with open(stamp_file, encoding="utf-8") as stamp:
            start_ts = float(stamp.read().strip())
    except Exception:
        start_ts = now_ts

elapsed_sec = max(0, int(now_ts - start_ts))
hours = elapsed_sec // 3600
minutes = (elapsed_sec % 3600) // 60
seconds = elapsed_sec % 60
if hours > 0:
    duration = "%dh%02dm" % (hours, minutes)
else:
    duration = "%dm%02ds" % (minutes, seconds)

rate_limits = data.get("rate_limits") or {}
five_hour = rate_limits.get("five_hour") or {}
rate_pct = five_hour.get("used_percentage")
rate_reset = five_hour.get("resets_at")

if isinstance(rate_pct, (int, float)):
    rate_color = color_for_usage(rate_pct, warning_color=ORANGE)
    rate_block = (
        GRAY + "5h " + RESET
        + rate_color + str(round(rate_pct)) + "%" + RESET
        + GRAY + " used" + RESET
    )

    if isinstance(rate_reset, (int, float)):
        seconds_left = int(rate_reset - now_ts)
        if seconds_left > 0:
            reset_minutes = seconds_left // 60
            reset_hours = reset_minutes // 60
            reset_remaining_minutes = reset_minutes % 60
            if reset_hours > 0:
                reset_label = "%dh%02dm" % (reset_hours, reset_remaining_minutes)
            else:
                reset_label = "%dm" % reset_remaining_minutes
            rate_block += GRAY + "  resets in " + RESET + CYAN + reset_label + RESET
        else:
            rate_block += GRAY + "  resetting" + RESET
else:
    rate_block = GRAY + "5h --" + RESET

line1 = CYAN + "✦ " + model_name + RESET + sep() + GRAY + "⏱ " + RESET + WHITE + duration + RESET
line2 = context_block + sep() + rate_block

sys.stdout.write(line1 + "\n" + line2)
'
