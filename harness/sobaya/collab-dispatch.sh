#!/bin/sh
# sobaya 워크스페이스 루트에서 Claude 세션을 열 때 쓰는 어댑터.
# 루트에는 collab 이 없으므로, 훅 입력을 보고 대상 앱(apps/<x>, collab/ 가 있는 것)을 찾아
# 그 앱의 .claude/hooks/<같은 훅>.sh 를 CLAUDE_PROJECT_DIR=<앱> 으로 실행한다. 앱을 못 찾으면 통과.
# attach-sobaya.sh 가 <sobaya>/.claude/hooks/ 에 복사하고 settings.local.json 에 배선한다.
WS="${CLAUDE_PROJECT_DIR:-$(pwd -P)}"
INPUT="$(cat)"; command -v jq >/dev/null 2>&1 || exit 0
jget() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }
event="$(jget .hook_event_name)"; tool="$(jget .tool_name)"; cwd="$(jget .cwd)"
norm() { (cd "$1" 2>/dev/null && pwd -P); }
app_of_dir() { d="$1"; while [ -n "$d" ] && [ "$d" != "/" ]; do [ -d "$d/collab" ] && [ -e "$d/.git" ] && { printf '%s' "$d"; return 0; }; d="$(dirname "$d")"; done; return 1; }
apps() { for a in "$WS"/apps/*/; do [ -d "${a}collab" ] && [ -e "${a}.git" ] && printf '%s\n' "${a%/}"; done; }
run_in() { # $1=app $2=hook 이름
  h="$1/.claude/hooks/$2.sh"; [ -f "$h" ] || return 0
  printf '%s' "$INPUT" | CLAUDE_PROJECT_DIR="$1" sh "$h"
}
case "$event" in
  SessionStart)
    n=0; for a in $(apps); do n=$((n+1)); echo "# ── 앱: ${a#"$WS"/} ──"; run_in "$a" session-start; echo; done
    [ $n -eq 0 ] && echo "# 협업 하네스: apps/ 아래에 collab/ 를 가진 앱이 없습니다."; exit 0 ;;
  PreToolUse|PostToolUse)
    app=""
    if [ "$tool" = "Bash" ]; then
      cmd="$(jget .tool_input.command)"
      for t in $(printf '%s' "$cmd" | tr ' ;|&()<>"'"'"'`' '\n' | grep -E '^(\./)?apps/[^/]+/' | sed -E 's#^(\./)?(apps/[^/]+)/.*#\2#' | sort -u | head -n1); do app="$WS/$t"; done
      [ -z "$app" ] && [ -n "$cwd" ] && app="$(app_of_dir "$(norm "$cwd")")"
    else
      fp="$(jget .tool_input.file_path)"; [ -n "$fp" ] || fp="$(jget .tool_input.notebook_path)"
      [ -n "$fp" ] && app="$(app_of_dir "$(norm "$(dirname "$fp")")")"
    fi
    [ -n "$app" ] && [ -d "$app/collab" ] || exit 0
    if [ "$event" = PreToolUse ]; then run_in "$app" guard; exit $?; else run_in "$app" post-edit; exit 0; fi ;;
  Stop)
    for a in $(apps); do out="$(run_in "$a" stop)"; [ -n "$out" ] && { printf '%s\n' "$out"; exit 0; }; done; exit 0 ;;
  *) exit 0 ;;
esac
