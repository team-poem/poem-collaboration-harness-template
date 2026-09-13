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
chmod +x harness/hooks/*.sh harness/*.sh .githooks/* scripts/*.sh tests/*.sh 2>/dev/null || true
git config core.hooksPath .githooks   # 어느 도구로 커밋하든 같은 규칙
[ -e CLAUDE.md ] || ln -s AGENTS.md CLAUDE.md
git config collab.me "$owner"; git config rerere.enabled true
# GitHub 머지 정책: squash 만 + 머지 시 브랜치 삭제 (하네스의 머지 감지·prune 이 이 전제로 동작). 실패해도 진행
if command -v gh >/dev/null 2>&1 && repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" && [ -n "$repo" ]; then
  gh api -X PATCH "repos/$repo" -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false -F delete_branch_on_merge=true \
    -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY >/dev/null 2>&1 && echo "✓ GitHub: squash 머지만, 머지 시 브랜치 삭제" || echo "! GitHub 머지 정책 설정 실패 — 리포 Settings 에서 squash only + delete branch on merge 를 켜세요"
fi
cat <<MSG
초기화 완료: $name · 나: @$owner
팀원 각자 클론 후:  git config collab.me <핸들> && git config rerere.enabled true
다음:
  1. harness/config.sh 의 HOTSPOTS 를 이 프로젝트의 허브 파일로 맞춘다 (스키마, lockfile, 배럴, i18n …)
     AGENTS.md 의 '- Test:' 에 실제 테스트 명령을 적는다 (sobaya 를 쓰면 attach-sobaya.sh 가 물어본다)
  2. git add -A && git commit -m "chore: init collaboration harness" && git push
  3. claude 를 켜면 협업 현황이 먼저 뜬다. 첫 작업은 Skill(start-work)
MSG
