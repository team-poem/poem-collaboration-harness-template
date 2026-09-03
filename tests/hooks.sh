#!/bin/sh
# 훅 단위 검증. 임시 리포에서 실제 훅을 stdin JSON 으로 호출한다.
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; W="$(mktemp -d)"; trap 'rm -rf "$T" "$W"' EXIT
cp -R "$SRC/.claude" "$SRC/harness" "$SRC/collab" "$SRC/scripts" "$SRC/.gitignore" "$T"/; rm -rf "$T/.claude/cache"
cd "$T" && git init -q -b main && git config user.email t@t && git config user.name t && git config collab.me me
mkdir -p src/auth src/pay collab/journal prisma && echo x > src/auth/a.ts && echo y > src/pay/p.ts && echo s > prisma/schema.prisma && echo '{}' > package.json
echo j > collab/journal/2026-01-01-minsu-old.md
git add -A && git commit -qm init
git switch -qc feat/pay && mkdir -p collab/active/feat--pay
printf -- '---\nbranch: feat/pay\nowner: minsu\nstarted: 2026-01-01\nstatus: active\ngoal: pay\n---\n' > collab/active/feat--pay/claim.md
git add -A && git commit -qm claim && git switch -q main
export CLAUDE_PROJECT_DIR="$T"; H="$T/.claude/hooks"; pass=0; fail=0
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
printf 'minsu\t120\tpackage.json src/pay/p.ts\n' > .claude/cache/wip.tsv
expect "허브 파일을 동료가 만지는 중 → 차단" guard package.json 2
check  "메시지에 상대와 시각"               "grep -q 'minsu' '$W/err' && grep -q '120초' '$W/err'"
expect "허브 아닌 파일은 통과"              guard src/pay/p.ts 0
call post-edit src/pay/p.ts >/dev/null;     check "post-edit: 겹침 알림" "grep -q '겹침: src/pay/p.ts' '$W/out'"
call post-edit src/pay/p.ts >/dev/null;     check "post-edit: 같은 파일 재알림 없음" "[ ! -s '$W/out' ]"
expect "동료가 안 만지는 허브 파일은 통과"   guard prisma/schema.prisma 0
sh scripts/collab.sh guard --allow package.json >/dev/null
expect "--allow 후 통과"                    guard package.json 0
check  "CLI guard 도 같은 판정"             "! sh scripts/collab.sh guard src/nothing.ts 2>/dev/null; sh scripts/collab.sh guard src/auth/a.ts"
rm -f .claude/cache/wip.tsv .claude/cache/allow

echo "# 루트 탐색"
mkdir -p "$W/ws/apps" && cp -R "$T" "$W/ws/apps/x" && rm -rf "$W/ws/apps/x/.claude/cache"
got="$(cd "$W/ws" && CLAUDE_PROJECT_DIR="$W/ws" sh "$W/ws/apps/x/.claude/hooks/guard.sh" 2>/dev/null <<EOF2
{"tool_name":"Write","tool_input":{"file_path":"$W/ws/apps/x/collab/journal/2026-01-01-minsu-old.md"}}
EOF2
echo $?)"
check "워크스페이스 루트에서 앱 파일 → 앱의 collab 규칙 적용" "[ '$got' = 2 ]"

echo "# 이벤트 파서"
. "$H/lib.sh"
check "changed + 경로"   "[ \"\$(printf -- '- changed lib/api/user.ts getUser 가 id 를 받음 → 호출부 수정' | sed 's/^[[:space:]]*-[[:space:]]*//' | awk '{t=\$1; p=\"-\"; s=2; if (\$2 ~ /[\\/.]/ && \$2 !~ /^@/) { p=\$2; s=3 }; txt=\"\"; for (i=s;i<=NF;i++) txt=txt (i>s?\" \":\"\") \$i; printf \"%s|%s|%s\", t, p, txt}')\" = 'changed|lib/api/user.ts|getUser 가 id 를 받음 → 호출부 수정' ]"
check "ask @핸들 (경로 없음)" "[ \"\$(printf -- '- ask @me 웹훅이 토큰 읽나?' | sed 's/^[[:space:]]*-[[:space:]]*//' | awk '{t=\$1; p=\"-\"; s=2; if (\$2 ~ /[\\/.]/ && \$2 !~ /^@/) { p=\$2; s=3 }; txt=\"\"; for (i=s;i<=NF;i++) txt=txt (i>s?\" \":\"\") \$i; printf \"%s|%s|%s\", t, p, txt}')\" = 'ask|-|@me 웹훅이 토큰 읽나?' ]"
check "md_section"       "[ \"\$(printf '## 이벤트\n- a\n\n- b\n## 남은 것\n- c\n' > '$W/m.md'; md_section '$W/m.md' 이벤트 | tr '\n' ' ')\" = '- a - b ' ]"
check "wip_snapshot 이 미추적 파일 포함"  "echo new > src/auth/untracked.ts; sha=\$(wip_snapshot); git ls-tree -r --name-only \$sha | grep -q src/auth/untracked.ts && ! git log --oneline | grep -q wip"

echo "# check"
echo z > src/auth/b.ts; printf '# j\n\n## 이벤트\n- changed src/auth/a.ts x\n\n## 남은 것\n- y\n' > collab/journal/2026-01-02-me-feat--login.md
git add -A && git commit -qm work
check "check 통과"                         "sh scripts/collab.sh check --base main >'$W/chk' 2>&1"
printf '# bad\n' > collab/journal/2026-01-02-me-feat--login-2.md; git add -A && git commit -qm bad
check "check: 이벤트 절 없는 저널 실패"     "! sh scripts/collab.sh check --base main >'$W/chk' 2>&1 && grep -q '절 없음' '$W/chk'"
git reset -q --hard HEAD~1; echo edit >> collab/journal/2026-01-01-minsu-old.md; git add -A && git commit -qm edit-old
check "check: 기존 저널 수정 실패"          "! sh scripts/collab.sh check --base main >'$W/chk' 2>&1 && grep -q '기존 저널' '$W/chk'"
git reset -q --hard HEAD~1
git switch -q main && git merge -q --no-ff --no-edit feat/login >/dev/null 2>&1
check "prune: 머지된 claim 삭제"            "sh scripts/collab.sh prune | grep -q '삭제: collab/active/feat--login'"
echo; echo "통과 $pass / 실패 $fail"; [ $fail -eq 0 ]
