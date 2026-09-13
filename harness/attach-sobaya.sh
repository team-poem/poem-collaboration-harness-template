#!/bin/sh
# 개발 하네스 sobaya(team-poem/sobaya)를 이 앱에 붙이고, 팀이 검증한 sobaya 버전을 맞춘다.
#
#   attach [--sobaya PATH] [--test "npm test"]  처음 한 번. 앱 계약(AGENTS.md 의 - Test:), sobaya 의 install/설정, 루트 세션용 훅 어댑터, lock
#   sync                                        내 sobaya 클론을 최신으로(pull --ff-only) + 앱 계약 재설치(멱등). 세션 시작 digest 가 권할 때
#   update                                      sync 후 lock 을 현재 sobaya 커밋으로 올린다. 커밋해서 팀에 공유
#   check                                       클론·lock·upstream 버전과 훅 상태를 보여준다
#
# 배치: sobaya 워크스페이스 안에 이 리포를 둔다 (sobaya/apps/<이 리포>). 다른 곳이면 --sobaya 또는 harness/config.sh SOBAYA_ROOT.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"; cd "$ROOT"
. "$ROOT/harness/hooks/lib.sh"
LOCK="$ROOT/harness/sobaya.lock"
die() { echo "✗ $*" >&2; exit 1; }
cmd="${1:-}"; [ $# -gt 0 ] && shift
sob=""; testcmd=""
while [ $# -gt 0 ]; do case "$1" in --sobaya) sob="$2"; shift ;; --test) testcmd="$2"; shift ;; esac; shift; done
if [ -n "$sob" ]; then sob="$(cd "$sob" && pwd -P)" || die "sobaya 경로 없음: $sob"; else sob="$(sobaya_root)" || die "sobaya 워크스페이스를 못 찾음. 이 리포를 sobaya/apps/ 아래에 두거나 --sobaya PATH"; fi
[ -x "$sob/tdd-set/bin/install.sh" ] || die "$sob 는 sobaya 워크스페이스가 아님 (tdd-set/bin/install.sh 없음)"
sob_head() { git -C "$sob" rev-parse HEAD 2>/dev/null; }
sob_short() { git -C "$sob" rev-parse --short HEAD 2>/dev/null; }
write_lock() { printf 'repo=%s\nsha=%s\nchecked=%s\n' "$(git -C "$sob" remote get-url origin 2>/dev/null || echo team-poem/sobaya)" "$(sob_head)" "$(today)" > "$LOCK"; }
install_app() {  # 멱등. 앱 계약 파일과 앱 pre-commit. sobaya 의 install.sh 는 core.hooksPath 가 있으면 거부하므로 잠깐 풀었다가 되돌린다.
  hp="$(git config --get core.hooksPath 2>/dev/null || true)"; [ -z "$hp" ] || git config --unset core.hooksPath
  out="$(bash "$sob/tdd-set/bin/install.sh" "$ROOT" 2>&1)"; rc=$?
  [ -z "$hp" ] || git config core.hooksPath "$hp"
  [ $rc -eq 0 ] || { echo "$out" >&2; die "sobaya install 실패"; }
  echo "✓ sobaya 앱 계약: spec.md, failed-test.md, 앱 pre-commit(.git/hooks — 우리 .githooks/pre-commit 이 이어서 실행)"
}
sobaya_hook_ok() { h="$(git rev-parse --git-common-dir)/hooks/pre-commit"; [ -x "$h" ] && head -n2 "$h" | grep -q 'Sobaya app pre-commit'; }
install_adapter() {  # 루트에서 세션을 열어도 collab 훅이 앱에 적용되게
  mkdir -p "$sob/.claude/hooks"; cp "$ROOT/harness/sobaya/collab-dispatch.sh" "$sob/.claude/hooks/collab-dispatch.sh"; chmod +x "$sob/.claude/hooks/collab-dispatch.sh"
  sl="$sob/.claude/settings.local.json"; d='"$CLAUDE_PROJECT_DIR"/.claude/hooks/collab-dispatch.sh'
  want="$(jq -n --arg c "$d" '{hooks:{SessionStart:[{matcher:"startup|resume|clear",hooks:[{type:"command",command:$c}]}],PreToolUse:[{matcher:"Write|Edit|MultiEdit|NotebookEdit|Bash",hooks:[{type:"command",command:$c}]}],PostToolUse:[{matcher:"Write|Edit|MultiEdit|NotebookEdit|Bash",hooks:[{type:"command",command:$c}]}],Stop:[{hooks:[{type:"command",command:$c}]}]}}')"
  if [ -f "$sl" ] && jq -e . "$sl" >/dev/null 2>&1; then
    jq --argjson w "$want" --arg c "$d" '
      .hooks = (.hooks // {}) | reduce ($w.hooks|keys[]) as $k (.; .hooks[$k] = ((.hooks[$k] // []) | map(select((.hooks // [])|all(.command != $c)))) + $w.hooks[$k])' "$sl" > "$sl.tmp" && mv "$sl.tmp" "$sl"
  else printf '%s\n' "$want" > "$sl"; fi
  ex="$sob/.git/info/exclude"; mkdir -p "$(dirname "$ex")"; for l in ".claude/" "CLAUDE.md"; do grep -qxF "$l" "$ex" 2>/dev/null || echo "$l" >> "$ex"; done
  [ -e "$sob/CLAUDE.md" ] || ln -s AGENTS.md "$sob/CLAUDE.md"   # Claude Code 가 sobaya 계약을 읽게 (git 에는 안 올라감)
  echo "✓ 루트 세션 어댑터(Claude): $sob/.claude/settings.local.json (git 추적 안 함). Codex 는 앱 안에서 세션을 여세요 — .codex/hooks.json 이 앱에 있습니다"
}
set_test() {
  cur="$(sed -n 's/^- Test:[[:space:]]*//p' AGENTS.md | head -n1)"
  if [ -z "$testcmd" ] && printf '%s' "$cur" | grep -q '<'; then printf '앱 테스트 명령 (예: npm test, go test ./...) [비우면 나중에]: '; read -r testcmd; fi
  if [ -n "$testcmd" ]; then sed -i.bak "s|^- Test:.*|- Test: \`$testcmd\`|" AGENTS.md && rm -f AGENTS.md.bak; echo "✓ AGENTS.md: - Test: \`$testcmd\`"
  elif printf '%s' "$cur" | grep -q '<'; then echo "! AGENTS.md 의 '- Test:' 가 아직 자리표시자입니다. 채우기 전에는 sobaya 의 pre-commit 이 커밋을 막습니다."; fi
}
case "$cmd" in
  attach)
    grep -q '^- Test:' AGENTS.md || die "AGENTS.md 에 '## App facts' 절이 없습니다 (템플릿 0.0.2 이상 필요)"
    [ -L AGENTS.md ] && die "AGENTS.md 가 심링크입니다. sobaya 는 실제 파일만 읽습니다 — 템플릿 0.0.2 로 갱신하세요"
    set_test
    bash "$sob/scripts/setup.sh" "$sob" >/dev/null 2>&1 && echo "✓ sobaya 루트 git 훅 활성" || echo "! sobaya 루트 훅 설정 실패 (bash $sob/scripts/setup.sh $sob 로 확인)"
    install_app; install_adapter
    [ -f "$LOCK" ] || { write_lock; echo "✓ lock: harness/sobaya.lock = $(sob_short) (팀이 쓰는 sobaya 버전)"; }
    echo; echo "다음: git add AGENTS.md spec.md failed-test.md harness/sobaya.lock && git commit -m 'chore: attach sobaya'"
    echo "     spec.md 와 failed-test.md 는 브랜치(기능) 단위 산출물입니다. handoff 가 PR 전에 collab/journal/plans/ 로 옮깁니다." ;;
  sync|update)
    before="$(sob_short)"
    if [ -n "$(git -C "$sob" status --porcelain 2>/dev/null | grep -v '^?? \.claude/\|^?? CLAUDE.md')" ]; then echo "! sobaya 클론에 커밋 안 한 변경이 있어 pull 을 건너뜁니다 ($sob)"
    else git -C "$sob" pull -q --ff-only 2>/dev/null && echo "✓ sobaya $before → $(sob_short)" || echo "! pull --ff-only 실패 (브랜치가 갈라졌거나 오프라인). 그대로 진행"; fi
    install_app; install_adapter
    sobaya_hook_ok && echo "✓ sobaya 앱 pre-commit 있음 (우리 pre-commit 뒤에 실행)" || echo "! sobaya 앱 pre-commit 이 없습니다. attach 를 다시 실행하세요"
    if [ "$cmd" = update ]; then write_lock; echo "✓ lock 갱신 → $(sob_short). 커밋해서 팀에 공유: git add harness/sobaya.lock && git commit -m 'chore: sobaya $(sob_short)'"
    else lk="$(sobaya_lock)"; [ -n "$lk" ] && [ "$lk" != "$(sob_head)" ] && echo "! 내 sobaya($(sob_short))가 lock($(printf '%s' "$lk" | cut -c1-7))과 다릅니다. 팀 기준을 올리려면 'update'"; fi ;;
  check)
    lk="$(sobaya_lock)"; up="$(git -C "$sob" ls-remote -q origin HEAD 2>/dev/null | cut -f1)"
    echo "sobaya 클론:   $sob @ $(sob_short)"
    echo "lock (팀 기준): ${lk:-없음}"; echo "upstream HEAD: ${up:-확인 불가}"
    [ -n "$lk" ] && [ "$lk" != "$(sob_head)" ] && echo "→ 클론이 lock 과 다름: sh harness/attach-sobaya.sh sync"
    [ -n "$up" ] && [ -n "$lk" ] && [ "$up" != "$lk" ] && echo "→ upstream 이 lock 보다 앞섬: sh harness/attach-sobaya.sh update 후 커밋"
    sobaya_hook_ok && echo "sobaya 앱 pre-commit: 있음" || echo "sobaya 앱 pre-commit: 없음"
    [ "$(git config --get core.hooksPath 2>/dev/null)" = ".githooks" ] && echo "협업 git 훅: 활성 (.githooks)" || echo "협업 git 훅: 비활성 → git config core.hooksPath .githooks"
    [ -f "$sob/.claude/hooks/collab-dispatch.sh" ] && echo "루트 세션 어댑터: 설치됨" || echo "루트 세션 어댑터: 없음 (attach 또는 sync)" ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
