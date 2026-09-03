# active/ — 작업 선언(claim)

브랜치 하나 = 디렉토리 하나. `collab/active/<branch-slug>/claim.md` (`feat/login` → `feat--login/claim.md`).
브랜치 산출물(failed-test.md, spec.md 등)도 이 디렉토리에 둔다.

- claim 이 없으면 훅이 파일 수정을 막는다. 작업의 첫 행동은 선언이다.
- claim 은 "영역 점유" 가 아니다. "무엇을 만드는가" 만 쓴다. 누가 지금 어느 파일을 만지는지는 git(작업 트리 스냅샷)이 안다.
- 다른 브랜치의 claim 은 수정하지 않는다. push 해야 동료에게 보인다.
- 머지되거나 브랜치가 사라진 claim 은 main 에서 `scripts/collab.sh prune` 이 지운다.

템플릿: `collab/templates/claim.md`
