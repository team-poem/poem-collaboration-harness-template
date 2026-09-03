#!/bin/sh
# 훅·CLI 공통 라이브러리. POSIX sh. jq 있으면 쓰고 없으면 sed.
# 원칙: 판단이 안 서면 통과(fail-open). 막을 때만 확실히 막는다. 모든 판정은 여기 한 곳에 있다.

_norm_dir() { (cd "$1" 2>/dev/null && pwd -P); }
# 리포 루트: 대상 파일에서 위로 올라가 collab/ 와 .git 을 가진 가장 가까운 디렉토리. 없으면 CLAUDE_PROJECT_DIR.
find_root_from() {
  d="$1"; while [ "$d" != "/" ] && [ -n "$d" ]; do
    [ -d "$d/collab" ] && [ -e "$d/.git" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"; done; return 1
}
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ROOT="$(_norm_dir "$ROOT" || printf '%s' "$ROOT")"
load_config() {
  # shellcheck disable=SC1091
  [ -f "$ROOT/harness/config.sh" ] && . "$ROOT/harness/config.sh"
  : "${PROTECTED_BRANCHES:=main master develop}" "${CLAIM_DIR:=collab/active}" "${JOURNAL_DIR:=collab/journal}"
  : "${PROTECTED_BRANCH_ALLOW:=collab/ harness/ .claude/ .github/}" "${CLAIM_EXEMPT:=.claude/settings.local.json}"
  : "${HOTSPOTS:=}" "${PULSE_EVERY_EDITS:=15}" "${PULSE_MAX_AGE_SEC:=900}" "${WIP_STALE_SEC:=7200}" "${AUTO_REBASE:=true}" "${JOURNAL_LOOKBACK_DAYS:=14}"
  CACHE="$ROOT/.claude/cache"; mkdir -p "$CACHE" 2>/dev/null
}
load_config
TAB="$(printf '\t')"

# ---- 나 / 시간 -------------------------------------------------------------
me() { m="$(git -C "$ROOT" config collab.me 2>/dev/null)" || m="$(git -C "$ROOT" config user.name 2>/dev/null)" || m="$USER"; printf '%s' "$m" | tr ' -' '__'; }
today() { date +%Y-%m-%d; }
now_epoch() { date +%s; }
cutoff_date() { date -v-"${JOURNAL_LOOKBACK_DAYS}"d +%F 2>/dev/null || date -d "$JOURNAL_LOOKBACK_DAYS days ago" +%F 2>/dev/null || echo 0000-00-00; }

# ---- 훅 입력 ---------------------------------------------------------------
INPUT=""
hook_read_input() { [ -n "$INPUT" ] || INPUT="$(cat)"; }
_json_get() { if command -v jq >/dev/null 2>&1; then printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null
  else key="${1##*.}"; printf '%s' "$INPUT" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\(\([^\"\\\\]\|\\\\.\)*\)\".*/\1/p" | head -n1; fi; }
hook_tool() { hook_read_input; _json_get .tool_name; }
hook_command() { hook_read_input; _json_get .tool_input.command; }
hook_flag() { hook_read_input; _json_get ".$1"; }
# 대상 파일(없으면 cwd) 위치로 ROOT 를 다시 잡는다. 서브셸이 아닌 최상위에서 호출할 것 (ROOT 를 바꾼다).
hook_reroot() {
  hook_read_input; p="$(_json_get .tool_input.file_path)"; [ -n "$p" ] || p="$(_json_get .tool_input.notebook_path)"
  case "$p" in /*) d="$(_norm_dir "$(dirname "$p")" || dirname "$p")" ;; *) d="$(_json_get .cwd)" ;; esac
  [ -n "$d" ] && r="$(find_root_from "$d")" && [ "$r" != "$ROOT" ] && { ROOT="$r"; load_config; }; return 0
}
hook_file_path() {  # 리포 상대경로. 리포 밖이면 return 1
  hook_read_input; p="$(_json_get .tool_input.file_path)"; [ -n "$p" ] || p="$(_json_get .tool_input.notebook_path)"; [ -n "$p" ] || return 1
  rel_path "$p"
}
rel_path() {  # 절대/상대 → 리포 상대 (심링크 정규화). 리포 밖이면 1
  p="$1"; case "$p" in
    /*) d="$(_norm_dir "$(dirname "$p")")" || d="$(dirname "$p")"; p="$d/$(basename "$p")"
        case "$p" in "$ROOT"/*) p="${p#"$ROOT"/}" ;; *) return 1 ;; esac ;;
    ./*) p="${p#./}" ;; esac
  printf '%s' "$p"
}

# ---- git -------------------------------------------------------------------
g() { git -C "$ROOT" "$@"; }
current_branch() { g symbolic-ref --short -q HEAD 2>/dev/null || g rev-parse --abbrev-ref HEAD 2>/dev/null; }
is_protected_branch() { for pb in $PROTECTED_BRANCHES; do [ "$1" = "$pb" ] && return 0; done; return 1; }
main_ref() { for pb in $PROTECTED_BRANCHES; do g show-ref --verify --quiet "refs/remotes/origin/$pb" && { printf 'origin/%s' "$pb"; return; }; done
  for pb in $PROTECTED_BRANCHES; do g show-ref --verify --quiet "refs/heads/$pb" && { printf '%s' "$pb"; return; }; done; return 1; }
ref_merged() { m="$(main_ref)" && g merge-base --is-ancestor "$1" "$m" 2>/dev/null; }
branch_slug() { printf '%s' "$1" | sed 's#/#--#g'; }
claim_dir_for() { printf '%s/%s' "$CLAIM_DIR" "$(branch_slug "$1")"; }
claim_path_for() { printf '%s/claim.md' "$(claim_dir_for "$1")"; }
tree_clean() { [ -z "$(g status --porcelain 2>/dev/null)" ]; }

# ---- 경로 매칭 (접두어가 / 로 끝나면 디렉토리, 아니면 그 파일 또는 그 아래) --------
path_matches_any() { p="$1"; shift; for prefix in "$@"; do [ -z "$prefix" ] && continue
    case "$prefix" in */) case "$p" in "$prefix"*) return 0 ;; esac ;; *) [ "$p" = "$prefix" ] && return 0; case "$p" in "$prefix"/*) return 0 ;; esac ;; esac; done; return 1; }
in_collab_meta() { case "$1" in collab/*|.claude/*|harness/*) return 0 ;; esac; return 1; }
is_hotspot() { path_matches_any "$1" $HOTSPOTS; }

# ---- claim / 마크다운 ------------------------------------------------------
claim_get() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n1 | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'; }
md_section() { awk -v h="## $2" '$0==h{on=1;next} /^## /{on=0} on && NF' "$1"; }

# 다른 브랜치의 claim 순회. 콜백 $1 에 (branch, claim임시파일, ref). 현재·보호·머지된 브랜치 제외.
for_each_other_claim() {
  me_b="$(current_branch)"; seen=" "
  for ref in $(g for-each-ref --format='%(refname:short)' refs/remotes/origin refs/heads 2>/dev/null | grep -v '^origin/HEAD$' | grep -v '^origin$'); do
    b="${ref#origin/}"; [ "$b" = "$me_b" ] && continue; is_protected_branch "$b" && continue
    case "$seen" in *" $b "*) continue ;; esac; ref_merged "$ref" && continue
    fe_tmp="$(mktemp)"
    if g show "$ref:$(claim_path_for "$b")" > "$fe_tmp" 2>/dev/null && [ -s "$fe_tmp" ]; then seen="$seen$b "; "$1" "$b" "$fe_tmp" "$ref"; fi
    rm -f "$fe_tmp"
  done
}

# ---- 작업 트리 스냅샷 (wip) -------------------------------------------------
# 내 작업 트리(미커밋·미추적 포함, .gitignore 존중)를 커밋 객체로 만들어 refs/wip/<me> 에 올린다. 히스토리를 더럽히지 않는다.
wip_snapshot() {
  idx="$CACHE/wip.index"; rm -f "$idx"
  GIT_INDEX_FILE="$idx" g read-tree HEAD 2>/dev/null || return 1
  GIT_INDEX_FILE="$idx" g add -A . >/dev/null 2>&1
  tree="$(GIT_INDEX_FILE="$idx" g write-tree 2>/dev/null)" || return 1
  g commit-tree "$tree" -p HEAD -m "wip $(me) $(now_epoch)" 2>/dev/null
}
wip_push() { sha="$(wip_snapshot)" && [ -n "$sha" ] && g push -q -f origin "$sha:refs/wip/$(me)" >/dev/null 2>&1; }
wip_fetch() { g fetch -q --prune origin '+refs/wip/*:refs/wip/*' >/dev/null 2>&1; }

# 내가 이 브랜치에서 바꾼 파일 (커밋 + 작업 트리)
my_files() { m="$(main_ref)" || m=HEAD; { g diff --name-only "$(g merge-base "$m" HEAD 2>/dev/null || echo HEAD)" HEAD 2>/dev/null; g status --porcelain 2>/dev/null | awk '{print $NF}'; } | grep -v '^collab/' | sort -u; }

# 동료들이 지금 만지는 파일 → $CACHE/wip.tsv : owner<TAB>age초<TAB>files(공백)
wip_table() {
  wt_out="$CACHE/wip.tsv"; : > "$wt_out.tmp"; m="$(main_ref)" || m=HEAD; my="$(me)"; now="$(now_epoch)"
  for ref in $(g for-each-ref --format='%(refname)' refs/wip 2>/dev/null); do
    o="${ref#refs/wip/}"; [ "$o" = "$my" ] && continue
    t="$(g log -1 --format=%ct "$ref" 2>/dev/null)" || continue; age=$((now - ${t:-0}))
    [ "$age" -gt "$WIP_STALE_SEC" ] && continue
    files="$(g diff --name-only "$(g merge-base "$m" "$ref" 2>/dev/null || echo "$m")" "$ref" 2>/dev/null | grep -v '^collab/' | tr '\n' ' ')"
    printf '%s\t%s\t%s\n' "$o" "$age" "${files:--}" >> "$wt_out.tmp"
  done; mv "$wt_out.tmp" "$wt_out"
}
# 경로를 지금 만지는 동료: "owner<TAB>age" 줄
touching_now() { [ -f "$CACHE/wip.tsv" ] || return 0; while IFS="$TAB" read -r o age files; do for f in $files; do [ "$f" = "$1" ] && { printf '%s\t%s\n' "$o" "$age"; break; }; done; done < "$CACHE/wip.tsv"; }
fmt_age() { s="$1"; [ "$s" -lt 60 ] && { echo "${s}초 전"; return; }; [ "$s" -lt 3600 ] && { echo "$((s/60))분 전"; return; }; echo "$((s/3600))시간 전"; }

# ---- 쓰기 검사: 훅과 CLI 가 같은 판정을 쓴다 ----------------------------------
# check_write <리포상대경로> → 0 허용 / 2 차단 (REASON 에 메시지)
REASON=""
check_write() {
  p="$1"; REASON=""; branch="$(current_branch)" || return 0
  [ "$branch" = "HEAD" ] && { REASON="detached HEAD 입니다. 브랜치를 만들고 Skill(start-work) 로 선언한 뒤 작업하세요."; return 2; }
  if is_protected_branch "$branch"; then
    case "$p" in "$CLAIM_DIR"/*) [ "$(basename "$p")" = README.md ] || { REASON="차단: 보호 브랜치에서는 claim 을 편집하지 않습니다. 정리는 scripts/collab.sh prune."; return 2; } ;; esac
    path_matches_any "$p" $PROTECTED_BRANCH_ALLOW && return 0
    REASON="차단: 보호 브랜치($branch)에서는 코드를 수정하지 않습니다. Skill(start-work) 로 작업 브랜치와 claim 을 만든 뒤 수정하세요."; return 2
  fi
  case "$p" in
    "$JOURNAL_DIR"/*.md) [ "$(basename "$p")" = README.md ] && return 0
      g cat-file -e "HEAD:$p" 2>/dev/null && { REASON="차단: 저널은 append-only 입니다. 커밋된 $p 를 고치지 말고 새 파일을 추가하세요 ($JOURNAL_DIR/$(today)-$(me)-<slug>.md)."; return 2; } ;;
    "$CLAIM_DIR"/*) [ "$(basename "$p")" = README.md ] && return 0
      mine="$(claim_dir_for "$branch")"; case "$p" in "$mine"/*) return 0 ;; esac
      REASON="차단: 다른 브랜치의 claim($p)은 수정하지 않습니다. 내 claim 은 $mine/claim.md."; return 2 ;;
  esac
  path_matches_any "$p" $CLAIM_EXEMPT && return 0
  cp="$(claim_path_for "$branch")"
  [ -f "$ROOT/$cp" ] || { REASON="차단: 이 브랜치($branch)에는 claim 이 없습니다 (수정 대상: $p). 먼저 $cp 를 만들어 무엇을 만드는지 선언하세요. Skill(start-work)."; return 2; }
  in_collab_meta "$p" && return 0
  # 허브 파일을 동료가 지금 만지는 중이면 차단 (세션 중 사용자가 허용한 경로는 통과)
  if is_hotspot "$p"; then
    [ -f "$CACHE/allow" ] && grep -qxF "$p" "$CACHE/allow" && return 0
    who="$(touching_now "$p" | awk -F"$TAB" '{printf "%s@%s(%s) ", (NR>1?", ":""), $1, $2}')"
    if [ -n "$who" ]; then
      REASON="차단: $p 는 허브 파일이고 지금 $(printf '%s' "$who" | sed 's/(\([0-9]*\))/ 작업 트리 \1초 전/g')이 만지는 중입니다. 같은 파일을 동시에 고치면 머지 충돌이 납니다.
멈추고 사용자에게 알리세요. 상대가 끝나길 기다리는 게 원칙입니다. 사용자가 그래도 진행하라고 하면 'scripts/collab.sh guard --allow $p' 후 다시 시도하세요."
      return 2
    fi
  fi
  return 0
}

# Bash 명령에서 쓰기 대상 경로를 뽑아 check_write. 완벽하지 않다 — CI 의 check 가 최종 방어선.
check_command() {
  cmd="$1"; REASON=""
  case "$cmd" in *scripts/collab.sh*|*harness/init.sh*|*tests/hooks.sh*|*tests/loop.sh*) return 0 ;; esac
  scrub="$(printf '%s' "$cmd" | sed -e 's/2>&1//g; s/2>>\{0,1\}[^ ]*//g; s/>&[0-9]//g; s/[12]\{0,1\}>>\{0,1\}[[:space:]]*\/dev\/null//g')"
  printf '%s' "$scrub" | grep -Eq '(^|[^<>|&])>{1,2}[[:space:]]*[^&[:space:]]|(^|[;&|[:space:]])(tee|mv|cp|rm|rmdir|install|truncate|dd|ln)[[:space:]]|(^|[;&|[:space:]])sed[[:space:]]+(-[a-zA-Z]*i|--in-place)|git[[:space:]]+(apply|mv|rm|checkout[[:space:]]+--|restore)|(^|[;&|[:space:]])(python3?|node|perl|ruby)[[:space:]].*(open\(|writeFile|File\.write|>[[:space:]]*[^&])' || return 0
  branch="$(current_branch)" || return 0
  paths="$(printf '%s' "$scrub" | tr ' ;|&()<>"'"'"'`' '\n' | grep -E '^[A-Za-z0-9_./~-]+$' | grep -v '^-' | grep -v '^[0-9.]*$' | sort -u)"
  blocked=""; found=0
  for t in $paths; do
    case "$t" in ~*|/dev/*|/tmp/*|/private/tmp/*|*://*) continue ;; esac
    case "$t" in */*|*.*) ;; *) continue ;; esac
    case "$t" in *.sh|*.py|*.js|*.ts|*.rb|*.pl) [ -x "$ROOT/$t" ] && continue ;; esac
    rp="$(rel_path "$t")" || continue; case "$rp" in node_modules/*|.git/*|.) continue ;; esac; found=1
    check_write "$rp" || blocked="$blocked
- $rp: $REASON"
  done
  [ -n "$blocked" ] && { REASON="차단 (Bash 로 파일 쓰기):$blocked"; return 2; }
  if [ $found -eq 0 ]; then
    is_protected_branch "$branch" && { REASON="차단: 보호 브랜치($branch)에서 파일을 쓰는 것으로 보이는 명령입니다. Skill(start-work) 로 브랜치를 만드세요."; return 2; }
    [ -f "$ROOT/$(claim_path_for "$branch")" ] || { REASON="차단: claim 이 없는 브랜치($branch)에서 파일을 쓰는 것으로 보이는 명령입니다. Skill(start-work) 먼저."; return 2; }
  fi
  return 0
}
