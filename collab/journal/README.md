# journal/ — 이벤트 로그 (append-only)

**읽는 쪽은 동료의 에이전트다.** 사람 읽으라고 쓰는 회고가 아니라, 상대 에이전트가 내 변경 위에서 올바르게 행동하기 위한 사실을 남긴다.

- 세션 또는 의미 있는 작업 단위마다 **새 파일 하나**. 기존 파일은 고치지 않는다 (훅이 막는다).
- 파일명: `YYYY-MM-DD-<owner>-<slug>.md`. 같은 날 여러 개면 `-2`, `-3`. owner 핸들에는 하이픈을 쓰지 않는다.
- `## 이벤트`: `- <type> <경로?> <무엇> → <상대가 할 일>`. type 은 changed / added / removed / migrated / dep / rule / touching / done / ask @핸들 / reply @핸들.
- `## 남은 것`: 이 브랜치를 이어받는 사람용.
- 동료 세션에는 머지 전이라도 원격 브랜치에서 읽어 **나에게 영향 있는 이벤트만** 주입된다: 내가 만진 파일이나 내가 import 하는 파일의 changed/migrated, 모든 added/dep/rule, 나를 부른 ask.
- `ask @핸들` 은 상대가 `reply @나` 로 답할 때까지 상대 세션에 계속 뜬다.
- 브랜치마다 새 파일만 추가되므로 병합 충돌이 구조적으로 없다.

템플릿: `collab/templates/journal.md`
