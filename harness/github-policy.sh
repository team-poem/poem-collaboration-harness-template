#!/bin/sh
# GitHub 리포 정책. 첫 push 뒤 한 번 (온보딩이 부른다). 멱등. gh 로그인 필요.
#   squash 머지만 · 머지 시 브랜치 삭제 · main 보호(PR 필수, "훅·루프 검증" 통과 필수, force push·삭제 금지, actions 봇 우회)
# private + 조직 Free 플랜이면 보호는 실패한다 (git 훅이 대신 막는다). public 이면 걸린다.
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"; cd "$ROOT"
command -v gh >/dev/null 2>&1 || { echo "gh 가 없습니다. GitHub Settings 에서 직접: squash only · delete branch on merge · main 보호"; exit 1; }
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || { echo "origin 이 GitHub 리포가 아니거나 gh 로그인이 안 돼 있습니다"; exit 1; }
main="$(sed -n 's/^PROTECTED_BRANCHES="\([^ "]*\).*/\1/p' harness/config.sh)"; main="${main:-main}"
if gh api -X PATCH "repos/$repo" -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false -F delete_branch_on_merge=true \
     -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY >/dev/null 2>&1; then echo "✓ $repo: squash 머지만, 머지 시 브랜치 삭제"
else echo "! 머지 정책 설정 실패 — Settings > General 에서 squash only + delete branch on merge"; fi
prot='{"required_status_checks":{"strict":true,"contexts":["훅·루프 검증"]},"enforce_admins":false,"required_pull_request_reviews":{"required_approving_review_count":0},"restrictions":null,"allow_force_pushes":false,"allow_deletions":false}'
if printf '%s' "$prot" | gh api -X PUT "repos/$repo/branches/$main/protection" --input - >/dev/null 2>&1; then echo "✓ $main 보호: PR 필수, CI 통과 필수, force push·삭제 금지"
  printf '{"required_approving_review_count":0,"bypass_pull_request_allowances":{"apps":["github-actions"]}}' | gh api -X PATCH "repos/$repo/branches/$main/protection/required_pull_request_reviews" --input - >/dev/null 2>&1 || true
else vis="$(gh repo view --json visibility --jq .visibility 2>/dev/null)"; echo "! $main 보호 설정 실패 (리포 $vis · private + Free 플랜이면 불가). git 훅이 대신 막습니다. public 으로 바꾸면 다시 실행: sh harness/github-policy.sh"; fi
