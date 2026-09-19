#!/bin/sh
# 협업 루프 검증. bare 원격에 클론 둘(solp, amazon)을 붙여 동시에 작업할 때 실제로 서로를 보는지 확인한다.
set -u
unset GITHUB_HEAD_REF
SRC="$(cd "$(dirname "$0")/.." && pwd -P)"
R="$(mktemp -d)"; R="$(cd "$R" && pwd -P)"; trap 'rm -rf "$R"' EXIT
pass=0; fail=0; check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; fi; }
git init -q --bare "$R/origin.git" && git -C "$R/origin.git" symbolic-ref HEAD refs/heads/main   # 러너의 기본 브랜치가 master 여도 main 으로
git clone -q "$R/origin.git" "$R/seed" 2>/dev/null; cd "$R/seed" && git switch -qc main 2>/dev/null
cp -R "$SRC/.claude" "$SRC/.codex" "$SRC/.githooks" "$SRC/harness" "$SRC/collab" "$SRC/scripts" "$SRC/.gitignore" . && rm -rf .claude/cache
mkdir -p lib/api components/ui app/checkout app/settings prisma && printf 'export function getUser(){}\n' > lib/api/user.ts && echo b > components/ui/button.tsx && echo s > prisma/schema.prisma && echo '{}' > package.json
git -c user.name=seed -c user.email=s@s add -A && git -c user.name=seed -c user.email=s@s commit -qm init && git push -q origin main
clone() { git clone -q "$R/origin.git" "$R/$1" && cd "$R/$1" && git config user.name "$1" && git config user.email "$1@t" && git config collab.me "$1"; }
col() { (cd "$R/$1" && CLAUDE_PROJECT_DIR="$R/$1" sh scripts/collab.sh "$2" ${3:-} ${4:-}); }
hook() { (cd "$R/$1" && CLAUDE_PROJECT_DIR="$R/$1" sh "harness/hooks/$2.sh"); }
today="$(date +%Y-%m-%d)"
clone solp >/dev/null; clone amazon >/dev/null

# solp: 결제 페이지 브랜치 + claim push, 호출부 코드 작성
cd "$R/solp" && git switch -qc feat/checkout && mkdir -p collab/active/feat--checkout app/checkout
printf -- '---\nbranch: feat/checkout\nowner: solp\nstarted: %s\nstatus: active\ngoal: 결제 페이지\n---\n' "$today" > collab/active/feat--checkout/claim.md
printf 'import { getUser } from "../../lib/api/user"\n' > app/checkout/page.tsx
git add -A && git commit -qm "claim+page" && git push -q -u origin HEAD
# amazon: 설정 브랜치, getUser 시그니처 변경 + 공용 Toast 추가 + 저널(이벤트, ask @solp) push
cd "$R/amazon" && git switch -qc feat/settings && mkdir -p collab/active/feat--settings app/settings
printf -- '---\nbranch: feat/settings\nowner: amazon\nstarted: %s\nstatus: active\ngoal: 사용자 설정\n---\n' "$today" > collab/active/feat--settings/claim.md
printf 'export function getUser(id: string){}\n' > lib/api/user.ts; echo t > components/ui/toast.tsx; echo st > app/settings/page.tsx
printf '# feat/settings · amazon\n\n## 이벤트\n- changed lib/api/user.ts getUser 가 id 를 받음 → 호출부는 id 를 넘길 것\n- added components/ui/toast.tsx 공용 토스트 → 새로 만들지 말 것\n- changed app/settings/page.tsx 설정 화면 골격\n- ask @solp 결제 웹훅이 세션 토큰을 읽나?\n\n## 남은 것\n- 프로필 이미지 업로드 미구현\n' > "collab/journal/$today-amazon-feat--settings.md"
git add -A && git commit -qm "settings" && git push -q -u origin HEAD

echo "# solp 의 digest 가 amazon 을 읽는가"
d="$(col solp digest --fetch)"
check "ask @solp 가 맨 위"                   "printf '%s' \"\$d\" | grep -q '@amazon (feat/settings): @solp 결제 웹훅'"
check "내가 import 하는 파일의 changed 주입"  "printf '%s' \"\$d\" | grep -q '\[changed\] lib/api/user.ts getUser'"
check "added 는 항상 주입"                    "printf '%s' \"\$d\" | grep -q '\[added\] components/ui/toast.tsx'"
check "무관한 changed 는 안 뜸"               "! printf '%s' \"\$d\" | grep -q 'app/settings/page.tsx'"
check "동료 작업 중에 goal"                   "printf '%s' \"\$d\" | grep -q 'feat/settings · @amazon · active · 사용자 설정'"
check "digest --json 유효"                    "col solp digest --json | jq -e '.asks|length==1' >/dev/null"
d2="$(col solp digest)"
check "두 번째 digest: 이벤트는 사라지고 ask 는 남음" "! printf '%s' \"\$d2\" | grep -q '\[changed\]' && printf '%s' \"\$d2\" | grep -q '@solp 결제 웹훅'"

echo "# 동시 작업: 같은 파일을 만지면"
cd "$R/amazon" && echo 'size' >> components/ui/button.tsx && echo '{"dep":1}' > package.json     # 커밋 안 함
check "amazon pulse: 작업 트리 스냅샷 push (브랜치별 ref)"   "col amazon pulse >/dev/null; git -C '$R/origin.git' show-ref refs/wip/amazon/feat--settings >/dev/null"
cd "$R/solp" && echo 'loading' >> components/ui/button.tsx
out="$(col solp pulse)"
check "solp pulse: button.tsx 겹침 감지"      "printf '%s' \"\$out\" | grep -q '겹침: components/ui/button.tsx 를 @amazon'"
p2="$(col solp pulse)"; check "solp pulse: 두 번째는 조용"            "[ -z \"\$p2\" ]"; [ -n "$p2" ] && printf '%s\n' "$p2" | sed 's/^/     /'

rc="$(cd "$R/solp" && printf '{"tool_name":"Write","tool_input":{"file_path":"%s/package.json"}}' "$R/solp" | CLAUDE_PROJECT_DIR="$R/solp" sh harness/hooks/guard.sh 2>"$R/err"; echo $?)"
check "허브 파일(package.json) 은 차단"       "[ \"\$rc\" = 2 ] && grep -q 'amazon' '$R/err'"
rc="$(cd "$R/solp" && printf '{"tool_name":"Write","tool_input":{"file_path":"%s/components/ui/button.tsx"}}' "$R/solp" | CLAUDE_PROJECT_DIR="$R/solp" sh harness/hooks/guard.sh 2>/dev/null; echo $?)"
check "허브 아닌 겹침 파일은 통과"            "[ \"\$rc\" = 0 ]"
check "digest 에 '같은 파일을 만지는 중'"     "col solp digest | grep -q 'components/ui/button.tsx ← @amazon'"

echo "# 열린 PR 에 추가 커밋한 뒤 같은 파일을 다시 편집하면"
edit_notice() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/components/ui/button.tsx"}}' "$R/solp" | hook solp post-edit; }
out="$(edit_notice)"
check "수정 훅: 브랜치와 숫자 나이를 편집 상태로 표시" "printf '%s' \"\$out\" | grep -Eq '@amazon\\(feat--settings, 작업 트리 [0-9]+초 전\\).*편집 중'"
cd "$R/amazon" && git config core.hooksPath .githooks && git add -A && git commit -qm "PR 추가 커밋"
git config --unset core.hooksPath
out="$(col solp pulse)"
check "추가 커밋 뒤 편집 겹침이 미머지 겹침으로 바뀜" "printf '%s' \"\$out\" | grep -q '겹침(커밋됨): components/ui/button.tsx'"
check "상대가 커밋한 허브 파일은 차단 해제" "col solp guard package.json"
out="$(edit_notice)"
check "수정 훅: 커밋된 변경을 다시 편집 중이라고 말하지 않음" "printf '%s' \"\$out\" | grep -q '커밋됨(미머지)' && ! printf '%s' \"\$out\" | grep -q '편집 중'"
cd "$R/amazon" && echo 'size again' >> components/ui/button.tsx && col amazon pulse >/dev/null
out="$(col solp pulse)"
check "동일 PR 에서 다시 편집하면 겹침을 다시 알림" "printf '%s' \"\$out\" | grep -q '겹침: components/ui/button.tsx 를 @amazon'"
out="$(col solp pulse)"
check "재편집도 같은 상태가 지속되는 동안은 조용" "[ -z \"\$out\" ]"

echo "# reply 로 ask 가 사라지는가"
cd "$R/solp" && printf '# feat/checkout · solp\n\n## 이벤트\n- reply @amazon 웹훅은 토큰을 읽지 않음\n- touching components/ui/button.tsx loading prop 추가 중\n\n## 남은 것\n- 결제 확인 화면\n' > "collab/journal/$today-solp-feat--checkout.md"
check "reply 후 ask 사라짐"                   "! col solp digest | grep -q '@solp 결제 웹훅'"

echo "# main 변경 → 자동 merge 와 충돌 복구"
cd "$R/amazon" && git stash -q && git switch -q main && echo 'export const X = 1' > lib/api/consts.ts && git add -A && git commit -qm "main change" && git push -q origin main && git switch -q feat/settings && git stash pop -q
cd "$R/solp" && git add -A && git commit -qm "solp work" >/dev/null
out="$(col solp pulse)"
check "깨끗한 트리: 자동 merge (기본)"        "printf '%s' \"\$out\" | grep -q '자동으로 merge' && git -C '$R/solp' merge-base --is-ancestor origin/main HEAD"
cd "$R/amazon" && git add -A && git commit -qm "amazon work" -q && git push -q origin HEAD && git switch -q main && mkdir -p app/checkout && printf 'import { getUser } from \"../../lib/api/user\"\nconflict\n' > app/checkout/page.tsx && git add -A && git commit -qm "main conflict" && git push -q origin main && git switch -q feat/settings
cd "$R/solp" && echo more >> app/checkout/page.tsx && git add -A && git commit -qm "solp more" -q
conflict_head="$(git rev-parse HEAD)"; conflict_tree="$(git write-tree)"; conflict_file="$(git hash-object app/checkout/page.tsx)"
out="$(col solp pulse)"
check "충돌: abort 하고 알림"                 "printf '%s' \"\$out\" | grep -q 'main 과 충돌: app/checkout/page.tsx' && ! git rev-parse -q --verify MERGE_HEAD >/dev/null"
check "충돌 복구 후 원래 HEAD·인덱스·파일 내용 보존" "[ \"\$(git rev-parse HEAD)\" = \"\$conflict_head\" ] && [ \"\$(git write-tree)\" = \"\$conflict_tree\" ] && [ \"\$(git hash-object app/checkout/page.tsx)\" = \"\$conflict_file\" ] && [ -z \"\$(git status --porcelain)\" ]"
cd "$R/solp" && echo dirty > app/checkout/x.ts
out="$(col solp pulse)"
check "미커밋 파일이 있으면 merge 안 하고 안내" "printf '%s' \"\$out\" | grep -q '커밋한 뒤' && [ \"\$(git rev-parse HEAD)\" = \"\$conflict_head\" ] && [ \"\$(cat app/checkout/x.ts)\" = dirty ]"

echo "# squash 머지 감지와 브랜치별 seen"
cd "$R/amazon" && git switch -q main && git pull -q --ff-only origin main 2>/dev/null; git merge -q --squash feat/settings >/dev/null 2>&1 && git commit -qm "feat: settings (squash)" && git push -q origin main; git switch -q feat/settings
check "squash 머지된 브랜치는 동료 목록에서 사라짐"  "! col solp digest --fetch | grep -q 'feat/settings · @amazon'"
check "squash 머지된 저널 이벤트가 중복 주입되지 않음" "[ \"\$(col solp digest | grep -c 'toast.tsx')\" -le 1 ]"
cd "$R/solp" && git switch -qc feat/other origin/main 2>/dev/null && mkdir -p collab/active/feat--other && printf -- '---\nbranch: feat/other\nowner: solp\nstarted: %s\nstatus: active\ngoal: other\n---\n' "$today" > collab/active/feat--other/claim.md && printf 'import { getUser } from "../../lib/api/user"\n' > app/checkout/other.tsx && git add -A && git commit -qm other >/dev/null
cd "$R/amazon" && git switch -qc feat/again origin/main 2>/dev/null && mkdir -p collab/active/feat--again && printf -- '---\nbranch: feat/again\nowner: amazon\nstarted: %s\nstatus: active\ngoal: again\n---\n' "$today" > collab/active/feat--again/claim.md && echo again >> components/ui/button.tsx && printf '# again\n\n## 이벤트\n- changed lib/api/user.ts getUser 반환형 변경 → 호출부 확인\n\n## 남은 것\n- x\n' > "collab/journal/$today-amazon-feat--again.md" && git add -A && git commit -qm again && git push -q -u origin HEAD
check "브랜치 X 에서 본 이벤트"                 "col solp digest --fetch | grep -q '반환형 변경'"
cd "$R/solp" && git switch -q feat/checkout
check "다른 브랜치 Y 의 세션에서도 다시 뜸 (브랜치별 seen)" "col solp digest | grep -q '반환형 변경'"
cd "$R/solp" && git switch -q feat/other

echo "# 내 다른 브랜치는 동료가 아니다 (보고 1·9번)"
cd "$R/solp" && git switch -qc feat/second origin/main 2>/dev/null && mkdir -p collab/active/feat--second
printf -- '---\nbranch: feat/second\nowner: solp\nstarted: %s\nstatus: active\ngoal: 두 번째 작업\n---\n' "$today" > collab/active/feat--second/claim.md
echo second >> components/ui/button.tsx && git add -A && git commit -qm second >/dev/null && git push -q -u origin HEAD
git switch -q feat/checkout; echo mine >> components/ui/button.tsx
d="$(col solp digest --fetch)"

check "내 다른 브랜치가 '동료 작업 중' 에 안 뜸"     "! printf '%s' \"\$d\" | grep -q 'feat/second · @solp'"
check "'내 다른 브랜치' 절에는 뜸"                   "printf '%s' \"\$d\" | grep -A2 '내 다른 브랜치' | grep -q 'feat/second'"
check "겹침 목록에 내 브랜치가 안 섞임"              "! printf '%s' \"\$d\" | sed -n '/지금 같은 파일/,\$p' | grep -q '@solp'"
check "check 겹침에도 내 브랜치 제외"                "! col solp check 2>&1 | grep '다른 열린 브랜치' | grep -q '@solp'"

git checkout -q components/ui/button.tsx
echo "# 저널 정정 supersedes (보고 7번)"
cd "$R/amazon" && git switch -q feat/again 2>/dev/null
printf '# 정정\n\n## 이벤트\n- supersedes lib/api/user.ts 반환형은 되돌렸다. 앞 지침 무효\n\n## 남은 것\n- 없음\n' > "collab/journal/$today-amazon-feat--again-2.md"
git add -A && git commit -qm supersede >/dev/null && git push -q origin HEAD
cd "$R/solp" && git switch -q feat/other 2>/dev/null || git switch -q feat/checkout
check "supersedes 뒤에는 낡은 이벤트가 안 뜸"        "! col solp digest --fetch | grep -q '반환형 변경'"

echo "# 스택 브랜치 base (보고 4번)"
cd "$R/solp" && git switch -qc feat/stacked feat/second 2>/dev/null && mkdir -p collab/active/feat--stacked
printf -- '---\nbranch: feat/stacked\nowner: solp\nstarted: %s\nstatus: active\ngoal: 스택\nbase: feat/second\n---\n' "$today" > collab/active/feat--stacked/claim.md
printf '# s\n\n## 이벤트\n- added app/checkout/stacked.tsx x\n\n## 남은 것\n- 없음\n' > "collab/journal/$today-solp-feat--stacked.md"
echo s > app/checkout/stacked.tsx && git add -A && git commit -qm stacked >/dev/null
check "base 를 쓰면 아래 브랜치 claim 이 위반으로 안 잡힘" "col solp check >'$R/chk' 2>&1 || { sed 's/^/     /' '$R/chk'; false; }"
check "check 가 base 를 표시"                        "grep -q 'base origin/feat/second' '$R/chk'"

echo "# PR 본문 (보고 2·3번)"
b="$(col solp pr-body)"
check "본문 앞쪽이 goal·변경 요약·검증"              "printf '%s' \"\$b\" | grep -q '## 변경 요약' && printf '%s' \"\$b\" | grep -q '## 검증'"
check "이벤트는 details 로 접힘"                     "printf '%s' \"\$b\" | grep -q '<details><summary>동료 에이전트용 이벤트'"
check "스택 PR 은 base 를 본문에 알림"               "printf '%s' \"\$b\" | grep -q '스택 PR'"
check "어떤 줄도 200자를 넘지 않음"                  "[ \"\$(printf '%s' \"\$b\" | awk '{print length}' | sort -rn | head -1)\" -lt 200 ]"

echo "# 머지된 브랜치 (보고 8번, 새 발견)"
cd "$R/amazon" && git switch -q main && git fetch -q origin && git pull -q --ff-only origin main 2>/dev/null; git merge -q --squash origin/feat/second && git commit -qm "feat: second (squash)" >/dev/null && git push -q origin main
cd "$R/solp" && git switch -q feat/second && git fetch -q origin
check "digest 가 머지됐다고 경고"                    "col solp digest --fetch | grep -q '이미 머지됐습니다'"
check "pulse 가 따라잡지 않고 알림"                  "col solp pulse | grep -q '이미 머지됐습니다'"
echo extra >> components/ui/button.tsx && git add -A && git commit -qm "머지 뒤 추가 커밋" >/dev/null
check "pre-push 가 push 를 막음"                     "! sh scripts/collab.sh prepush </dev/null >/dev/null 2>'$R/err'; grep -q '이미 머지됐습니다' '$R/err'"
check "COLLAB_ALLOW_MERGED_PUSH=1 이면 통과"          "COLLAB_ALLOW_MERGED_PUSH=1 sh scripts/collab.sh prepush </dev/null >/dev/null 2>&1"
git switch -q feat/checkout

echo "# check 와 stop"
cd "$R/solp" && git switch -q feat/checkout && rm -f app/checkout/x.ts
check "check: 다른 열린 브랜치와 같은 파일 알림" "col solp check | grep -q 'button.tsx(@amazon)' || col solp check | grep -q 'user.ts(@amazon)'"
cd "$R/solp" && rm -f "collab/journal/$today-solp-"*.md && git add -A && { git commit -qm rmj || true; } && echo n > app/checkout/n.tsx
out="$(printf '{"stop_hook_active":false}' | hook solp stop)"
check "stop: 변경 있고 저널 없음 → block"     "printf '%s' \"\$out\" | grep -q '\"decision\":\"block\"'"
[ $fail -gt 0 ] && { echo "     진단: branch=$(git rev-parse --abbrev-ref HEAD) 오늘저널=[$(ls collab/journal/$today-solp-*.md 2>/dev/null | tr '\n' ' ')] my_files=[$( . harness/hooks/lib.sh; my_files | tr '\n' ' ' | cut -c1-120)] out=[$out]"; }
echo; echo "통과 $pass / 실패 $fail"; [ $fail -eq 0 ]
