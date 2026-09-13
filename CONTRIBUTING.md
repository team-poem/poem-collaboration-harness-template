# 기여 절차 (사람용)

에이전트용 규칙은 `CLAUDE.md`. 이건 사람이 지키는 것. 외울 규칙은 셋이다. **시작에 claim, 끝에 저널, 남한테 할 말은 `ask @핸들`.**

## 처음 한 번
- 클론하고 `claude` 나 `codex` 를 켠다. 첫 세션은 온보딩이다 — 에이전트가 인사하고 핸들·테스트 명령·허브 파일을 물은 뒤 설정한다. 합류하는 사람은 핸들 하나만.
- 훅이 없는 도구면 `sh harness/init.sh <이름> <핸들>` 또는 `sh harness/join.sh <핸들>`. 세션 시작에 `sh scripts/collab.sh digest --fetch` 를 직접 친다.
- Claude Code 든 Codex 든 같다.
- `git config rerere.enabled true` (init.sh 가 해준다). 같은 충돌을 두 번 풀지 않는다.

## 브랜치
- `main` 은 보호 브랜치. PR 로만. 브랜치 하나 = claim 하나 = PR 하나.
- 브랜치는 짧게. 하루 안에 머지하는 걸 목표로. 오래 끌수록 충돌은 커진다.

## 흐름
1. `start-work` 로 브랜치와 claim 을 만들고 **바로 push**. 동료가 보는 건 원격뿐이다.
2. 작게 커밋하고 자주 push. 에이전트가 "겹침" 이나 "허브 파일 차단" 을 알리면 당사자와 한마디 나눈다.
3. 끝나면 `handoff`. 저널 없는 PR, 이벤트 절 없는 저널은 CI 가 막는다.

## PR 과 머지
- 본문은 `scripts/collab.sh pr-body` 가 만든다. 사람은 "검증" 칸만 채운다. 제목 = claim goal.
- **머지는 squash 만, 머지 시 브랜치 삭제.** `init.sh` 가 GitHub 설정을 시도한다. 하네스의 머지 감지와 prune 이 이 전제로 돈다.
- 리뷰어는 서로. 하루에 PR 여러 개, 400줄 넘기 전에. 공유 파일(스키마·의존성) 변경은 작은 선행 PR 로 먼저.
- 먼저 머지되는 쪽이 이기고 나중 쪽이 main 을 merge 로 따라잡는다 (pulse 가 자동). `check` 가 "다른 열린 브랜치와 같은 파일" 을 알려준다.
- **main 보호:** 리포는 public 으로 둔다 (조직이 Free 플랜이라 private 에는 브랜치 보호를 못 건다). `init.sh` 가 PR 필수·CI 통과 필수·force push 금지를 건다. git 훅도 같은 걸 막으므로 이중이다. private 로 만들어야 하면 git 훅만 남는다는 걸 알고 쓴다.

## AI 사용 고지
- 에이전트가 diff 의 의미 있는 부분을 썼으면 커밋에 `Assisted-by: <모델명>`.
- 결과는 사람이 소유한다. 설명 못 하는 줄은 지운다.

## sobaya 와 함께 쓸 때
- 이 리포는 각자의 sobaya 워크스페이스 안 `apps/<이름>` 에 클론한다. 처음 한 번 `sh harness/attach-sobaya.sh attach`.
- sobaya 가 업데이트되면: 아무나 `sh harness/attach-sobaya.sh update` → `harness/sobaya.lock` 커밋 → 나머지는 세션 시작 때 digest 가 "다르다" 고 하면 `sync`. 매주 CI 가 upstream 이 앞서면 이슈를 연다.
- `spec.md`·`failed-test.md` 는 브랜치 단위. PR 전에 handoff 가 `collab/journal/plans/` 로 옮긴다. main 에 남기지 않는다.

## 하네스를 고칠 때
- 훅을 고치면 `tests/hooks.sh` 와 `tests/loop.sh`. 새 규칙엔 테스트를 붙인다.
- `harness/VERSION` 을 올리고 `harness/CHANGELOG.md` 에 한 줄.
