# sobaya 와 함께 쓰는 규칙 — 협업 하네스 쪽에서 흡수한 것

sobaya 는 바꾸지 않는다 (amazon 결정, [sobaya#4](https://github.com/team-poem/sobaya/issues/4)). sobaya 의 성질과 그에 맞춘 우리 규칙을 적는다.

| sobaya 의 성질 | 우리 규칙 | 어디서 강제·안내 |
|---|---|---|
| 승인 기준이 baseline **커밋 sha** 라 rebase 하면 깨진다 | 승인 브랜치는 main 을 **merge** 로만 따라잡는다. 기본 `SYNC_MODE=merge` | pulse 가 자동. `SYNC_MODE=auto` 여도 승인 상태를 보고 merge |
| `spec.md`·`failed-test.md` 가 앱 **루트 고정** | 브랜치(기능) 단위로 쓰고 main 에는 두지 않는다. gate·review 뒤 **마지막 커밋**으로 `collab/journal/plans/<날짜-owner-slug>/` 에 옮긴다. 그 뒤 그 브랜치에서 sobaya 명령을 치지 않는다 | handoff 스킬. `check` 가 main 유입을 막음. `pr-body` 가 review HEAD 를 적음 |
| 워커는 에디터 훅을 **거치지 않는다** | sobaya 명령은 `scripts/collab.sh run -- …` 으로 감싼다. 실행 전 동료가 편집 중인 허브 파일이면 중단(`COLLAB_RUN_FORCE=1` 로 강행), 실행 후 워커가 건드린 허브 파일과 겹침을 보고. 커밋마다 post-commit 이 스냅샷을 올려 동료가 본다. pre-commit 은 허브 편집 경고 | `collab.sh run`, `.githooks/post-commit`, `precommit` |
| 승인 상태(`state.json`)가 **git-dir 당 하나** | 승인 브랜치가 있는 클론에서 새 브랜치는 워크트리: `scripts/collab.sh worktree <branch>`. wip ref 도 브랜치별이라 워크트리끼리 안 덮어쓴다 | start-work 스킬 |
| `install.sh` 가 `core.hooksPath` 가 있으면 **거부** | attach/sync 가 install 동안 hooksPath 를 잠깐 풀었다 되돌린다. 우리 `.githooks/pre-commit` 이 sobaya 의 `.git/hooks/pre-commit` 을 이어서 exec | `attach-sobaya.sh` |
| review 가 HEAD 에 **바인딩** | plan 이동 커밋이 review 뒤에 오므로 어긋난다. `pr-body` 가 review HEAD 와 현재 HEAD 를 적어 사람이 확인 | `pr-body` |
| 루트에 `AGENTS.md` 만 (Claude 는 `CLAUDE.md` 를 읽음) | `attach` 가 클론에 `CLAUDE.md -> AGENTS.md` 심링크를 만들고 `.git/info/exclude` 에 넣는다 | `attach-sobaya.sh` |
| 루트에 `.claude/` 가 없고 gitignore 도 없음 | 루트 세션 어댑터와 `settings.local.json` 을 `.git/info/exclude` 로 숨긴다 | `attach-sobaya.sh` |
| `_contract_text` 가 **심링크를 거부** | 앱의 `AGENTS.md` 가 실제 파일, `CLAUDE.md` 가 심링크 | 템플릿 구조, `install-into.sh` |
| `contract_clean` 이 **untracked 포함 깨끗한 트리** 요구 | 저널·claim·lock 을 커밋한 뒤 sobaya 명령. `.claude/cache/` 는 gitignore 라 안 걸림 | handoff 순서 |
| 항목 진행 중 HEAD 가 바뀌면 **죽는다** | pulse 는 lock 또는 `state.active` 가 있으면 따라잡기를 보류 | pulse |

## 이 표를 유지하는 방법
sobaya 가 업데이트되면(`attach-sobaya.sh update`) 위 성질이 바뀌었는지 `tests/sobaya.sh` 와 이 표를 같이 본다. 성질이 사라지면 규칙도 지운다.
