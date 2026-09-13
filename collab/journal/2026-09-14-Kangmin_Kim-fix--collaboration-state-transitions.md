# fix/collaboration-state-transitions · Kangmin_Kim · 2026-09-14
- claim: collab/active/fix--collaboration-state-transitions/claim.md

## 이벤트
- changed scripts/collab.sh pulse 는 직전 겹침과 비교해 편집 → 커밋 → 재편집을 다시 알림 → 같은 PR 에서 받은 새로운 편집 알림에 반응할 것
- changed harness/hooks/post-edit.sh 알림은 동료·브랜치·편집/커밋 상태별로 구분하고 나이를 올바르게 표시 → 커밋됨(미머지)은 선행 PR 검토, 편집 중은 같은 부분 수정 여부 확인
- changed scripts/collab.sh main 보류 알림은 브랜치와 보류 이유별로 기록 → sobaya 종료 뒤 커밋 안내가 오면 작업을 커밋하고 다음 pulse 에서 따라잡기

## 남은 것
- 이 PR 의 리뷰와 squash 머지. 자동 머지는 하지 않았다.
- 실제 sobaya 워커의 전체 실행과 GitHub 상의 다중 PR 경합은 이번에 실행하지 않았다. 로컬 bare 원격·클론 둘, 모의 sobaya 상태로 검증했다.
- 다음 루프 후보: 오래된 WIP 스냅샷과 원격 브랜치의 최신 커밋이 다를 때 겹침 판정 검증. 이번 수정에는 포함하지 않았다.

## 체크포인트와 검증
- 첫 체크포인트: 수정 전 신규 상태 전환 검사 3개 실패를 확인. 겹침 알림 수정 뒤 hooks 71개와 loop 29개 통과.
- 두 번째 체크포인트: 작업 중 보류에서 미커밋 보류로 바뀔 때 안내가 누락되는 검사 1개 실패를 확인. 수정 뒤 sobaya 모의 검증 32개 통과.
- 최종 체크포인트: `sh tests/hooks.sh` 71개, `sh tests/loop.sh` 30개, `sh tests/sobaya.sh` 32개, 총 133개 통과. 충돌 abort 후 HEAD·인덱스·파일 내용, 승인 상태와 작업 커밋 보존 확인.
- 변경된 셸 스크립트 문법 검사와 `git diff --check` 통과.
- 동기화 방식은 기존 merge 를 유지. PR 의존성·머지 순서 자동화와 sobaya 자체 수정은 하지 않았다.
