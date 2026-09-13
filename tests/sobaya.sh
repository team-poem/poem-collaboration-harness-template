#!/bin/sh
# sobaya 결합 검증. 가짜 sobaya 워크스페이스(tdd-set/bin/step.sh 만 있는)를 만들고 그 안 apps/x 에 하네스를 둔다.
# 실제 sobaya 는 부르지 않는다 — 어댑터 라우팅, 경로 판정, merge 모드, plan 보관 규칙만 본다.
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd -P)"
R="$(mktemp -d)"; R="$(cd "$R" && pwd -P)"; trap 'rm -rf "$R"' EXIT
pass=0; fail=0; check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; fi; }
today="$(date +%Y-%m-%d)"
# 가짜 sobaya 루트 (git 리포)
WS="$R/sobaya"; mkdir -p "$WS/tdd-set/bin" "$WS/apps" && cd "$WS" && git init -q -b main && git config user.email s@s && git config user.name s
mkdir -p scripts; for f in tdd-set/bin/step.sh tdd-set/bin/install.sh scripts/setup.sh; do printf '#!/bin/sh\necho "fake $0 $*"\nexit 0\n' > "$f"; chmod +x "$f"; done
echo '# Sobaya' > AGENTS.md; git add -A && git commit -qm init
# bare 원격 + 앱
git init -q --bare "$R/origin.git" && git -C "$R/origin.git" symbolic-ref HEAD refs/heads/main
A="$WS/apps/shop"; git clone -q "$R/origin.git" "$A" 2>/dev/null; cd "$A" && git switch -qc main 2>/dev/null && git config user.email a@a && git config user.name a && git config collab.me solp
cp -R "$SRC/.claude" "$SRC/harness" "$SRC/collab" "$SRC/scripts" "$SRC/.gitignore" "$SRC/AGENTS.md" . && rm -rf .claude/cache && ln -s AGENTS.md CLAUDE.md
mkdir -p src && echo a > src/a.ts && echo '{}' > package.json && git add -A && git commit -qm init && git push -q origin main
git switch -qc feat/x && mkdir -p collab/active/feat--x && printf -- '---\nbranch: feat/x\nowner: solp\nstarted: %s\nstatus: active\ngoal: x\n---\n' "$today" > collab/active/feat--x/claim.md && git add -A && git commit -qm claim && git push -q -u origin HEAD
export CLAUDE_PROJECT_DIR="$A"

echo "# 앱 안에서: 경로가 훅 cwd 기준으로 해석되는가"
rc="$(printf '{"tool_name":"Bash","tool_input":{"command":"echo x > src/new.ts"},"cwd":"%s"}' "$A" | sh .claude/hooks/guard.sh 2>/dev/null; echo $?)"
check "claim 있는 브랜치: 상대경로 쓰기 통과"  "[ \"\$rc\" = 0 ]"
git switch -q main
rc="$(printf '{"tool_name":"Bash","tool_input":{"command":"echo x > src/new.ts"},"cwd":"%s"}' "$A" | sh .claude/hooks/guard.sh 2>/dev/null; echo $?)"
check "main: 상대경로 쓰기 차단"                "[ \"\$rc\" = 2 ]"

echo "# sobaya 루트에서 세션을 열었을 때 (어댑터)"
D="$WS/.claude/hooks/collab-dispatch.sh"; mkdir -p "$WS/.claude/hooks" && cp "$SRC/harness/sobaya/collab-dispatch.sh" "$D"
disp() { CLAUDE_PROJECT_DIR="$WS" sh "$D"; }
out="$(printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$WS" | disp)"
check "SessionStart: 앱 digest 가 앱 이름과 함께 주입"   "printf '%s' \"\$out\" | grep -q '앱: apps/shop' && printf '%s' \"\$out\" | grep -q '협업 현황'"
rc="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s/src/b.ts"},"cwd":"%s"}' "$A" "$WS" | disp 2>"$R/err"; echo $?)"
check "Write apps/shop/… (main) → 앱 규칙으로 차단"      "[ \"\$rc\" = 2 ] && grep -q '보호 브랜치' '$R/err'"
rc="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo x > apps/shop/src/b.ts"},"cwd":"%s"}' "$WS" | disp 2>"$R/err"; echo $?)"
check "Bash apps/shop/… (main) → 앱 규칙으로 차단"       "[ \"\$rc\" = 2 ]"
rc="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s/brain/note.md"},"cwd":"%s"}' "$WS" "$WS" | disp 2>/dev/null; echo $?)"
check "sobaya 루트 자체 파일은 관여 안 함"               "[ \"\$rc\" = 0 ]"
rc="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"tdd-set/bin/step.sh apps/shop"},"cwd":"%s"}' "$WS" | disp 2>/dev/null; echo $?)"
check "sobaya 명령(쓰기 패턴 없음)은 통과"                "[ \"\$rc\" = 0 ]"
git -C "$A" switch -q feat/x
rc="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo x > apps/shop/src/b.ts"},"cwd":"%s"}' "$WS" | disp 2>/dev/null; echo $?)"
check "claim 있는 브랜치면 루트에서의 Bash 쓰기 통과"     "[ \"\$rc\" = 0 ]"
cd "$A" && echo n > src/n.ts
out="$(printf '{"hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s"}' "$WS" | disp)"
check "Stop: 앱에 저널 없으면 block 전달"                 "printf '%s' \"\$out\" | grep -q '\"decision\":\"block\"'"
rm -f src/n.ts

echo "# sobaya 감지와 lock"
d="$(sh scripts/collab.sh digest)"
check "digest: sobaya 워크스페이스 감지, 미결합 안내"      "printf '%s' \"\$d\" | grep -q '아직 붙이지 않음'"
printf 'repo=x\nsha=%s\nchecked=%s\n' "$(git -C "$WS" rev-parse HEAD)" "$today" > harness/sobaya.lock
check "digest: lock 과 일치"                              "sh scripts/collab.sh digest | grep -q '팀 검증 버전과 일치'"
git -C "$WS" commit -q --allow-empty -m bump
check "digest: sobaya 가 lock 과 다르면 sync 권유"         "sh scripts/collab.sh digest | grep -q 'attach-sobaya.sh sync'"

echo "# merge 모드"
. "$A/.claude/hooks/lib.sh"
check "승인 상태 없음 → rebase"                           "[ \"\$(sync_mode)\" = rebase ]"
mkdir -p "$(git rev-parse --absolute-git-dir)/sobaya" && echo '{"baseline":"x"}' > "$(git rev-parse --absolute-git-dir)/sobaya/state.json"
check "승인 상태 있음 → merge"                            "[ \"\$(sync_mode)\" = merge ]"
git add -A && git commit -qm w >/dev/null 2>&1; base="$(git rev-parse HEAD)"
git switch -q main && echo m > src/m.ts && git add -A && git commit -qm main-change && git push -q origin main && git switch -q feat/x
out="$(sh scripts/collab.sh pulse)"   # pulse 가 직접 fetch 해서 main 변경을 본다
check "pulse: merge 로 따라잡고 조상 관계 유지"            "printf '%s' \"\$out\" | grep -q '자동으로 merge' && git merge-base --is-ancestor \"\$base\" HEAD"

echo "# plan 파일 규칙"
echo s > spec.md && echo f > failed-test.md && printf '# j\n\n## 이벤트\n- done src/ x\n\n## 남은 것\n- 없음\n' > "collab/journal/$today-solp-feat--x.md" && git add -A && git commit -qm plan
check "check: 루트 spec.md/failed-test.md 가 PR 에 있으면 실패" "! sh scripts/collab.sh check --base origin/main > '$R/chk' 2>&1 && grep -q 'plan 보관' '$R/chk'"
mkdir -p "collab/journal/plans/$today-solp-feat--x" && git mv spec.md failed-test.md "collab/journal/plans/$today-solp-feat--x/" && git commit -qm archive
check "check: plans/ 로 옮기면 통과 (plans 는 저널 entry 로 안 침)" "sh scripts/collab.sh check --base origin/main > '$R/chk' 2>&1"
rc="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/collab/journal/plans/%s-solp-feat--x/spec.md"}}' "$A" "$today" | sh .claude/hooks/guard.sh 2>/dev/null; echo $?)"
check "보관된 plan 은 append-only 로 보호"                  "[ \"\$rc\" = 2 ]"

echo "# attach-sobaya.sh check (실제 sobaya 없이 되는 부분)"
out="$(sh harness/attach-sobaya.sh check 2>&1)"
check "check: 클론·lock 출력"                             "printf '%s' \"\$out\" | grep -q 'sobaya 클론' && printf '%s' \"\$out\" | grep -q 'lock'"
echo; echo "통과 $pass / 실패 $fail"; [ $fail -eq 0 ]
