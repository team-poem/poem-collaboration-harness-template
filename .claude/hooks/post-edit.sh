#!/bin/sh
# PostToolUse(Write|Edit|MultiEdit|NotebookEdit|Bash): 차단하지 않고 알린다.
# 1) 방금 만진 파일을 동료도 지금 만지는 중이면 알림 (파일마다 한 번)
# 2) N회 수정마다 / 일정 시간마다 pulse: 내 작업 트리 스냅샷 push, 원격 fetch, 새 겹침·새 이벤트·main 변경(자동 rebase)
. "$(dirname "$0")/lib.sh"
hook_read_input; hook_reroot
branch="$(current_branch)" || exit 0
is_protected_branch "$branch" && exit 0
[ -f "$ROOT/$(claim_path_for "$branch")" ] || exit 0
msgs=""
path="$(hook_file_path 2>/dev/null)" || path=""
if [ -n "$path" ] && ! in_collab_meta "$path"; then
  who="$(touching_now "$path")"
  if [ -n "$who" ]; then warned="$CACHE/warned"; touch "$warned"
    if ! grep -qxF "$path" "$warned"; then echo "$path" >> "$warned"
      msgs="$msgs- 겹침: $path 를 $(printf '%s' "$who" | awk -F"$TAB" '{printf "@%s(작업 트리 %s초 전) ", $1, $2}')도 지금 만지는 중입니다. 작게 커밋하고 자주 pulse 하세요. 같은 부분을 고치는 것 같으면 사용자에게 알리세요.
"; fi
  fi
fi
cnt="$CACHE/edits"; n=$(( $(cat "$cnt" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$cnt"
last=$(cat "$CACHE/pulse.at" 2>/dev/null || echo 0); age=$(( $(now_epoch) - last ))
if [ $(( n % PULSE_EVERY_EDITS )) -eq 0 ] || [ "$age" -ge "$PULSE_MAX_AGE_SEC" ]; then
  p="$(sh "$ROOT/scripts/collab.sh" pulse 2>/dev/null)"; [ -n "$p" ] && msgs="$msgs$p
"
fi
[ -z "$msgs" ] && exit 0
if command -v jq >/dev/null 2>&1; then printf '[협업 알림]\n%s' "$msgs" | jq -Rs '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:.}}'
else printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$(printf '[협업 알림] %s' "$msgs" | sed 's/"/\\"/g' | tr '\n' ' ')"; fi
exit 0
