# sobaya 에 제안하는 작은 변경 (협업 하네스 결합용)

협업 하네스 쪽에서 우회해 둔 것들이다. sobaya 가 아래를 받아주면 우회가 사라지고 결합이 더 단순해진다. 전부 선택이다.

## 1. 승인 기준을 커밋 sha 가 아니라 내용 해시로
`contract_baseline` 이 "baseline 커밋이 HEAD 의 조상" 을 요구해서 rebase 를 하면 승인이 깨진다.
협업 하네스는 그래서 승인 상태가 있는 브랜치를 merge 로만 따라잡는다.
baseline 을 `spec.md`, `failed-test.md`, `AGENTS.md` 의 명령 줄, 승인된 테스트 파일들의 blob 해시로 잡으면 rebase 뒤에도 유효하다.
`state.json` 에 `baseline_tree` 같은 키 하나 추가.

## 2. plan/spec 경로를 앱 계약에서 지정
`_contract_text "$app" failed-test.md` 가 루트 고정이다. 두 사람이 동시에 다른 기능을 하면 같은 경로에 서로 다른 plan 이 생겨 머지 때 충돌한다.
협업 하네스는 PR 전에 plan 을 `collab/journal/plans/` 로 옮겨 우회한다.
앱 `AGENTS.md` 에 `- Plan: <경로>` `- Spec: <경로>` 를 허용하고 기본값을 지금처럼 루트로 두면, 브랜치별 `collab/active/<slug>/failed-test.md` 를 바로 쓸 수 있다.

## 3. 루트에 `CLAUDE.md -> AGENTS.md` 심링크
Claude Code 는 부모 디렉토리의 `CLAUDE.md` 를 읽지만 `AGENTS.md` 는 읽지 않는다. 심링크 하나면 provider 별 복사 없이 계약이 전달된다.
협업 하네스의 `attach-sobaya.sh` 가 지금은 클론에 로컬로 만들고 `.git/info/exclude` 에 넣는다.

## 4. `.gitignore` 에 `.claude/`
루트에서 Claude 세션을 열 때 협업 하네스가 `.claude/settings.local.json` 과 훅 어댑터를 놓는다. 지금은 `.git/info/exclude` 로 숨긴다.

## 5. `install.sh` 가 앱 `AGENTS.md` 가 심링크면 명확히 알려주기
협업 하네스 0.0.1 은 `AGENTS.md` 가 심링크였고 `_contract_text` 가 "Cannot read regular file" 로 거부했다. 0.0.2 에서 방향을 바꿔 해결했지만, `install.sh` 단계에서 "AGENTS.md 는 실제 파일이어야 한다" 고 말해주면 다음 사람이 덜 헤맨다.

## 6. `install.sh` 가 `core.hooksPath` 훅과 공존
협업 하네스는 `.githooks/pre-commit` 을 `core.hooksPath` 로 켜고, 그 안에서 sobaya 의 앱 pre-commit(`.git/hooks/pre-commit`)을 이어서 실행한다.
그런데 `install.sh` 는 `core.hooksPath` 가 잡혀 있으면 "existing pre-commit hook preserved" 로 중단한다. 협업 하네스는 install 동안 hooksPath 를 잠깐 풀었다 되돌리는 식으로 우회한다.
`--chain` 옵션이나 "hooksPath 훅이 sobaya 훅을 exec 하면 통과" 규칙이 있으면 우회가 사라진다.

## 7. 워커에게 허브 파일을 알리기
협업 하네스의 `harness/config.sh` HOTSPOTS(스키마, lockfile 등)는 동시 수정이 곧 충돌인 파일이다. 워커는 에디터 훅을 거치지 않으므로 지금은 아무것도 막지 못한다.
워커 프롬프트에 "이 목록은 수정하지 말고 필요하면 결과 보고에 적어라" 를 넣어 주면 사람이 선행 PR 로 처리할 수 있다.

## 8. 승인 상태를 브랜치별로
`state.json` 이 git-dir 당 하나라 같은 클론에서 브랜치를 오가면 `Baseline must be an ancestor of HEAD` 로 깨지고 `--replace` 마다 호출 한도가 리셋된다.
`sobaya/<branch-slug>/state.json` 이면 워크트리 없이도 브랜치 전환이 된다. 협업 하네스는 그때까지 "승인 브랜치가 있으면 새 브랜치는 워크트리" 로 안내한다.

## 9. review 바인딩과 plan 이동
협업 하네스는 PR 전에 `spec.md`·`failed-test.md` 를 `collab/journal/plans/` 로 옮긴다(두 브랜치가 같은 루트 경로를 쓰면 충돌·승인 파괴). 이 커밋으로 HEAD 가 바뀌어 `review.head` 와 어긋난다.
gate/review 가 `collab/journal/plans/<...>/failed-test.md` 경로도 인식하거나, 2번(plan 경로 설정)이 되면 이동 자체가 필요 없다.
