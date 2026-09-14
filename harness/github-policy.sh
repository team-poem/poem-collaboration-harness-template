#!/bin/sh
# GitHub 리포 정책. 첫 push 뒤 한 번 (온보딩이 부른다). 멱등. gh 로그인 필요.
#   squash 머지만 · 머지 시 브랜치 삭제 · main 보호(PR 필수, "훅·루프 검증" 통과 필수, force push·삭제 금지, actions 봇 우회)
# private + 조직 Free 플랜이면 보호는 실패한다 (git 훅이 대신 막는다). public 이면 걸린다.
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"; cd "$ROOT"
command -v gh >/dev/null 2>&1 || { echo "gh 가 없습니다. GitHub Settings 에서 직접: squash only · delete branch on merge · main 보호"; exit 1; }
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || { echo "origin 이 GitHub 리포가 아니거나 gh 로그인이 안 돼 있습니다"; exit 1; }
main="$(sed -n 's/^PROTECTED_BRANCHES="\([^ "]*\).*/\1/p' harness/config.sh)"; main="${main:-main}"
if gh api -X PATCH "repos/$repo" -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false -F delete_branch_on_merge=true -F allow_auto_merge=true \
     -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY >/dev/null 2>&1; then echo "✓ $repo: squash 머지만, 머지 시 브랜치 삭제, auto-merge 허용"
else echo "! 머지 정책 설정 실패 — Settings > General 에서 squash only + delete branch on merge + allow auto-merge"; fi
# main 보호 룰셋
#   - PR 필수, 다른 멤버 1명 이상 승인, 새 커밋이 오면 이전 승인 무효, 리뷰 대화 전부 해결
#   - CI 두 job 통과 필수, 브랜치가 main 최신이어야 함(strict)
#   - 관리자도 예외 없음. force push·삭제 금지. 선형 히스토리(squash)
prot='{"required_status_checks":{"strict":true,"contexts":["훅·루프 검증","협업 규칙 검사"]},"enforce_admins":true,"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_code_owner_reviews":false},"restrictions":null,"allow_force_pushes":false,"allow_deletions":false,"required_linear_history":true,"required_conversation_resolution":true}'
if printf '%s' "$prot" | gh api -X PUT "repos/$repo/branches/$main/protection" --input - >/dev/null 2>&1; then
  echo "✓ $main 보호: PR 필수 · 승인 1명 이상(새 커밋이면 재승인) · 대화 해결 · CI 통과 · 관리자 포함 · force push·삭제 금지"
  echo "  주의: 관리자도 main 에 직접 push 못 한다. CI 가 여는 claim 정리 PR 도 사람이 승인해야 머지된다."
else vis="$(gh repo view --json visibility --jq .visibility 2>/dev/null)"; echo "! $main 보호 설정 실패 (리포 $vis · private + Free 플랜이면 불가). git 훅이 대신 막습니다. public 으로 바꾸면 다시 실행: sh harness/github-policy.sh"; fi
