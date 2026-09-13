# {{PROJECT_NAME}} — 협업 하네스

## App facts
<!-- 개발 하네스 sobaya 가 읽는 앱 계약. - Test: 는 정확히 한 줄, 전체 테스트 스위트 명령. Format:/Lint:/Bench: 는 선택 -->
- Test: `<declare the actual test command>`
- Skills: nodejs

여러 사람이 각자 AI 에이전트를 데리고 이 리포에서 **동시에** 일한다. 이 문서는 에이전트가 동료 에이전트가 한 일을 읽고,
같은 파일을 동시에 고치지 않고, 다음 사람이 이어받을 수 있게 일하기 위한 계약이다. 코드 컨벤션·테스트는 다루지 않는다.

## 0. 어느 도구에서든 같다
이 계약은 `AGENTS.md` 하나다. `CLAUDE.md` 는 여기를 가리키는 심링크. 스킬은 `.agents/skills/` (`.claude/skills` 는 심링크).
규칙의 본체는 `scripts/collab.sh` 와 git 훅(`.githooks/`)에 있고, `.claude/settings.json` 과 `.codex/hooks.json` 은 같은 스크립트를 부르는 얇은 배선이다.
**훅이 안 도는 환경이면 직접 부른다**: 세션 시작에 `sh scripts/collab.sh digest --fetch`, 파일을 여러 개 고친 뒤 `sh scripts/collab.sh pulse`, 끝에 handoff 스킬의 절차. 커밋·push 는 어차피 git 훅이 검사한다.

## 1. 세션 시작
훅이 협업 현황을 주입한다: 나에게 온 질문, 내 claim, **동료가 바꾼 것 중 나에게 영향 있는 이벤트**, 동료가 지금 만지는 파일,
나와 같은 파일을 만지는 중인 사람. 이걸 읽기 전에 파일을 고치지 않는다. 다시 보려면 `scripts/collab.sh digest`.

## 2. 강제되는 것 (에디터 훅과 git pre-commit 이 같은 판정을 쓴다)
1. **선언 없이 수정하지 않는다.** `collab/active/<branch-slug>/claim.md` 가 없으면 Write/Edit 도 Bash 쓰기도 막힌다. 첫 행동은 start-work 스킬.
2. **보호 브랜치(main)에서 코드를 고치지 않는다.**
3. **동료가 지금 편집 중(커밋 전)인 허브 파일은 막힌다** (package.json, 스키마 등 `harness/config.sh` HOTSPOTS). 멈추고 사용자에게 알린다. 상대가 커밋하면 풀린다. 동료 브랜치에 커밋됐지만 미머지인 파일과 그 외 겹침은 알림만 — 공유 파일이면 작은 선행 PR 을 제안한다.
4. **git 훅이 커밋·push 도 본다.** 보호 브랜치로의 직접 push 와 로컬 머지는 막히고, 커밋마다 작업 트리 스냅샷과 브랜치가 올라간다 (`.githooks/`).
5. **저널은 새 파일만.** 남의 claim 은 손대지 않는다. 브랜치마다 새 파일만 추가되므로 머지 충돌이 구조적으로 없다.
6. **세션 중에도 서로를 본다.** 수정 몇 번마다 훅이 내 작업 트리 스냅샷을 올리고 원격을 당겨온다. 새 겹침·새 이벤트·질문이 오면 알려주고, main 이 바뀌면 작업 트리가 깨끗할 때 자동으로 merge 로 따라잡는다. 충돌이면 되돌리고 알린다. sobaya 가 항목 진행 중이면 보류한다.
7. **저널 없이 끝내지 않는다.** 코드 변경이 있는데 오늘 저널이 없으면 Stop 훅이 한 번 세운다 → handoff 스킬.

## 3. 이벤트 = 에이전트 간 언어
저널 `## 이벤트` 는 동료 에이전트가 읽는다. `- <type> <경로?> <무엇> → <상대가 할 일>` 한 줄씩.
`changed` `added` `removed` `migrated` `dep` `rule` `touching` `done` `ask @핸들` `reply @핸들`.
받은 `changed/migrated` 는 내 코드가 깨졌을 수 있다는 뜻이다. 작업 전에 호출부를 확인한다. `added` 는 중복 구현 금지. `rule` 은 따른다. `ask` 는 사용자에게 전하고 `reply` 로 답한다.

## 4. 흐름
- 시작: start-work 스킬 → 브랜치 + claim(goal 한 줄) + push
- 중간: 작게 커밋하고 자주 push. 알림에 반응. 같은 파일을 둘이 고치는 것 같으면 사용자에게 알린다
- 끝: handoff 스킬 → 저널(이벤트 + 남은 것) + claim status + `collab.sh check` + push

## 5. 멈추고 사용자에게 묻는 조건
허브 파일 차단 · 같은 파일을 동료가 만지는 중인데 같은 부분을 고쳐야 함 · 자동 rebase 충돌 · 받은 이벤트가 내 작업과 모순 · 동료가 같은 것을 만들고 있음.
에이전트가 알아서 "조심해서" 진행하지 않는다.

## 6. 범위와 완료
요청받은 것만 한다. 지나가다 본 리팩터링·리네임·포맷 정리는 하지 않는다 (동료의 충돌이 된다). 아이디어는 저널 `rule` 이나 `ask` 로.
"끝났다" 전에: 빌드·테스트 통과(있으면), 저널 작성, push 됨. 검증 안 한 것을 통과했다고 말하지 않는다.

## 7. 커밋과 언어
작고 의미 단위로. 에이전트가 의미 있는 부분을 썼으면 `Assisted-by: <모델명>` 트레일러. `--force` 금지 (기본이 merge 라 필요 없다). 남의 브랜치에 push 금지 — 단 이어받기로 claim `owner` 를 나로 바꾼 뒤부터는 내 브랜치다.
머지는 GitHub 에서 **squash 만**, 머지 시 브랜치 삭제. PR 제목 = claim goal. 브랜치 안의 커밋 메시지는 자유(sobaya 체크포인트 포함).
대화·문서·커밋은 한국어, 코드·식별자·브랜치명은 영어.

## 8. 개발 하네스 sobaya 와 함께 쓸 때
이 리포는 sobaya 워크스페이스의 `apps/<이름>` 에 산다. 구현은 sobaya 의 `tdd-set/bin/*`(승인된 실패 테스트 → 워커 구현 → 검증 → 체크포인트 커밋)가 하고,
협업 하네스는 그 바깥에서 "누가 무엇을" 을 관리한다. 겹치는 규칙은 sobaya 의 `AGENTS.md`·`tdd-set/AGENTS.md` 를 따른다.
- `spec.md` 와 `failed-test.md` 는 **브랜치(기능) 단위** 산출물이다. main 에 두지 않는다. handoff 가 PR 전에 `collab/journal/plans/<날짜-owner-slug>/` 로 옮기고 루트에서 지운다.
- sobaya 승인 상태가 있는 브랜치는 main 을 **rebase 가 아니라 merge** 로 따라잡는다 (pulse 가 자동 판별). 승인 기준이 커밋 sha 라서 rebase 하면 깨진다.
- 세션은 앱 안(`apps/<이름>`)에서 열어도 되고 sobaya 루트에서 열어도 된다. 루트에서는 `attach-sobaya.sh` 가 설치한 어댑터가 이 앱의 훅을 대신 부른다.
- sobaya 버전은 `harness/sobaya.lock` 이 팀 기준이다. digest 가 "다르다" 고 하면 `sh harness/attach-sobaya.sh sync`.

## 9. 위치
`collab/active/<slug>/` claim + 브랜치 산출물 · `collab/journal/` 이벤트 로그 · `harness/config.sh` 설정(HOTSPOTS 등) · `harness/hooks/` 훅 스크립트 · `.githooks/` git 훅 · `scripts/collab.sh` 도구 · `harness/attach-sobaya.sh` sobaya 결합 · 사람용 절차 `CONTRIBUTING.md`
