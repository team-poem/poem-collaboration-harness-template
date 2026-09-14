#!/bin/sh
# SessionStart: 리포 상태를 보고 온보딩 또는 협업 현황(digest)을 주입한다. 실패해도 세션은 계속된다.
. "$(dirname "$0")/lib.sh"
rm -f "$CACHE/edits" "$CACHE/warned" "$(branch_cache warned)" "$CACHE/allow"
st="$(sh "$ROOT/scripts/collab.sh" state 2>/dev/null)"; mode="$(printf '%s\n' "$st" | sed -n 's/^state=//p')"
v() { printf '%s\n' "$st" | sed -n "s/^$1=//p"; }
case "$mode" in
  setup|join)
    echo "# 포엠 협업 하네스 — 첫 세션 (온보딩)"
    echo
    echo "이 리포는 아직 이 사람에게 준비되지 않았습니다. 협업 현황 대신 **온보딩을 먼저** 진행하세요. 절차와 대사는 onboard 스킬에 있습니다. 파일 수정은 온보딩이 끝난 뒤에."
    echo
    echo "감지: 리포 $(v repo) · 원격 $(v remote) · 플레이스홀더 $( [ "$(v placeholders)" = 1 ] && echo 있음 || echo 없음) · 핸들 $(v handle) · git 훅 $(v hooks) · sobaya $(v sobaya) $( [ "$(v sobaya_lock)" != - ] && echo '(lock 있음)') · gh $(v gh) · 테스트 명령 $(v test)"
    if [ "$mode" = setup ]; then
      echo "상태: **setup** — 프로젝트가 초기화되지 않았습니다 (플레이스홀더가 남아 있음). 사용자에게 인사하고 네 가지 중 고르게 하세요:"
      echo "  1) 이 폴더를 프로젝트로 초기화  2) 이미 있는 GitHub 프로젝트에 하네스 붙이기  3) 새 프로젝트 만들기  4) 먼저 5분 설명 듣기"
    else
      echo "상태: **join** — 프로젝트는 준비돼 있고, 이 사람의 개인 설정만 남았습니다 (핸들·git 훅·sobaya 동기화). 메뉴 없이 짧게 끝내세요. 설명은 원하면."
    fi
    echo
    echo "끝나면 'sh scripts/collab.sh digest --fetch' 를 보여주고, 외울 규칙 셋(시작에 claim, 끝에 저널, 남한테 할 말은 ask @핸들)을 말한 뒤 start-work 를 제안합니다."
    exit 0 ;;
esac
exec sh "$ROOT/scripts/collab.sh" digest --fetch
