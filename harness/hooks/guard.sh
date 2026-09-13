#!/bin/sh
# PreToolUse(Write|Edit|MultiEdit|NotebookEdit|Bash): 쓰기 규칙 검사. 판정은 lib.sh 한 곳(check_write / check_command).
# exit 2 = 차단 (stderr 가 에이전트에게 전달). 리포 밖 파일은 관여하지 않는다.
. "$(dirname "$0")/lib.sh"
hook_read_input; hook_reroot
if [ "$(hook_tool)" = "Bash" ]; then
  cmd="$(hook_command)"; [ -n "$cmd" ] || exit 0
  check_command "$cmd" && exit 0
else
  path="$(hook_file_path)" || exit 0
  check_write "$path" && exit 0
fi
printf '%s\n' "$REASON" >&2
exit 2
