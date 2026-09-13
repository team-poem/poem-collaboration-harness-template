#!/bin/sh
# Stop: 코드 변경이 있는데 오늘 내 저널이 없으면 한 번만 멈춰 세운다 (handoff 유도). stop_hook_active 면 통과 — 무한 루프 방지.
. "$(dirname "$0")/lib.sh"
hook_read_input; hook_reroot
[ "$(hook_flag stop_hook_active)" = "true" ] && exit 0
branch="$(current_branch)" || exit 0; is_protected_branch "$branch" && exit 0
[ -f "$ROOT/$(claim_path_for "$branch")" ] || exit 0
[ -z "$(my_files | head -n1)" ] && exit 0
ls "$ROOT/$JOURNAL_DIR"/"$(today)"-"$(me)"-*.md >/dev/null 2>&1 && exit 0
r="이 세션에 코드 변경이 있는데 오늘 내 저널($JOURNAL_DIR/$(today)-$(me)-<slug>.md)이 없습니다. handoff 스킬 로 이벤트와 남은 것을 남기고 push 한 뒤 끝내세요. 사용자가 저널 없이 끝내라고 명시했으면 그대로 끝내도 됩니다."
if command -v jq >/dev/null 2>&1; then jq -nc --arg r "$r" '{decision:"block",reason:$r}'; else printf '{"decision":"block","reason":"%s"}' "$r"; fi
exit 0
