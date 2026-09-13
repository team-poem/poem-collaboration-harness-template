#!/bin/sh
# 훅 단위 검증. 임시 리포에서 실제 훅을 stdin JSON 으로 호출한다.
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; W="$(mktemp -d)"; trap 'rm -rf "$T" "$W"' EXIT
cp -R "$SRC/.claude" "$SRC/.codex" "$SRC/.githooks" "$SRC/harness" "$SRC/collab" "$SRC/scripts" "$SRC/.gitignore" "$T"/; rm -rf "$T/.claude/cache"
cd "$T" && git init -q -b main && git config user.email t@t && git config user.name t && git config collab.me me
mkdir -p src/auth src/pay collab/journal prisma && echo x > src/auth/a.ts && echo y > src/pay/p.ts && echo s > prisma/schema.prisma && echo '{}' > package.json
echo j > collab/journal/2026-01-01-minsu-old.md
git add -A && git commit -qm init
git switch -qc feat/pay && mkdir -p collab/active/feat--pay
printf -- '---\nbranch: feat/pay\nowner: minsu\nstarted: 2026-01-01\nstatus: active\ngoal: pay\n---\n' > collab/active/feat--pay/claim.md
git add -A && git commit -qm claim && git switch -q main
export CLAUDE_PROJECT_DIR="$T"; H="$T/harness/hooks"; pass=0; fail=0
call() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s/%s"}}' "$T" "$2" | sh "$H/$1.sh" 2>"$W/err" >"$W/out"; echo $?; }
bash_call() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | sh "$H/guard.sh" 2>"$W/err" >"$W/out"; echo $?; }
expect() { got="$(call "$2" "$3")"; if [ "$got" = "$4" ]; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1 (exit $got, expected $4)"; sed 's/^/     /' "$W/err"; fi; }
expect_bash() { got="$(bash_call "$2")"; if [ "$got" = "$3" ]; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1 (exit $got, expected $3)"; sed 's/^/     /' "$W/err"; fi; }
check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; fi; }

echo "# main"
expect "main: 코드 차단"                  guard src/auth/a.ts 2
expect "main: collab/ 허용"               guard collab/journal/README.md 0
expect "main: 남의 claim 차단"            guard collab/active/feat--pay/claim.md 2
expect_bash "main: bash 리다이렉션 차단"   "echo hi > src/auth/a.ts" 2
expect_bash "main: 없는 디렉토리로 쓰기도 차단" "mkdir -p src/new && echo x > src/new/i.ts" 2
expect_bash "main: 읽기 통과"              "cat src/auth/a.ts | grep x" 0
expect_bash "main: 2>/dev/null 은 쓰기 아님" "ls src 2>/dev/null" 0
expect_bash "main: > /dev/null (공백) 도 쓰기 아님" "ls -la > /dev/null" 0
expect_bash "main: git commit 통과"        'git add -A && git commit -m "x"' 0

echo "# 브랜치, claim 없음"
git switch -qc feat/login
expect "claim 없음: 차단"                 guard src/auth/a.ts 2
expect "claim 없음: 내 claim 디렉토리 허용" guard collab/active/feat--login/claim.md 0
expect_bash "claim 없음: sed -i 차단"      "sed -i '' 's/x/y/' src/auth/a.ts" 2
expect_bash "claim 없음: heredoc 차단"     "cat > src/auth/new.ts <<'EOT'
x
EOT" 2

echo "# 브랜치, claim 있음"
mkdir -p collab/active/feat--login
printf -- '---\nbranch: feat/login\nowner: me\nstarted: 2026-01-02\nstatus: active\ngoal: login\n---\n' > collab/active/feat--login/claim.md
expect "코드 허용"                         guard src/auth/a.ts 0
expect "동료 파일도 허용 (scope 없음)"     guard src/pay/p.ts 0
expect_bash "bash 코드 허용"               "echo 1 >> src/auth/a.ts" 0
expect_bash "collab.sh 자체는 통과"        "sh scripts/collab.sh check > /dev/null" 0
expect "남의 claim 차단"                   guard collab/active/feat--pay/claim.md 2
expect "내 claim 디렉토리 산출물 허용"      guard collab/active/feat--login/failed-test.md 0
expect "새 저널 허용"                      guard collab/journal/2026-01-02-me-feat--login.md 0
expect "기존 저널 차단"                    guard collab/journal/2026-01-01-minsu-old.md 2
S="$(ln -s "$T" "$W/link" && echo "$W/link")"
got="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/collab/journal/2026-01-01-minsu-old.md"}}' "$S" | sh "$H/guard.sh" 2>/dev/null; echo $?)"
check "심링크 경로도 정규화해 차단"        "[ '$got' = 2 ]"

echo "# 허브 파일 + 동료 wip"
printf 'minsu\tfeat--pay\t120\tpackage.json src/pay/p.ts\t-\n' > .claude/cache/wip.tsv
expect "허브 파일을 동료가 편집 중 → 차단"  guard package.json 2
check  "메시지에 상대와 시각"               "grep -q 'minsu' '$W/err' && grep -q '120초' '$W/err'"
expect "허브 아닌 파일은 통과"              guard src/pay/p.ts 0
printf 'minsu\tfeat--pay\t120\t-\tpackage.json\n' > .claude/cache/wip.tsv
expect "동료 브랜치에 커밋만 된 허브 파일은 통과(알림만)" guard package.json 0
call post-edit package.json >/dev/null;     check "post-edit: 커밋된 겹침도 알림" "grep -q '겹침: package.json' '$W/out'"
printf 'minsu\tfeat--pay\t120\tpackage.json src/pay/p.ts\t-\n' > .claude/cache/wip.tsv; rm -f .claude/cache/warned
call post-edit src/pay/p.ts >/dev/null;     check "post-edit: 겹침 알림" "grep -q '겹침: src/pay/p.ts' '$W/out'"
call post-edit src/pay/p.ts >/dev/null;     check "post-edit: 같은 파일 재알림 없음" "[ ! -s '$W/out' ]"
expect "동료가 안 만지는 허브 파일은 통과"   guard prisma/schema.prisma 0
sh scripts/collab.sh guard --allow package.json >/dev/null
expect "--allow 후 통과"                    guard package.json 0
check  "CLI guard 도 같은 판정"             "! sh scripts/collab.sh guard src/nothing.ts 2>/dev/null; sh scripts/collab.sh guard src/auth/a.ts"
rm -f .claude/cache/wip.tsv .claude/cache/allow

echo "# 루트 탐색"
mkdir -p "$W/ws/apps" && cp -R "$T" "$W/ws/apps/x" && rm -rf "$W/ws/apps/x/.claude/cache"
got="$(cd "$W/ws" && CLAUDE_PROJECT_DIR="$W/ws" sh "$W/ws/apps/x/harness/hooks/guard.sh" 2>/dev/null <<EOF2
{"tool_name":"Write","tool_input":{"file_path":"$W/ws/apps/x/collab/journal/2026-01-01-minsu-old.md"}}
EOF2
echo $?)"
check "워크스페이스 루트에서 앱 파일 → 앱의 collab 규칙 적용" "[ '$got' = 2 ]"

echo "# 이벤트 파서"
. "$H/lib.sh"
check "changed + 경로"   "[ \"\$(printf -- '- changed lib/api/user.ts getUser 가 id 를 받음 → 호출부 수정' | sed 's/^[[:space:]]*-[[:space:]]*//' | awk '{t=\$1; p=\"-\"; s=2; if (\$2 ~ /[\\/.]/ && \$2 !~ /^@/) { p=\$2; s=3 }; txt=\"\"; for (i=s;i<=NF;i++) txt=txt (i>s?\" \":\"\") \$i; printf \"%s|%s|%s\", t, p, txt}')\" = 'changed|lib/api/user.ts|getUser 가 id 를 받음 → 호출부 수정' ]"
check "dep zod@3.23 은 경로 아님"  "[ \"\$(printf -- '- dep zod@3.23 추가' | sed 's/^[[:space:]]*-[[:space:]]*//' | awk '{t=\$1; p=\"-\"; s=2; if (\$2 ~ /\\// && \$2 !~ /^@/) { p=\$2; s=3 }; txt=\"\"; for (i=s;i<=NF;i++) txt=txt (i>s?\" \":\"\") \$i; printf \"%s|%s|%s\", t, p, txt}')\" = 'dep|-|zod@3.23 추가' ]"
check "ask @핸들 (경로 없음)" "[ \"\$(printf -- '- ask @me 웹훅이 토큰 읽나?' | sed 's/^[[:space:]]*-[[:space:]]*//' | awk '{t=\$1; p=\"-\"; s=2; if (\$2 ~ /[\\/.]/ && \$2 !~ /^@/) { p=\$2; s=3 }; txt=\"\"; for (i=s;i<=NF;i++) txt=txt (i>s?\" \":\"\") \$i; printf \"%s|%s|%s\", t, p, txt}')\" = 'ask|-|@me 웹훅이 토큰 읽나?' ]"
check "md_section"       "[ \"\$(printf '## 이벤트\n- a\n\n- b\n## 남은 것\n- c\n' > '$W/m.md'; md_section '$W/m.md' 이벤트 | tr '\n' ' ')\" = '- a - b ' ]"
check "wip_snapshot 이 미추적 파일 포함"  "echo new > src/auth/untracked.ts; sha=\$(wip_snapshot); git ls-tree -r --name-only \$sha | grep -q src/auth/untracked.ts && ! git log --oneline | grep -q wip"

echo "# 온보딩: 리포 상태에 따라 세션 시작이 달라지는가"
O="$(mktemp -d)"; cp -R "$SRC/.claude" "$SRC/.codex" "$SRC/.githooks" "$SRC/.agents" "$SRC/harness" "$SRC/collab" "$SRC/scripts" "$SRC/.gitignore" "$SRC/AGENTS.md" "$O"/; rm -rf "$O/.claude/cache"
(cd "$O" && git init -q -b main && git config user.email o@o && git config user.name o && git add -A && git commit -qm init) >/dev/null 2>&1
st="$(cd "$O" && CLAUDE_PROJECT_DIR="$O" sh scripts/collab.sh state)"
check "플레이스홀더 남음 → state=setup"          "printf '%s' \"\$st\" | grep -q '^state=setup'"
out="$(cd "$O" && CLAUDE_PROJECT_DIR="$O" sh harness/hooks/session-start.sh </dev/null)"
check "setup: 세션 시작이 온보딩 메뉴를 주입"      "printf '%s' \"\$out\" | grep -q '온보딩' && printf '%s' \"\$out\" | grep -q '새 프로젝트 만들기' && ! printf '%s' \"\$out\" | grep -q '# 협업 현황'"
(cd "$O" && sh harness/init.sh demo solp >/dev/null 2>&1 && git config --unset collab.me)
st="$(cd "$O" && CLAUDE_PROJECT_DIR="$O" sh scripts/collab.sh state)"
check "초기화됐지만 핸들 없음 → state=join"        "printf '%s' \"\$st\" | grep -q '^state=join'"
out="$(cd "$O" && CLAUDE_PROJECT_DIR="$O" sh harness/hooks/session-start.sh </dev/null)"
check "join: 메뉴 없이 합류 안내"                  "printf '%s' \"\$out\" | grep -q 'join' && ! printf '%s' \"\$out\" | grep -q '새 프로젝트 만들기'"
(cd "$O" && sh harness/join.sh amazon >/dev/null)
st="$(cd "$O" && CLAUDE_PROJECT_DIR="$O" sh scripts/collab.sh state)"
check "join.sh 후 → state=ready (핸들·훅·rerere)"  "printf '%s' \"\$st\" | grep -q '^state=ready' && [ \"\$(git -C '$O' config collab.me)\" = amazon ] && [ \"\$(git -C '$O' config core.hooksPath)\" = .githooks ]"
out="$(cd "$O" && CLAUDE_PROJECT_DIR="$O" sh harness/hooks/session-start.sh </dev/null)"
check "ready: 세션 시작이 협업 현황을 주입"        "printf '%s' \"\$out\" | grep -q '# 협업 현황'"
check "init.sh 가 scripts/·hooks 의 코드를 안 건드림"  "grep -q 'PROJECT_NAME' '$O/scripts/collab.sh' && ! grep -q 'demo' '$O/harness/hooks/lib.sh'"
X="$(mktemp -d)"; (cd "$X" && git init -q -b main && git config user.email x@x && git config user.name x && echo '# 기존 프로젝트' > AGENTS.md && echo '{}' > package.json && git add -A && git commit -qm init) >/dev/null 2>&1
(cd "$SRC" && sh harness/install-into.sh "$X" shop solp >"$W/inst" 2>&1)
check "install-into: 하네스 복사 + init, 기존 AGENTS.md 보존"  "[ -f '$X/scripts/collab.sh' ] && [ -f '$X/harness/hooks/lib.sh' ] && [ -f '$X/AGENTS.collab.md' ] && grep -q '기존 프로젝트' '$X/AGENTS.md' && [ \"\$(git -C '$X' config collab.me)\" = solp ] && [ -L '$X/.claude/skills' ]"
check "install-into: 두 번 돌려도 안전(멱등)"        "(cd '$SRC' && sh harness/install-into.sh '$X' shop solp >/dev/null 2>&1) && [ -f '$X/scripts/collab.sh' ]"
rm -rf "$O" "$X"

echo "# 설정 일관성: Claude 와 Codex 가 같은 훅 스크립트를 가리키는가"
c1="$(jq -r '.hooks|to_entries[]|.key+" "+(.value[]|.hooks[]|.command|sub("^\"\\$CLAUDE_PROJECT_DIR\"/";""))' "$SRC/.claude/settings.json" | sort)"
c2="$(jq -r '.hooks|to_entries[]|.key+" "+(.value[]|.hooks[]|.command)' "$SRC/.codex/hooks.json" | sort)"
check "git 훅 4개 존재·실행 가능"             "for h in pre-commit pre-push pre-merge-commit post-commit; do [ -x \"$SRC/.githooks/\$h\" ] || exit 1; done"
check "settings.json ≡ .codex/hooks.json"   "[ \"\$c1\" = \"\$c2\" ] && [ -n \"\$c1\" ]"
check "가리키는 스크립트가 모두 존재·실행 가능" "for s in \$(printf '%s\n' \"\$c2\" | awk '{print \$2}' | sort -u); do [ -x \"\$SRC/\$s\" ] || exit 1; done"
check ".claude/skills → .agents/skills 심링크" "[ -L '$SRC/.claude/skills' ] && [ -f '$SRC/.claude/skills/start-work/SKILL.md' ]"
check "CLAUDE.md → AGENTS.md 심링크"          "[ -L '$SRC/CLAUDE.md' ] && [ ! -L '$SRC/AGENTS.md' ]"

echo "# git 훅 (도구 무관): pre-commit 이 guard 와 같은 규칙"
git config core.hooksPath .githooks
git switch -q main
echo hack > src/auth/a.ts; git add src/auth/a.ts
check "main: 코드 커밋 차단"                  "! git commit -qm x 2>/dev/null"
git reset -q HEAD src/auth/a.ts; git checkout -q src/auth/a.ts
echo note >> collab/journal/README.md; git add collab/journal/README.md
check "main: collab/ 커밋 허용"                "git commit -qm note 2>/dev/null"
git switch -qc feat/hook
echo x > src/auth/h.ts; git add src/auth/h.ts
check "claim 없음: 커밋 차단"                  "! git commit -qm x 2>/dev/null"
mkdir -p collab/active/feat--hook && printf -- '---\nbranch: feat/hook\nowner: me\nstatus: active\ngoal: h\n---\n' > collab/active/feat--hook/claim.md && git add collab/active/feat--hook
check "claim 과 함께면 커밋 허용"               "git commit -qm claim 2>/dev/null"
echo edit >> collab/journal/2026-01-01-minsu-old.md; git add collab/journal/2026-01-01-minsu-old.md
check "기존 저널 수정 커밋 차단"               "! git commit -qm x 2>/dev/null"
git reset -q HEAD collab/journal/2026-01-01-minsu-old.md && git checkout -q collab/journal/2026-01-01-minsu-old.md
echo z >> collab/active/feat--pay/claim.md; git add collab/active/feat--pay/claim.md
check "남의 claim 수정 커밋 차단"              "! git commit -qm x 2>/dev/null"
git reset -q HEAD collab/active/feat--pay/claim.md && git checkout -q collab/active/feat--pay/claim.md
printf 'minsu\tfeat--pay\t60\tpackage.json\t-\n' > .claude/cache/wip.tsv; date +%s > .claude/cache/pulse.at; echo '{"a":1}' > package.json; git add package.json
check "pre-commit 은 wip 허브를 차단 안 하고 경고만"    "git commit -qm pkg 2>'$W/err' && grep -q '주의: 허브 파일' '$W/err'"
rm -f .claude/cache/wip.tsv
printf '#!/bin/sh\necho SOBAYA_HOOK_RAN >> "$(git rev-parse --show-toplevel)/.sobaya-ran"\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
echo y > src/auth/y.ts; git add src/auth/y.ts; git commit -qm y 2>/dev/null
check "sobaya 앱 pre-commit 을 이어서 실행"     "[ -f .sobaya-ran ]"
rm -f .git/hooks/pre-commit .sobaya-ran
echo "# git 훅: pre-push / pre-merge-commit / post-commit"
check "pre-push: main 으로 직접 push 차단"      "! printf 'refs/heads/main %s refs/heads/main %s\n' \$(git rev-parse HEAD) 0000000000000000000000000000000000000000 | sh .githooks/pre-push 2>/dev/null"
check "pre-push: 브랜치 push 통과"              "printf 'refs/heads/feat/hook %s refs/heads/feat/hook 0000000000000000000000000000000000000000\n' \$(git rev-parse HEAD) | sh .githooks/pre-push 2>/dev/null"
check "pre-push: CI 예외"                       "printf 'refs/heads/main %s refs/heads/main 0\n' \$(git rev-parse HEAD) | COLLAB_ALLOW_PROTECTED_PUSH=1 sh .githooks/pre-push 2>/dev/null"
git switch -q main
check "pre-merge-commit: main 에서 코드 브랜치 로컬 머지 차단" "! git merge -q --no-ff --no-edit feat/hook 2>/dev/null; git merge --abort 2>/dev/null; ! git log --oneline -1 | grep -q 'Merge'"
git config --unset core.hooksPath; git switch -q feat/login

echo "# check"
echo z > src/auth/b.ts; printf '# j\n\n## 이벤트\n- changed src/auth/a.ts x\n\n## 남은 것\n- y\n' > collab/journal/2026-01-02-me-feat--login.md
git add -A && git commit -qm work
check "check 통과"                         "sh scripts/collab.sh check --base main >'$W/chk' 2>&1"
check "check: CI(detached HEAD)에서 자기 브랜치를 남으로 안 봄" "git switch -q --detach && GITHUB_HEAD_REF=feat/login sh scripts/collab.sh check --base main 2>&1 | grep -v -q '같은 파일을 바꿈' ; git switch -q feat/login"
printf '# bad\n' > collab/journal/2026-01-02-me-feat--login-2.md; git add -A && git commit -qm bad
check "check: 이벤트 절 없는 저널 실패"     "! sh scripts/collab.sh check --base main >'$W/chk' 2>&1 && grep -q '절 없음' '$W/chk'"
git reset -q --hard HEAD~1; echo edit >> collab/journal/2026-01-01-minsu-old.md; git add -A && git commit -qm edit-old
check "check: 기존 저널 수정 실패"          "! sh scripts/collab.sh check --base main >'$W/chk' 2>&1 && grep -q '기존 저널' '$W/chk'"
git reset -q --hard HEAD~1
git switch -q main && git merge -q --no-ff --no-edit feat/login >/dev/null 2>&1
check "prune: 머지된 claim 삭제"            "sh scripts/collab.sh prune | grep -q '삭제: collab/active/feat--login'"
echo; echo "통과 $pass / 실패 $fail"; [ $fail -eq 0 ]
