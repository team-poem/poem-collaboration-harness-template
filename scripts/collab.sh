#!/bin/sh
# 협업 하네스 도구. 훅과 같은 lib.sh 를 쓴다. 사람도, 훅도, 다른 하네스도, CI 도 이것만 부른다.
#
#   digest [--fetch] [--json]   협업 현황. 세션 시작 훅이 주입하는 것과 동일. 내 시점으로 좁혀서
#   pulse                       내 작업 트리 스냅샷 올리기 + 원격 당겨오기. 새 겹침·새 이벤트·main 변경(자동 rebase)만 출력
#   guard <path> | --allow <path>   쓰기 판정(exit 2 = 차단). --allow 는 이 세션에서 그 경로의 허브 차단을 해제
#   check [--base REF]          PR 규칙 검사. 위반 시 exit 1. CI 와 handoff 가 사용
#   prune                       main 전용. 머지·소멸 브랜치의 claim 삭제
#   precommit                   git pre-commit 이 부른다. 스테이지된 파일마다 guard 와 같은 판정 (도구가 무엇이든)
#   prepush                     git pre-push 가 부른다. 저널 없이 push 하면 경고 (막지는 않음)
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
seen() { [ -f "$CACHE/seen" ] && grep -qxF "$1" "$CACHE/seen"; }
mark_seen() { echo "$1" >> "$CACHE/seen"; }
event_id() { printf '%s' "$1" | cksum | cut -d' ' -f1; }
# 이벤트 줄 "- <type> <path?> <text>" → "type<TAB>path<TAB>text" (path 는 / 또는 . 을 포함한 두 번째 토큰)
parse_event() { sed 's/^[[:space:]]*-[[:space:]]*//' | awk '{
  t=$1; p="-"; s=2; if ($2 ~ /[\/.]/ && $2 !~ /^@/) { p=$2; s=3 }
  txt=""; for (i=s;i<=NF;i++) txt=txt (i>s?" ":"") $i; printf "%s\t%s\t%s\n", t, p, txt }'; }
# 내 파일이 이 경로를 import 하는가 (확장자 뗀 경로의 마지막 두 조각으로 grep)
imported_by_me() { key="$(printf '%s' "$1" | sed -E 's/\.[a-zA-Z]+$//' | awk -F/ '{print (NF>1? $(NF-1)"/"$NF : $NF)}')"
  [ -n "$key" ] && [ -n "$MYF" ] && printf '%s\n' "$MYF" | xargs grep -l -- "$key" 2>/dev/null | grep -q .; }
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

digest)
  fetch_note=""; json=0; for a in "$@"; do case "$a" in --fetch) do_fetch 8 && fetch_note="원격 갱신됨" || fetch_note="원격 갱신 실패 — 동료 상태가 오래됐을 수 있음" ;; --json) json=1 ;; esac; done
  wip_table; MYF="$(my_files)"; MINE="$(claim_path_for "$BR")"; lastj="$(my_last_journal_date)"
  # 수집: asks, events, others, overlaps → 임시 파일
  A="$CACHE/_asks"; E="$CACHE/_events"; O="$CACHE/_others"; V="$CACHE/_overlaps"; : > "$A"; : > "$E"; : > "$O"; : > "$V"
  other_journals | sort -t"$TAB" -k2 | while IFS="$TAB" read -r ref j b o; do
    jd="$(basename "$j" | cut -c1-10)"; tmp="$(mktemp)"; g show "$ref:$j" > "$tmp" 2>/dev/null
    md_section "$tmp" "이벤트" | while IFS= read -r line; do
      id="$(event_id "$j|$line")"; ev="$(printf '%s\n' "$line" | parse_event)"; t="${ev%%$TAB*}"; rest="${ev#*$TAB}"; p="${rest%%$TAB*}"; txt="${rest#*$TAB}"
      if [ "$t" = ask ] && printf '%s' "$txt" | grep -q "@$ME\b"; then replied "$o" "$jd" || printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$b" "$o" "$j" "$txt" >> "$A"; continue; fi
      printf '%s' "$txt" | grep -q "@$ME\b" && { seen "$id" || printf '%s\t%s\t%s\t%s\t%s %s\n' "$id" "$b" "$o" "$j" "$t" "$txt" >> "$A"; continue; }
      seen "$id" && continue; affects_me "$t" "$p" || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$b" "$o" "$j" "$t" "$p" "$txt" >> "$E"
    done; rm -f "$tmp"
  done
  _others() { o="$(claim_get "$2" owner)"; st="$(claim_get "$2" status)"; files=""; age=""
    [ -f "$CACHE/wip.tsv" ] && line="$(grep "^$o$TAB" "$CACHE/wip.tsv")" && { age="$(printf '%s' "$line" | cut -f2)"; files="$(printf '%s' "$line" | cut -f3)"; }
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "${o:--}" "${st:-active}" "$(claim_get "$2" goal)" "${age:--}" "${files:--}" >> "$O"
    for f in $files; do [ "$f" = "-" ] && continue; printf '%s\n' "$MYF" | grep -qx "$f" && printf '%s\t%s\t%s\t%s\n' "$f" "$o" "$age" "$( is_hotspot "$f" && echo hotspot || echo file)" >> "$V"; done; }
  for_each_other_claim _others
  if [ $json = 1 ]; then
    printf '{"me":"%s","branch":"%s","claim":' "$(esc "$ME")" "$(esc "$BR")"
    if [ -f "$MINE" ]; then printf '{"goal":"%s","status":"%s","owner":"%s"}' "$(esc "$(claim_get "$MINE" goal)")" "$(esc "$(claim_get "$MINE" status)")" "$(esc "$(claim_get "$MINE" owner)")"; else printf 'null'; fi
    printf ',"asks":['; f=1; while IFS="$TAB" read -r id b o j txt; do [ $f = 1 ] || printf ','; f=0; printf '{"id":"%s","from":"%s","branch":"%s","text":"%s","journal":"%s"}' "$id" "$(esc "$o")" "$(esc "$b")" "$(esc "$txt")" "$(esc "$j")"; done < "$A"
    printf '],"events":['; f=1; while IFS="$TAB" read -r id b o j t p txt; do [ $f = 1 ] || printf ','; f=0; printf '{"type":"%s","path":"%s","text":"%s","from":"%s","branch":"%s"}' "$(esc "$t")" "$(esc "$p")" "$(esc "$txt")" "$(esc "$o")" "$(esc "$b")"; done < "$E"
    printf '],"others":['; f=1; while IFS="$TAB" read -r b o st goal age files; do [ $f = 1 ] || printf ','; f=0; printf '{"branch":"%s","owner":"%s","status":"%s","goal":"%s","wip_age":%s,"touching":%s}' "$(esc "$b")" "$(esc "$o")" "$(esc "$st")" "$(esc "$goal")" "$( [ "$age" = "-" ] && echo null || echo "$age")" "$( [ "$files" = "-" ] && echo '[]' || printf '%s\n' $files | jarr)"; done < "$O"
    printf '],"overlaps":['; f=1; while IFS="$TAB" read -r fpath o age kind; do [ $f = 1 ] || printf ','; f=0; printf '{"path":"%s","owner":"%s","wip_age":%s,"kind":"%s"}' "$(esc "$fpath")" "$(esc "$o")" "$age" "$kind"; done < "$V"
    printf ']}\n'
  else
    echo "# 협업 현황 (자동 주입) · 나: @$ME · 브랜치: ${BR:-?}${fetch_note:+ · $fetch_note}"
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
    if [ -s "$O" ]; then while IFS="$TAB" read -r b o st goal age files; do echo "- $b · @$o · $st · $goal"; [ "$files" != "-" ] && echo "  지금 만지는 파일 ($(fmt_age "$age")): $files"; done < "$O"; else echo "- 없음"; fi
    if sr="$(sobaya_root)"; then lk="$(sobaya_lock)"; hd="$(git -C "$sr" rev-parse --short HEAD 2>/dev/null)"
      echo; echo "## 개발 하네스 (sobaya)"
      if [ -z "$lk" ]; then echo "- sobaya 워크스페이스 감지($sr). 아직 붙이지 않음 → sh harness/attach-sobaya.sh attach"
      elif [ "$(git -C "$sr" rev-parse HEAD 2>/dev/null)" != "$lk" ]; then echo "- 내 sobaya($hd)가 팀이 검증한 버전(${lk%"${lk#???????}"})과 다릅니다 → sh harness/attach-sobaya.sh sync"
      else echo "- sobaya $hd · 팀 검증 버전과 일치$( sobaya_approved && echo ' · 이 브랜치는 승인 상태 있음(main 따라잡기는 merge)')"; fi
    fi
    echo; echo "## 지금 같은 파일을 만지는 중"
    if [ -s "$V" ]; then while IFS="$TAB" read -r fpath o age kind; do echo "- $fpath ← @$o ($(fmt_age "$age"))$( [ "$kind" = hotspot ] && echo ' · 허브 파일: 차단됨. 상대가 끝나길 기다린다')"; done < "$V"
      echo "  → 같은 부분을 고치는 것 같으면 사용자에게 알린다. 작게 커밋하고 자주 pulse 한다."
    else echo "- 없음"; fi
  fi
  rm -f "$A" "$E" "$O" "$V"; now_epoch > "$CACHE/pulse.at" ;;

pulse)
  is_protected_branch "$BR" && exit 0
  [ -f "$CACHE/overlaps.prev" ] || : > "$CACHE/overlaps.prev"
  wip_push; do_fetch 5 || { now_epoch > "$CACHE/pulse.at"; exit 0; }
  out=""; wip_table; MYF="$(my_files)"
  # 새 겹침 (파일 단위)
  new=""; [ -f "$CACHE/wip.tsv" ] && while IFS="$TAB" read -r o age files; do for f in $files; do [ "$f" = "-" ] && continue
    printf '%s\n' "$MYF" | grep -qx "$f" || continue; grep -qxF "$f@$o" "$CACHE/overlaps.prev" && continue
    echo "$f@$o" >> "$CACHE/overlaps.prev"; new="$new
- 겹침: $f 를 @$o 도 만지는 중 ($(fmt_age "$age"))$( is_hotspot "$f" && echo ' · 허브 파일이라 이제부터 차단됨')"; done; done < "$CACHE/wip.tsv"
  [ -n "$new" ] && out="$out$new"
  # 새 이벤트·질문 (digest 와 같은 필터, seen 제외)
  ev="$(sh "$0" digest --json 2>/dev/null)"
  if command -v jq >/dev/null 2>&1 && [ -n "$ev" ]; then
    touch "$CACHE/asked"
    a="$(printf '%s' "$ev" | jq -r '.asks[] | "\(.id)\t- 질문 @\(.from): \(.text)"' 2>/dev/null | while IFS="$TAB" read -r id line; do grep -qxF "$id" "$CACHE/asked" && continue; echo "$id" >> "$CACHE/asked"; echo "$line"; done)"
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
      if [ "$AUTO_REBASE" = true ] && tree_clean; then
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
  else V "claim 없음: $cp (Skill: start-work)"; fi
  journals="$(printf '%s\n' "$changed" | awk '$1=="A"{print $2}' | grep "^$JOURNAL_DIR/[^/]*\.md$" | grep -v README || true)"
  [ -n "$journals" ] || V "저널 없음. $JOURNAL_DIR/ 에 새 파일 (Skill: handoff)"
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
  echo "완료" ;;

precommit)
  [ "$BR" = HEAD ] && exit 0
  export COLLAB_SKIP_WIP=1; bad=0
  g diff --cached --name-only --no-renames -z | tr '\0' '\n' | while IFS= read -r p; do [ -n "$p" ] || continue
    check_write "$p" || { printf '✗ %s\n  %s\n' "$p" "$REASON" >&2; echo bad; }; done | grep -q bad && bad=1
  [ $bad -eq 0 ] || { echo "커밋 차단 (협업 하네스). 위 안내대로 고친 뒤 다시 커밋하세요." >&2; exit 1; }; exit 0 ;;
prepush)
  is_protected_branch "$BR" && exit 0; [ -f "$(claim_path_for "$BR")" ] || exit 0
  [ -n "$(my_files | head -n1)" ] || exit 0
  [ -n "$MAIN" ] && g diff --name-only --diff-filter=A "$(g merge-base "$MAIN" HEAD)" HEAD -- "$JOURNAL_DIR" 2>/dev/null | grep -q "^$JOURNAL_DIR/[^/]*-$ME-" && exit 0
  echo "주의: 이 브랜치에 코드 변경이 있는데 내 저널이 없습니다. PR 전에 handoff 스킬(또는 collab/journal/ 에 이벤트 파일)을 남기세요. CI 가 PR 에서 막습니다." >&2; exit 0 ;;
*) sed -n '2,11p' "$0"; exit 1 ;;
esac
