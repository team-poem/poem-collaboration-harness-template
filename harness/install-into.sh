#!/bin/sh
# 기존 리포에 협업 하네스를 넣는다. 사용: sh harness/install-into.sh <대상 리포 경로> [프로젝트명] [핸들]
# 템플릿 파일을 복사하고 대상에서 init.sh 를 돌린다. 대상에 이미 있는 파일은 덮어쓰지 않는다 (AGENTS.md 는 AGENTS.collab.md 로).
set -e
SRC="$(cd "$(dirname "$0")/.." && pwd -P)"; T="${1:-}"; [ -n "$T" ] || { echo "사용: install-into.sh <대상 리포 경로> [이름] [핸들]"; exit 1; }
T="$(cd "$T" && pwd -P)"; git -C "$T" rev-parse --show-toplevel >/dev/null 2>&1 || { echo "$T 는 git 리포가 아닙니다"; exit 1; }
name="${2:-$(basename "$T")}"; handle="${3:-}"
copy_dir() { [ -e "$T/$1" ] && { echo "  건너뜀 (있음): $1"; return; }; mkdir -p "$(dirname "$T/$1")"; cp -R "$SRC/$1" "$T/$1"; echo "  복사: $1"; }
for d in collab harness scripts tests .agents .githooks .codex .github docs; do copy_dir "$d"; done
mkdir -p "$T/.claude"; [ -e "$T/.claude/settings.json" ] && echo "  건너뜀 (있음): .claude/settings.json — hooks 를 harness/hooks 로 합치세요" || { cp "$SRC/.claude/settings.json" "$T/.claude/settings.json"; echo "  복사: .claude/settings.json"; }
[ -e "$T/.claude/skills" ] || ln -s ../.agents/skills "$T/.claude/skills"
if [ -e "$T/AGENTS.md" ]; then cp "$SRC/AGENTS.md" "$T/AGENTS.collab.md"; echo "  AGENTS.md 가 이미 있어 AGENTS.collab.md 로 두었습니다 → App facts 절과 협업 규칙을 기존 AGENTS.md 에 합치고 지우세요"
else cp "$SRC/AGENTS.md" "$T/AGENTS.md"; [ -e "$T/CLAUDE.md" ] || ln -s AGENTS.md "$T/CLAUDE.md"; echo "  복사: AGENTS.md (+ CLAUDE.md 심링크)"; fi
[ -e "$T/CONTRIBUTING.md" ] || { cp "$SRC/CONTRIBUTING.md" "$T/CONTRIBUTING.md"; echo "  복사: CONTRIBUTING.md"; }
grep -qx '.claude/cache/' "$T/.gitignore" 2>/dev/null || printf '\n.claude/cache/\n.claude/settings.local.json\n' >> "$T/.gitignore"
rm -rf "$T/harness/sobaya.lock"
echo "→ init.sh"; (cd "$T" && sh harness/init.sh "$name" "$handle")
