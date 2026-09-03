#!/bin/sh
# 템플릿에서 새 프로젝트를 만든 뒤 한 번 실행. 플레이스홀더 치환, 핸들·rerere 설정, 실행 권한. 멱등.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"; cd "$ROOT"
name="${1:-}"; owner="${2:-}"
[ -z "$name" ] && { printf '프로젝트 이름: '; read -r name; }
[ -z "$owner" ] && { owner="$(git config user.name 2>/dev/null | tr ' -' '__' || true)"; printf '내 핸들 (공백·하이픈 없이) [%s]: ' "$owner"; read -r o; [ -n "$o" ] && owner="$o"; }
owner="$(printf '%s' "$owner" | tr ' -' '__')"; date="$(date +%Y-%m-%d)"
grep -rl --exclude-dir=.git --exclude-dir=node_modules -e '{{PROJECT_NAME}}' -e '{{OWNER}}' -e '{{DATE}}' . 2>/dev/null \
  | grep -v '^./collab/templates/' | grep -v '^./harness/init.sh$' | while read -r f; do
  sed -i.bak -e "s/{{PROJECT_NAME}}/$name/g" -e "s/{{OWNER}}/$owner/g" -e "s/{{DATE}}/$date/g" "$f" && rm -f "$f.bak"; done
chmod +x .claude/hooks/*.sh scripts/*.sh tests/*.sh 2>/dev/null || true
[ -e AGENTS.md ] || ln -s CLAUDE.md AGENTS.md
git config collab.me "$owner"; git config rerere.enabled true
cat <<MSG
초기화 완료: $name · 나: @$owner
팀원 각자 클론 후:  git config collab.me <핸들> && git config rerere.enabled true
다음:
  1. harness/config.sh 의 HOTSPOTS 를 이 프로젝트의 허브 파일로 맞춘다 (스키마, lockfile, 배럴, i18n …)
  2. git add -A && git commit -m "chore: init collaboration harness" && git push
  3. claude 를 켜면 협업 현황이 먼저 뜬다. 첫 작업은 Skill(start-work)
MSG
