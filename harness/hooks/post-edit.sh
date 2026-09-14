#!/bin/sh
# PostToolUse(Write|Edit|MultiEdit|NotebookEdit|Bash): 차단하지 않고 알린다.
# 1) 방금 만진 파일의 동료·브랜치·편집 상태가 달라지면 알림
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
  warned="$(branch_cache warned)"; touch "$warned"
  # 나이만 바뀐 것은 같은 상태다. 다른 파일의 상태는 보존한다.
  awk -F"$TAB" -v p="$path" '$1 != p' "$warned" > "$warned.next"
  if [ -n "$who" ]; then
    msgs="$(printf '%s\n' "$who" | while IFS="$TAB" read -r o slug age kind; do
      id="$path$TAB$o$TAB$slug$TAB$kind"; printf '%s\n' "$id" >> "$warned.next"
      grep -qxF "$id" "$warned" && continue
      case "$kind" in
        (editing) echo "- 겹침: $path 를 @$o($slug, 작업 트리 ${age}초 전)도 편집 중입니다. 같은 부분을 고치는 것 같으면 사용자에게 알리세요." ;;
        (committed) echo "- 겹침: $path 는 @$o($slug) 브랜치에 커밋됨(미머지). 공유 파일이면 작은 선행 PR 을 제안하세요." ;;
      esac
    done)"
    [ -z "$msgs" ] || msgs="$msgs
"
  fi
  mv "$warned.next" "$warned"
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
