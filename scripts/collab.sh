#!/bin/sh
# 협업 하네스 도구. 훅과 같은 lib.sh 를 쓴다. 사람도, 훅도, 다른 하네스도, CI 도 이것만 부른다.
#
#   state                       온보딩 상태: setup(프로젝트 초기화 필요) | join(합류: 개인 설정만) | ready. 감지 정보도 함께
#   digest [--fetch] [--json]   협업 현황. 세션 시작 훅이 주입하는 것과 동일. 내 시점으로 좁혀서
#   pulse                       내 작업 트리 스냅샷 올리기 + 원격 당겨오기. 새 겹침·새 이벤트·main 변경(자동 rebase)만 출력
#   guard <path> | --allow <path>   쓰기 판정(exit 2 = 차단). --allow 는 이 세션에서 그 경로의 허브 차단을 해제
#   check [--base REF]          PR 규칙 검사. 위반 시 exit 1. CI 와 handoff 가 사용
#   run -- <명령...>            sobaya 루프처럼 워커가 파일을 고치는 명령을 감싼다. 전: 동료가 편집 중인 허브 파일이면 중단. 후: 워커가 건드린 허브 파일 보고
#   worktree <branch>           sobaya 승인이 이 클론에 있으면 새 브랜치를 워크트리로 연다 (승인 상태가 git-dir 당 하나라 브랜치 전환이 깨짐)
#   prune                       main 전용. 머지·소멸 브랜치의 claim 삭제
#   wip                         git post-commit 이 부른다. 작업 트리 스냅샷 push + fetch + 새 겹침 경고(stderr). 자동 따라잡기 없음
#   pr-body                     PR 본문 생성 (claim goal, 저널 이벤트, 겹친 파일, 검증 칸). handoff 가 gh pr create 에 쓴다
#   precommit                   git pre-commit 이 부른다. 스테이지된 파일마다 guard 와 같은 판정 (도구가 무엇이든)
#   prepush                     git pre-push 가 부른다. 보호 브랜치로의 push 차단, 저널 없는 push 경고
set -u
HERE="$(cd "$(dirname "$0")" && pwd -P)"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$HERE/.." && pwd -P)}"
. "$CLAUDE_PROJECT_DIR/harness/hooks/lib.sh"
cd "$ROOT" || exit 1
ME="$(me)"; BR="$(current_branch)"; MAIN="$(main_ref || true)"

# ---- 헬퍼 ------------------------------------------------------------------
do_fetch() { g fetch -q --prune origin '+refs/heads/*:refs/remotes/origin/*' '+refs/wip/*:refs/wip/*' >/dev/null 2>&1 & pid=$!
  i=0; while kill -0 $pid 2>/dev/null && [ $i -lt "${1:-8}" ]; do sleep 1; i=$((i+1)); done
  if kill -0 $pid 2>/dev/null; then kill $pid 2>/dev/null; return 1; fi; wait $pid; }
unmerged_files() { if [ -n "$MAIN" ]; then g diff --name-only --diff-filter=A "$MAIN...$1" -- "$2" 2>/dev/null; else g ls-tree -r --name-only "$1" -- "$2" 2>/dev/null; fi | grep -v '/README\.md$'; }
journal_owner() { basename "$1" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-([^-]+)-.*/\1/'; }
my_last_journal_date() { ls "$JOURNAL_DIR"/*-"$ME"-*.md 2>/dev/null | sort | tail -n1 | xargs -I{} basename {} | cut -c1-10; }
SEEN="$(branch_cache seen)"; ASKED="$(branch_cache asked)"; OVPREV="$(branch_cache overlaps.prev)"
seen() { [ -f "$SEEN" ] && grep -qxF "$1" "$SEEN"; }
mark_seen() { echo "$1" >> "$SEEN"; }
event_id() { printf '%s' "$1" | cksum | cut -d' ' -f1; }
# 이벤트 줄 "- <type> <path?> <text>" → "type<TAB>path<TAB>text" (path 는 / 또는 . 을 포함한 두 번째 토큰)
parse_event() { sed 's/^[[:space:]]*-[[:space:]]*//' | awk '{
  t=$1; p="-"; s=2; if ($2 ~ /\// && $2 !~ /^@/) { p=$2; s=3 }
  txt=""; for (i=s;i<=NF;i++) txt=txt (i>s?" ":"") $i; printf "%s\t%s\t%s\n", t, p, txt }'; }
# 내 파일이 이 경로를 import 하는가 (확장자 뗀 경로의 마지막 두 조각으로 grep)
imported_by_me() {  # 내 파일이 그 경로를 import 하는가. 직접(dir/file), 디렉토리 배럴(dir), 파일명 순으로 넓혀 본다. 미탐보다 오탐이 낫다
  [ -n "$MYF" ] || return 1; base="$(printf '%s' "$1" | sed -E 's/\.[a-zA-Z]+$//; s#/index$##')"
  dir="$(dirname "$base")"; file="$(basename "$base")"; keys="$base"
  [ "$dir" != "." ] && keys="$keys
$dir
$(basename "$dir")/$file"
  printf '%s\n' "$keys" | sort -u | while IFS= read -r k; do [ -n "$k" ] || continue
    printf '%s\n' "$MYF" | xargs grep -lE -- "from ['\"][^'\"]*$k(/[^'\"]*)?['\"]|require\(['\"][^'\"]*$k" 2>/dev/null | grep -q . && echo hit; done | grep -q hit; }
# 이벤트가 나에게 영향 있는가: type, path
affects_me() { case "$1" in
  changed|migrated|removed) [ "$2" != "-" ] && { printf '%s\n' "$MYF" | grep -qx "$2" || imported_by_me "$2"; } ;;
  added|dep|rule) return 0 ;;
  touching) [ "$2" != "-" ] && printf '%s\n' "$MYF" | grep -qx "$2" ;;
  *) return 1 ;; esac; }
# 다른 사람 저널들: "ref<TAB>path<TAB>branch<TAB>owner" (미머지 브랜치 저널 전부 + main 의 최근 저널)
other_journals() {
  _oj() { for j in $(unmerged_files "$3" "$JOURNAL_DIR"); do printf '%s\t%s\t%s\t%s\n' "$3" "$j" "$1" "$(journal_owner "$j")"; done; }; for_each_other_claim _oj
  cut="$(cutoff_date)"; [ -n "$MAIN" ] && for j in $(g ls-tree -r --name-only "$MAIN" -- "$JOURNAL_DIR" 2>/dev/null | grep -v README); do
    [ "$(basename "$j" | cut -c1-10)" \< "$cut" ] && continue; o="$(journal_owner "$j")"; [ "$o" = "$ME" ] && continue
    printf '%s\t%s\t%s\t%s\n' "$MAIN" "$j" "main" "$o"; done
}
# 내가 답했는가: 내 저널에 "reply @owner" 가 ask 저널 날짜 이후에 있는가
replied() { for j in $(ls "$JOURNAL_DIR"/*-"$ME"-*.md 2>/dev/null); do [ "$(basename "$j" | cut -c1-10)" \< "$2" ] && continue; grep -qE "^[[:space:]]*-[[:space:]]*reply[[:space:]]+@$1\b" "$j" && return 0; done; return 1; }
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
jarr() { first=1; printf '['; while IFS= read -r x; do [ -z "$x" ] && continue; [ $first = 1 ] || printf ','; first=0; printf '"%s"' "$(esc "$x")"; done; printf ']'; }

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in

state)
  # 리터럴을 쪼개 둔다 — init.sh 의 치환이 이 코드까지 바꾸면 안 되니까
  ob='{'; cb='}'; ph=0; grep -q "$ob${ob}PROJECT_NAME$cb$cb\|$ob${ob}OWNER$cb$cb" AGENTS.md 2>/dev/null && ph=1
  handle="$(g config collab.me 2>/dev/null || true)"; hooks="$( [ "$(g config core.hooksPath 2>/dev/null)" = .githooks ] && echo on || echo off)"
  remote="$(g remote get-url origin 2>/dev/null || true)"; sr="$(sobaya_root 2>/dev/null || true)"; lk="$(sobaya_lock)"
  ghok="$(command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && echo yes || echo no)"
  testcmd="$(sed -n 's/^- Test:[[:space:]]*//p' AGENTS.md 2>/dev/null | head -n1)"
  if [ "$(g config collab.onboarded 2>/dev/null)" = true ]; then st=ready
  elif [ $ph = 1 ]; then st=setup
  elif [ -z "$handle" ] || [ "$hooks" = off ] || { [ -n "$lk" ] && [ -n "$sr" ] && [ "$(git -C "$sr" rev-parse HEAD 2>/dev/null)" != "$lk" ]; }; then st=join
  else st=ready; fi
  printf 'state=%s\nrepo=%s\nremote=%s\nplaceholders=%s\nhandle=%s\nhooks=%s\nsobaya=%s\nsobaya_lock=%s\ngh=%s\ntest=%s\n' \
    "$st" "$(basename "$ROOT")" "${remote:--}" "$ph" "${handle:--}" "$hooks" "${sr:--}" "${lk:--}" "$ghok" "${testcmd:--}" ;;

digest)
  fetch_note=""; json=0; for a in "$@"; do case "$a" in --fetch) do_fetch 8 && fetch_note="원격 갱신됨" || fetch_note="원격 갱신 실패 — 동료 상태가 오래됐을 수 있음" ;; --json) json=1 ;; esac; done
  wip_table; MYF="$(my_files)"; MINE="$(claim_path_for "$BR")"; lastj="$(my_last_journal_date)"
  # 수집: asks, events, others, overlaps → 임시 파일
  A="$CACHE/_asks"; E="$CACHE/_events"; O="$CACHE/_others"; V="$CACHE/_overlaps"; : > "$A"; : > "$E"; : > "$O"; : > "$V"
  : > "$CACHE/_ids"
  other_journals | sort -t"$TAB" -k2 | while IFS="$TAB" read -r ref j b o; do
    jd="$(basename "$j" | cut -c1-10)"; tmp="$(mktemp)"; g show "$ref:$j" > "$tmp" 2>/dev/null
    md_section "$tmp" "이벤트" | while IFS= read -r line; do
      id="$(event_id "$j|$line")"; grep -qxF "$id" "$CACHE/_ids" && continue; echo "$id" >> "$CACHE/_ids"; ev="$(printf '%s\n' "$line" | parse_event)"; t="${ev%%$TAB*}"; rest="${ev#*$TAB}"; p="${rest%%$TAB*}"; txt="${rest#*$TAB}"
      if [ "$t" = ask ] && printf '%s' "$txt" | grep -q "@$ME\b"; then replied "$o" "$jd" || printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$b" "$o" "$j" "$txt" >> "$A"; continue; fi
      printf '%s' "$txt" | grep -q "@$ME\b" && { seen "$id" || printf '%s\t%s\t%s\t%s\t%s %s\n' "$id" "$b" "$o" "$j" "$t" "$txt" >> "$A"; continue; }
      seen "$id" && continue; affects_me "$t" "$p" || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$b" "$o" "$j" "$t" "$p" "$txt" >> "$E"
    done; rm -f "$tmp"
  done
  _others() { o="$(claim_get "$2" owner)"; st="$(claim_get "$2" status)"; slug="$(branch_slug "$1")"; unc=""; com=""; age=""
    [ -f "$CACHE/wip.tsv" ] && line="$(grep "^$o$TAB$slug$TAB" "$CACHE/wip.tsv" | head -n1)" && [ -n "$line" ] && { age="$(printf '%s' "$line" | cut -f3)"; unc="$(printf '%s' "$line" | cut -f4)"; com="$(printf '%s' "$line" | cut -f5)"; }
    last="$(g log -1 --format=%cr "$3" 2>/dev/null)"; days=$(( ( $(now_epoch) - $(g log -1 --format=%ct "$3" 2>/dev/null || echo 0) ) / 86400 ))
    nxt="$(claim_get "$2" next)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "${o:--}" "${st:-active}" "$(claim_get "$2" goal)" "${age:--}" "${unc:--}" "${com:--}" "${last:--}$( [ $days -ge 14 ] && echo ' · 방치?')" "${nxt:--}" >> "$O"
    for f in $unc; do [ "$f" = "-" ] && continue; printf '%s\n' "$MYF" | grep -qx "$f" && printf '%s\t%s\t%s\t%s\n' "$f" "$o" "$age" "$( is_hotspot "$f" && echo hotspot || echo file)" >> "$V"; done
    for f in $com; do [ "$f" = "-" ] && continue; printf '%s\n' "$MYF" | grep -qx "$f" && printf '%s\t%s\t%s\t%s\n' "$f" "$o" "$age" "committed" >> "$V"; done
    for f in $nxt; do case "$f" in */*|*.*) printf '%s\n' "$MYF" | grep -qx "$f" && printf '%s\t%s\t%s\t%s\n' "$f" "$o" "-" "next" >> "$V" ;; esac; done; }
  for_each_other_claim _others
  if [ $json = 1 ]; then
    printf '{"me":"%s","branch":"%s","claim":' "$(esc "$ME")" "$(esc "$BR")"
    if [ -f "$MINE" ]; then printf '{"goal":"%s","status":"%s","owner":"%s"}' "$(esc "$(claim_get "$MINE" goal)")" "$(esc "$(claim_get "$MINE" status)")" "$(esc "$(claim_get "$MINE" owner)")"; else printf 'null'; fi
    printf ',"asks":['; f=1; while IFS="$TAB" read -r id b o j txt; do [ $f = 1 ] || printf ','; f=0; printf '{"id":"%s","from":"%s","branch":"%s","text":"%s","journal":"%s"}' "$id" "$(esc "$o")" "$(esc "$b")" "$(esc "$txt")" "$(esc "$j")"; done < "$A"
    printf '],"events":['; f=1; while IFS="$TAB" read -r id b o j t p txt; do [ $f = 1 ] || printf ','; f=0; printf '{"type":"%s","path":"%s","text":"%s","from":"%s","branch":"%s"}' "$(esc "$t")" "$(esc "$p")" "$(esc "$txt")" "$(esc "$o")" "$(esc "$b")"; done < "$E"
    printf '],"others":['; f=1; while IFS="$TAB" read -r b o st goal age unc com last nxt; do [ $f = 1 ] || printf ','; f=0; printf '{"branch":"%s","owner":"%s","status":"%s","goal":"%s","wip_age":%s,"editing":%s,"committed":%s,"last_commit":"%s","next":"%s"}' "$(esc "$b")" "$(esc "$o")" "$(esc "$st")" "$(esc "$goal")" "$( [ "$age" = "-" ] && echo null || echo "$age")" "$( [ "$unc" = "-" ] && echo '[]' || printf '%s\n' $unc | jarr)" "$( [ "$com" = "-" ] && echo '[]' || printf '%s\n' $com | jarr)" "$(esc "$last")" "$(esc "$nxt")"; done < "$O"
    printf '],"overlaps":['; f=1; while IFS="$TAB" read -r fpath o age kind; do [ $f = 1 ] || printf ','; f=0; printf '{"path":"%s","owner":"%s","wip_age":%s,"kind":"%s"}' "$(esc "$fpath")" "$(esc "$o")" "$age" "$kind"; done < "$V"
    printf ']}\n'
  else
    echo "# 협업 현황 (자동 주입) · 나: @$ME · 브랜치: ${BR:-?}${fetch_note:+ · $fetch_note}"
    [ "$(g config --get core.hooksPath 2>/dev/null)" = ".githooks" ] || echo "! git 훅이 꺼져 있습니다 → git config core.hooksPath .githooks (커밋·push 검사가 도구와 무관하게 걸린다)"
    echo; echo "## 나에게 온 질문·메시지 (답은 내 저널 이벤트에 'reply @상대' 로)"
    if [ -s "$A" ]; then while IFS="$TAB" read -r id b o j txt; do echo "- @$o ($b): $txt"; done < "$A"; else echo "- 없음"; fi
    echo; echo "## 내 claim"
    if is_protected_branch "$BR"; then echo "- 보호 브랜치. 코드 수정은 차단됩니다. 작업 시작은 start-work 스킬."
    elif [ -f "$MINE" ]; then echo "- $(claim_get "$MINE" goal) · status $(claim_get "$MINE" status)"; o="$(claim_get "$MINE" owner)"; [ "$o" != "$ME" ] && echo "- 주의: 이 claim 의 owner 는 @$o. 이어받는 것이면 start-work 스킬 의 '이어받기'."
    else echo "- 없음. 파일 수정 전에 start-work 스킬 로 선언하세요 (훅이 차단합니다)."; fi
    echo; echo "## 동료가 바꾼 것 중 나에게 영향 있는 이벤트"
    if [ -s "$E" ]; then while IFS="$TAB" read -r id b o j t p txt; do echo "- [$t] ${p#-}${p:+ }$txt  (@$o, $b)"; mark_seen "$id"; done < "$E"
      echo "  → changed/migrated/removed 는 내 코드가 깨졌을 수 있다는 뜻. 작업 전에 해당 호출부를 확인한다. added 는 중복 구현 금지. rule 은 따른다."
    else echo "- 없음"; fi
    echo; echo "## 동료 작업 중"
    if [ -s "$O" ]; then while IFS="$TAB" read -r b o st goal age unc com last nxt; do echo "- $b · @$o · $st · $goal · 마지막 커밋 $last"
        [ "$unc" != "-" ] && echo "  지금 편집 중 ($(fmt_age "$age")): $unc"
        [ "$com" != "-" ] && echo "  브랜치에 커밋됨(미머지): $com"
        [ "$nxt" != "-" ] && echo "  다음에 만질 것: $nxt"; done < "$O"; else echo "- 없음"; fi
    if sr="$(sobaya_root)"; then lk="$(sobaya_lock)"; hd="$(git -C "$sr" rev-parse --short HEAD 2>/dev/null)"
      echo; echo "## 개발 하네스 (sobaya)"
      if [ -z "$lk" ]; then echo "- sobaya 워크스페이스 감지($sr). 아직 붙이지 않음 → sh harness/attach-sobaya.sh attach"
      elif [ "$(git -C "$sr" rev-parse HEAD 2>/dev/null)" != "$lk" ]; then echo "- 내 sobaya($hd)가 팀이 검증한 버전(${lk%"${lk#???????}"})과 다릅니다 → sh harness/attach-sobaya.sh sync"
      else echo "- sobaya $hd · 팀 검증 버전과 일치$( sobaya_approved && echo ' · 이 브랜치는 승인 상태 있음(main 따라잡기는 merge)')"; fi
    fi
    echo; echo "## 지금 같은 파일을 만지는 중"
    if [ -s "$V" ]; then while IFS="$TAB" read -r fpath o age kind; do case "$kind" in
        hotspot) echo "- $fpath ← @$o 편집 중 ($(fmt_age "$age")) · 허브 파일: 차단됨. 상대가 커밋하면 풀린다" ;;
        file) echo "- $fpath ← @$o 편집 중 ($(fmt_age "$age"))" ;;
        committed) echo "- $fpath ← @$o 브랜치에 커밋됨(미머지). 먼저 머지되는 쪽이 이기고 나중 쪽이 따라잡는다 — 공유 파일이면 작은 선행 PR 로 먼저 머지하자고 제안" ;;
        next) echo "- $fpath ← @$o 가 다음에 만질 예정(claim next:). 지금 내가 끝내고 머지하거나, 상대와 순서를 맞춘다" ;; esac; done < "$V"
      echo "  → 같은 부분을 고치는 것 같으면 사용자에게 알린다. 작게 커밋하고 자주 push 한다."
    else echo "- 없음"; fi
  fi
  rm -f "$A" "$E" "$O" "$V" "$CACHE/_ids"; now_epoch > "$CACHE/pulse.at" ;;

pulse)
  is_protected_branch "$BR" && exit 0
  [ -f "$OVPREV" ] || : > "$OVPREV"
  wip_push; do_fetch 5 || { now_epoch > "$CACHE/pulse.at"; exit 0; }
  out=""; wip_table; MYF="$(my_files)"
  # 직전 pulse 와 비교한다. 사라졌다 다시 생긴 편집 겹침은 새 알림이다.
  ovnext="$OVPREV.next"; : > "$ovnext"
  new=""; [ -f "$CACHE/wip.tsv" ] && while IFS="$TAB" read -r o slug age unc com; do
    for f in $unc; do [ "$f" = "-" ] && continue; printf '%s\n' "$MYF" | grep -qx "$f" || continue
      echo "$f@$o/$slug" >> "$ovnext"; grep -qxF "$f@$o/$slug" "$OVPREV" && continue; new="$new
- 겹침: $f 를 @$o($slug) 도 지금 편집 중 ($(fmt_age "$age"))$( is_hotspot "$f" && echo ' · 허브 파일이라 이제부터 차단됨')"; done
    for f in $com; do [ "$f" = "-" ] && continue; printf '%s\n' "$MYF" | grep -qx "$f" || continue
      echo "$f@$o/$slug:c" >> "$ovnext"; grep -qxF "$f@$o/$slug:c" "$OVPREV" && continue; new="$new
- 겹침(커밋됨): $f 를 @$o($slug) 브랜치가 이미 바꿨습니다. 머지 때 만납니다 — 공유 파일이면 작은 선행 PR 을 제안하세요"; done; done < "$CACHE/wip.tsv"
  mv "$ovnext" "$OVPREV"
  [ -n "$new" ] && out="$out$new"
  # 새 이벤트·질문 (digest 와 같은 필터, seen 제외)
  ev="$(sh "$0" digest --json 2>/dev/null)"
  if command -v jq >/dev/null 2>&1 && [ -n "$ev" ]; then
    touch "$ASKED"
    a="$(printf '%s' "$ev" | jq -r '.asks[] | "\(.id)\t- 질문 @\(.from): \(.text)"' 2>/dev/null | while IFS="$TAB" read -r id line; do grep -qxF "$id" "$ASKED" && continue; echo "$id" >> "$ASKED"; echo "$line"; done)"
    [ -n "$a" ] && out="$out
$a"
    e="$(printf '%s' "$ev" | jq -r '.events[] | "- [\(.type)] \(.path|sub("^-$";"")) \(.text) (@\(.from))"' 2>/dev/null)"
    if [ -n "$e" ]; then out="$out
$e"; sh "$0" digest >/dev/null 2>&1; fi   # 텍스트 digest 를 한 번 돌려 seen 에 기록
  fi
  # main 보다 뒤처졌으면 따라잡는다 (origin/main 이 언제 바뀌었든, 내 HEAD 에 아직 없으면)
  if [ -n "$MAIN" ]; then newmain="$(g rev-parse "$MAIN" 2>/dev/null)"
    if [ -n "$newmain" ] && ! g merge-base --is-ancestor "$newmain" HEAD 2>/dev/null; then
      mb="$(g merge-base HEAD "$newmain" 2>/dev/null)"; printf '%s\n' "$MYF" > "$CACHE/_myf"
      hit="$(g diff --name-only "$mb" "$newmain" 2>/dev/null | grep -Fx -f "$CACHE/_myf" 2>/dev/null | tr '\n' ' ')"; rm -f "$CACHE/_myf"
      mode="$(sync_mode)"
      if sobaya_busy; then [ "$(cat "$CACHE/main.notified" 2>/dev/null)" != "$newmain" ] && { echo "$newmain" > "$CACHE/main.notified"; out="$out
- main 이 갱신됐지만 sobaya 가 항목을 진행 중이라 따라잡기를 보류합니다.${hit:+ 내 파일과 겹침: $hit.} 루프가 끝나면 다음 pulse 가 합니다."; }
      elif [ "$AUTO_REBASE" = true ] && tree_clean; then
        if [ "$mode" = merge ]; then ok_sync() { g merge -q --no-edit "$MAIN" >/dev/null 2>&1; }; undo_sync() { g merge --abort >/dev/null 2>&1; }
        else ok_sync() { g rebase -q --autostash "$MAIN" >/dev/null 2>&1; }; undo_sync() { g rebase --abort >/dev/null 2>&1; }; fi
        if ok_sync; then out="$out
- main 이 갱신되어 자동으로 $mode 했습니다.${hit:+ 내 파일과 겹친 변경: $hit — 다시 확인하세요.}$( [ "$mode" = merge ] && echo ' (sobaya 승인 브랜치라 rebase 대신 merge)')"
        else files="$(g diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')"; undo_sync
          out="$out
- main 과 충돌: $files. 자동 $mode 를 되돌렸습니다. 사용자에게 알리고, 상대 저널의 이벤트를 참고해 'git $mode $MAIN' 으로 직접 해결하세요."; fi
      elif [ "$(cat "$CACHE/main.notified" 2>/dev/null)" != "$newmain" ]; then echo "$newmain" > "$CACHE/main.notified"
        out="$out
- main 이 갱신됐습니다.${hit:+ 내 파일과 겹침: $hit.} 커밋한 뒤 'git $mode $MAIN' 하세요 (작업 트리가 깨끗하면 다음 pulse 가 자동으로 합니다)."; fi
    fi
  fi
  now_epoch > "$CACHE/pulse.at"; [ -n "$out" ] && printf '%s\n' "$out" | sed '/^$/d' ;;

wip)
  is_protected_branch "$BR" && exit 0; [ -f "$(claim_path_for "$BR")" ] || exit 0
  wip_push; g rev-parse -q --verify "@{upstream}" >/dev/null 2>&1 && g push -q origin HEAD >/dev/null 2>&1
  do_fetch 5 || exit 0; wip_table; MYF="$(my_files)"
  [ -f "$CACHE/wip.tsv" ] && while IFS="$TAB" read -r o slug age unc com; do for f in $unc $com; do [ "$f" = "-" ] && continue
    printf '%s\n' "$MYF" | grep -qx "$f" && echo "협업: $f 를 @$o($slug) 도 바꾸는 중" >&2; done; done < "$CACHE/wip.tsv"; exit 0 ;;
pr-body)
  cp="$(claim_path_for "$BR")"; goal="$( [ -f "$cp" ] && claim_get "$cp" goal)"
  echo "## 무엇을"; echo "${goal:-<claim goal>}"; echo
  echo "## 동료가 알아야 할 이벤트"
  for j in $(ls "$JOURNAL_DIR"/*-"$ME"-*.md 2>/dev/null | sort); do g cat-file -e "$( [ -n "$MAIN" ] && echo "$MAIN" || echo HEAD):$j" 2>/dev/null && continue; md_section "$j" "이벤트" | grep -E '^\s*-\s*(changed|added|removed|migrated|dep|rule)\b'; done | sed 's/^[[:space:]]*//' | sort -u | sed 's/^/- /; s/^- - /- /' | grep . || echo "- 없음"
  echo; echo "## 다른 열린 브랜치와 겹친 파일"; ov="$(sh "$0" check 2>/dev/null | sed -n 's/^! 다른 열린 브랜치와 같은 파일을 바꿈://p')"; echo "${ov:-없음}"
  sd="$(g rev-parse --absolute-git-dir 2>/dev/null)/sobaya/state.json"; [ -f "$sd" ] && command -v jq >/dev/null && { echo; echo "## sobaya"; echo "- review 바인딩 HEAD: $(jq -r '.review.head // "없음"' "$sd" 2>/dev/null | cut -c1-7) · 현재 HEAD: $(g rev-parse --short HEAD)"; }
  echo; echo "## 검증"; echo "<!-- 실제로 돌린 것만 -->"; exit 0 ;;
run)
  [ "${1:-}" = "--" ] && shift; [ $# -gt 0 ] || { echo "사용: collab.sh run -- <명령...>"; exit 1; }
  is_protected_branch "$BR" && { echo "보호 브랜치($BR)에서는 워커를 돌리지 않습니다. start-work 스킬로 브랜치와 claim 을 만드세요." >&2; exit 1; }
  [ -f "$(claim_path_for "$BR")" ] || { echo "claim 이 없습니다. start-work 스킬 먼저." >&2; exit 1; }
  do_fetch 5 >/dev/null 2>&1; wip_table
  busy=""; for h in $HOTSPOTS; do w="$(editing_now "$h")"; [ -n "$w" ] && busy="$busy
- $h ← $(printf '%s' "$w" | awk -F"$TAB" '{printf "@%s(%s) ", $1, $2}')편집 중"; done
  if [ -n "$busy" ] && [ -z "${COLLAB_RUN_FORCE:-}" ]; then
    printf '중단: 동료가 지금 편집 중인 허브 파일이 있습니다. 워커는 훅을 거치지 않아 같은 파일을 고치면 머지 충돌이 납니다.%s\n상대가 커밋하면 풀립니다. 그래도 돌리려면 COLLAB_RUN_FORCE=1.\n' "$busy" >&2; exit 1; fi
  before="$(g rev-parse HEAD 2>/dev/null)"; "$@"; rc=$?
  wip_push >/dev/null 2>&1; wip_table
  touched="$( { g diff --name-only "$before" HEAD 2>/dev/null; g status --porcelain 2>/dev/null | awk '{print $NF}'; } | sort -u)"
  hot=""; for f in $touched; do is_hotspot "$f" && hot="$hot $f"; done
  if [ -n "$hot" ]; then echo "협업: 워커가 허브 파일을 건드렸습니다:$hot" >&2
    for f in $hot; do w="$(touching_now "$f")"; [ -n "$w" ] && echo "  ⚠ $f 는 $(printf '%s' "$w" | awk -F"$TAB" '{printf "@%s(%s, %s) ", $1, $2, $4}')도 바꾸는 중 — 머지 때 충돌. 작은 선행 PR 로 먼저 머지하거나 상대와 순서를 정하세요." >&2; done
    echo "  → 저널 이벤트에 changed/migrated 로 남기고, 사용자에게 알리세요." >&2; fi
  exit $rc ;;
worktree)
  b="${1:-}"; [ -n "$b" ] || { echo "사용: collab.sh worktree <branch>"; exit 1; }
  [ -n "$MAIN" ] || { echo "origin/main 이 없습니다"; exit 1; }
  dir="$(dirname "$ROOT")/$(basename "$ROOT")-$(branch_slug "$b")"
  if sobaya_approved; then echo "이 클론에 sobaya 승인 상태가 있어 새 브랜치는 워크트리로 엽니다: $dir"; else echo "워크트리로 엽니다: $dir"; fi
  g worktree add -q "$dir" -b "$b" "$MAIN" || exit 1
  git -C "$dir" config collab.me "$ME" >/dev/null 2>&1; git -C "$dir" config core.hooksPath .githooks >/dev/null 2>&1
  echo "다음: cd $dir 에서 세션을 열고 start-work 를 이어서 (claim 작성·push). sobaya 는 그 디렉토리를 앱으로 지정해 실행."; exit 0 ;;
guard)
  if [ "${1:-}" = "--allow" ]; then echo "$2" >> "$CACHE/allow"; echo "이 세션에서 $2 허용"; exit 0; fi
  p="$(rel_path "${1:-}")" || exit 0; check_write "$p" && exit 0; printf '%s\n' "$REASON" >&2; exit 2 ;;

check)
  base="$MAIN"; [ "${1:-}" = "--base" ] && base="$2"; [ -n "$base" ] || { echo "base 브랜치를 찾을 수 없음"; exit 1; }
  branch="${GITHUB_HEAD_REF:-$BR}"; cp="$(claim_path_for "$branch")"; viol=""; V() { viol="$viol$1
"; }
  is_protected_branch "$branch" && { echo "보호 브랜치 — 검사 생략"; exit 0; }
  mb="$(g merge-base "$base" HEAD 2>/dev/null)" || { echo "merge-base 없음: $base"; exit 1; }
  changed="$(g diff --name-status "$mb" HEAD)"; files="$(printf '%s\n' "$changed" | awk '{print $2}')"
  if [ -f "$cp" ]; then for k in branch owner goal status; do [ -n "$(claim_get "$cp" "$k")" ] || V "$cp: '$k:' 비어 있음"; done
    [ "$(branch_slug "$(claim_get "$cp" branch)")" = "$(basename "$(dirname "$cp")")" ] || V "$cp: branch 가 디렉토리명과 다름"
    case "$(claim_get "$cp" status)" in active|paused|done) ;; *) V "$cp: status 는 active|paused|done" ;; esac
  else V "claim 없음: $cp (start-work 스킬)"; fi
  journals="$(printf '%s\n' "$changed" | awk '$1=="A"{print $2}' | grep "^$JOURNAL_DIR/[^/]*\.md$" | grep -v README || true)"
  [ -n "$journals" ] || V "저널 없음. $JOURNAL_DIR/ 에 새 파일 (handoff 스킬)"
  for j in $journals; do for h in "이벤트" "남은 것"; do grep -q "^## $h" "$j" || V "$j: '## $h' 절 없음"; done
    basename "$j" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[^-]+-' || V "$j: 파일명은 YYYY-MM-DD-<owner>-<slug>.md"; done
  printf '%s\n' "$changed" | awk '$1~/^[MD]/{print $2}' | grep -q "^$JOURNAL_DIR/.*\.md$" && V "기존 저널을 수정/삭제함 (append-only)"
  # sobaya 의 브랜치 산출물(spec.md, failed-test.md)이 main 으로 가면 다음 브랜치와 충돌한다
  for f in spec.md failed-test.md; do printf '%s\n' "$files" | grep -qx "$f" && V "$f 가 PR 에 포함됨. handoff 의 'plan 보관' 절차로 collab/journal/plans/ 에 옮기고 루트에서 지울 것"; done
  others="$(printf '%s\n' "$files" | grep "^$CLAIM_DIR/" | grep -v "^$(claim_dir_for "$branch")/" | grep -v README || true)"; [ -n "$others" ] && V "다른 브랜치의 claim 을 건드림: $(echo "$others" | tr '\n' ' ')"
  agent=false; g log --format='%(trailers:key=Assisted-by,valueonly)' "$mb..HEAD" 2>/dev/null | grep -q . && agent=true
  # 다른 열린 브랜치와 같은 파일을 바꿨는가 (정보)
  ov=""; _ov() { for f in $(g diff --name-only "$(g merge-base "$base" "$3")" "$3" 2>/dev/null | grep -v '^collab/'); do printf '%s\n' "$files" | grep -qx "$f" && ov="$ov $f(@$(claim_get "$2" owner))"; done; }; for_each_other_claim _ov
  echo "검사: $branch (base $base)"
  [ -n "$viol" ] && printf '%s' "$viol" | sed 's/^/✗ /' || echo "✓ 규칙 위반 없음"
  [ -n "$ov" ] && echo "! 다른 열린 브랜치와 같은 파일을 바꿈:$ov — 먼저 머지되는 쪽이 이기고 나중 쪽이 rebase 한다"
  echo "  에이전트 커밋: $agent"
  [ -z "$viol" ] && echo "통과" || { echo "위반 있음"; exit 1; } ;;

prune)
  is_protected_branch "$BR" || { echo "보호 브랜치에서만 실행"; exit 1; }
  do_fetch 8 || echo "(fetch 실패 — 로컬 정보로 진행)"
  for d in "$CLAIM_DIR"/*/; do [ -d "$d" ] || continue; f="$d/claim.md"; [ -f "$f" ] || continue; b="$(claim_get "$f" branch)"
    r=""; g show-ref --verify --quiet "refs/remotes/origin/$b" && r="origin/$b"; [ -z "$r" ] && g show-ref --verify --quiet "refs/heads/$b" && r="$b"
    if [ -z "$r" ]; then echo "삭제: $d (브랜치 $b 없음)"; g rm -rq "$d"
    elif ref_merged "$r"; then echo "삭제: $d (브랜치 $b 머지됨)"; g rm -rq "$d"; fi; done
  # 브랜치가 사라진 wip ref 정리
  for ref in $(g for-each-ref --format='%(refname)' refs/wip 2>/dev/null); do rest="${ref#refs/wip/}"; slug="${rest#*/}"; [ "$rest" = "$slug" ] && continue
    b="$(printf '%s' "$slug" | sed 's#--#/#g')"; g show-ref --verify --quiet "refs/remotes/origin/$b" || { echo "wip 정리: $ref"; g push -q origin --delete "$ref" >/dev/null 2>&1; g update-ref -d "$ref"; }; done
  echo "완료" ;;

precommit)
  [ "$BR" = HEAD ] && exit 0
  # 허브 파일을 동료가 지금 편집 중이면 경고만 (차단은 sobaya 의 커밋 단계를 깨뜨린다)
  [ -f "$CACHE/wip.tsv" ] && [ $(( $(now_epoch) - $(cat "$CACHE/pulse.at" 2>/dev/null || echo 0) )) -lt 900 ] && g diff --cached --name-only | while IFS= read -r p; do
    is_hotspot "$p" && w="$(editing_now "$p")" && [ -n "$w" ] && echo "주의: 허브 파일 $p 를 $(printf '%s' "$w" | cut -f1 | sed 's/^/@/' | tr '\n' ' ')도 지금 편집 중입니다. 머지 충돌 가능성이 높습니다." >&2; done
  export COLLAB_SKIP_WIP=1; bad=0
  g diff --cached --name-only --no-renames -z | tr '\0' '\n' | while IFS= read -r p; do [ -n "$p" ] || continue
    check_write "$p" || { printf '✗ %s\n  %s\n' "$p" "$REASON" >&2; echo bad; }; done | grep -q bad && bad=1
  [ $bad -eq 0 ] || { echo "커밋 차단 (협업 하네스). 위 안내대로 고친 뒤 다시 커밋하세요." >&2; exit 1; }; exit 0 ;;
prepush)
  # stdin: "<local ref> <local sha> <remote ref> <remote sha>" 줄들. 보호 브랜치로의 push 는 차단 (CI 는 COLLAB_ALLOW_PROTECTED_PUSH=1)
  if [ -z "${COLLAB_ALLOW_PROTECTED_PUSH:-}" ] && [ ! -t 0 ]; then
    while read -r lref lsha rref rsha; do [ -n "$rref" ] || continue; rb="${rref#refs/heads/}"
      is_protected_branch "$rb" || continue; [ "$lsha" != "0000000000000000000000000000000000000000" ] || continue   # 삭제는 여기서 안 봄
      [ "$rsha" = "0000000000000000000000000000000000000000" ] && continue                                              # 원격에 없던 브랜치의 첫 publish
      # 하네스·협업 메타만 바뀐 push(초기화 커밋, claim 정리 등)는 통과 — guard 의 보호 브랜치 허용 목록과 같은 기준
      if g rev-parse -q --verify "$rsha^{commit}" >/dev/null 2>&1; then
        meta_only=1; for f in $(g diff --name-only "$rsha" "$lsha" 2>/dev/null); do path_matches_any "$f" $PROTECTED_BRANCH_ALLOW || { meta_only=0; break; }; done
        [ $meta_only = 1 ] && continue; fi
      echo "차단: 보호 브랜치 $rb 로 코드를 직접 push 하지 않습니다. 브랜치를 만들어 PR 로 머지하세요. (CI 나 관리자는 COLLAB_ALLOW_PROTECTED_PUSH=1)" >&2; exit 1; done
  fi
  is_protected_branch "$BR" && exit 0; [ -f "$(claim_path_for "$BR")" ] || exit 0
  [ -n "$(my_files | head -n1)" ] || exit 0
  [ -n "$MAIN" ] && g diff --name-only --diff-filter=A "$(g merge-base "$MAIN" HEAD)" HEAD -- "$JOURNAL_DIR" 2>/dev/null | grep -q "^$JOURNAL_DIR/[^/]*-$ME-" && exit 0
  echo "주의: 이 브랜치에 코드 변경이 있는데 내 저널이 없습니다. PR 전에 handoff 스킬(또는 collab/journal/ 에 이벤트 파일)을 남기세요. CI 가 PR 에서 막습니다." >&2; exit 0 ;;
*) sed -n '2,13p' "$0"; exit 1 ;;
esac
