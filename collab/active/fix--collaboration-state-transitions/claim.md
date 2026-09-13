---
branch: fix/collaboration-state-transitions
owner: Kangmin_Kim
started: 2026-09-14
status: active
goal: PR 추가 작업과 main 갱신 사이의 협업 상태 전환을 안정화한다
next: scripts/collab.sh harness/hooks/lib.sh harness/hooks/post-edit.sh tests/loop.sh
---

## 메모
- 사용자가 맡긴 개발 루프. 추가 커밋 중 겹침, 커밋 후 해제, 동기화 보류와 재개를 재현하고 수정한다.
- 체크포인트: 실패 재현과 겹침 수정 / main 동기화 검증 / 전체 회귀 검증과 handoff.
- PR 의존성·머지 순서 자동화는 이번 범위에 포함하지 않는다.
