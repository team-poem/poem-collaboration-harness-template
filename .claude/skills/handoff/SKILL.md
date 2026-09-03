---
name: handoff
description: 세션을 마무리한다. 저널에 이벤트(동료 에이전트가 알아야 할 변경)와 남은 것을 쓰고, claim 상태를 갱신하고, 검사 후 push. 작업을 멈추거나 PR 전, 또는 Stop 훅이 저널이 없다고 세울 때 사용.
---

# handoff — 인수인계

다음에 이 코드를 만지는 건 동료의 에이전트일 가능성이 높다. 그 에이전트가 내 변경 위에서 올바르게 행동하도록 **사실**을 남긴다.

## 절차
1. **저널.** `collab/templates/journal.md` → `collab/journal/YYYY-MM-DD-<나>-<slug>.md` (같은 날 두 번째면 `-2`). 기존 파일은 고치지 않는다.
   - `## 이벤트`: 이번 세션에서 **동료가 모르면 안 되는 것만** 한 줄씩. 형식 `- <type> <경로?> <무엇> → <상대가 할 일>`.
     - 시그니처·동작이 바뀐 함수·컴포넌트·API → `changed`. 새 공용 컴포넌트·유틸·훅 → `added`. 스키마·데이터 → `migrated`. 패키지 → `dep`. 앞으로 지킬 규칙 → `rule`.
     - 세션 시작 시 받은 질문에는 `- reply @상대 ...`. 물어볼 게 있으면 `- ask @상대 ...`.
     - 커밋 로그를 옮겨 적지 않는다. "무엇을 했다" 가 아니라 "상대가 무엇을 해야 하나" 가 기준.
   - `## 남은 것`: 이어받는 사람용. 막힌 곳, 실패한 시도.
2. **claim.** `status` 갱신: 계속하면 `active`, 한동안 안 하면 `paused`, PR 올리면 `done`.
3. **검사.** `scripts/collab.sh check`. 위반이 있으면 고친다. "다른 열린 브랜치와 같은 파일" 이 나오면 사용자에게 알린다.
4. **커밋·push.** `git add collab/ && git commit -m "chore(collab): handoff <branch>" && git push`. PR 을 올릴 때는 `.github/PULL_REQUEST_TEMPLATE.md`.
5. 사용자에게 세 줄: 한 것, 남은 것, 동료가 알아야 할 것.

## 커밋 트레일러
에이전트가 diff 의 의미 있는 부분을 썼으면 커밋 끝에 `Assisted-by: <모델명>`.
