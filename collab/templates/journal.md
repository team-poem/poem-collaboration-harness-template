# {{BRANCH}} · {{OWNER}} · {{DATE}}
- claim: collab/active/{{SLUG}}/claim.md

## 이벤트
<!-- 동료의 에이전트가 읽는다. 한 줄 = 한 사건. 형식: - <type> <경로?> <무엇이 바뀌었나> → <상대가 할 일>
     type: changed(시그니처·동작 변경) added(새 공용 것, 중복 만들지 말 것) removed migrated(스키마·데이터)
           dep(의존성) rule(앞으로 지킬 규칙) touching(지금 만지는 중, 며칠) done(끝남, 자유롭게) ask @핸들(질문) reply @핸들(답) -->
- changed lib/api/user.ts getUser 가 id 를 받게 됨 → 호출부는 id 를 넘길 것
- added components/ui/Toast.tsx 공용 토스트 → 새로 만들지 말고 이걸 쓸 것

## 남은 것
<!-- 이 브랜치를 이어받는 사람이 그대로 이어갈 수 있게. 막힌 곳, 시도했다 실패한 것 -->
- 
