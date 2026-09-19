# 하네스 변경 기록

하위 프로젝트는 `harness/VERSION` 으로 어느 템플릿에서 왔는지 안다. 필요한 항목만 가져간다.

## 0.0.9 — cairn-landing 실전 보고 9건 수정
2인·PR 10개로 실제 운영한 세션이 보고한 문제들. 전부 재현 후 수정.
- **작업 브랜치의 머지가 훅에 막히던 회귀(0.0.4)**: main 에 동료 claim 이 있으면 `git merge main` 이 항상 차단됐다. 문서는 merge 인데 훅이 막아 rebase + force 로 몰렸다. 통합 커밋(머지·체리픽)은 소유권 규칙 대상에서 제외. `pre-merge-commit` 은 보호 브랜치에서만 검사
- **내 다른 브랜치를 동료로 오인**: `for_each_other_claim`·`wip_table` 이 owner 가 나인 브랜치도 포함해 겹침 경고가 도배됐다. 이제 제외하고 digest 에 "내 다른 브랜치" 목록으로만. 알림 양 문제도 같이 해소
- **claim 디렉토리 경로 오판정**: `git add collab/active/<slug>` 는 막히고 `.../claim.md` 는 통과하던 것 수정
- **PR 본문이 사람용이 아니던 것**: goal → 변경 요약(diff --stat) → 검증 을 앞에 두고, 이벤트와 겹침은 `<details>` 로 접고 상위 5개 + "외 N개"
- **스택 브랜치**: claim 에 `base:`. `check`·`pr-body`·pulse 따라잡기가 이 기준을 쓴다
- **저널 정정**: `supersedes <경로|낱말>` 이벤트. 같은 owner 의 앞선 이벤트를 digest 에서 숨긴다
- **머지된 브랜치에 계속 커밋**: pre-push 가 차단(`COLLAB_ALLOW_MERGED_PUSH=1` 로 해제), digest·pulse 가 경고. gh 가 있으면 PR 상태로, 없으면 origin 브랜치 내용이 main 에 들어갔는지로 판정
- **머지 충돌 오진**: 내 브랜치가 머지돼서 생긴 충돌을 "동료와 충돌" 로 말하던 문구 수정. 충돌 파일을 바꾼 동료가 있으면 그 이름을, 없으면 머지 여부 확인을 안내

## 0.0.8 — PR 추가 작업 중 상태 전환 안정화
- 같은 PR 에서 편집 → 커밋 → 재편집하면 겹침을 다시 알린다. pulse 는 과거 전체가 아닌 직전 겹침과 비교하고, 수정 훅은 동료·브랜치·편집/커밋 상태를 구분한다. 브랜치명을 시간으로 표시하던 오류도 수정
- main 동기화 알림을 브랜치·기준 커밋·보류 이유별로 기록. sobaya 작업 종료 뒤 미커밋 변경이 남으면 커밋 안내를 새로 보내고, 동기화 성공 시 기록을 지운다
- 실제 로컬 원격과 클론 둘로 PR 추가 커밋·재편집을 재현. sobaya 보류 → 미커밋 → 체크포인트 → 동일 main 따라잡기와 충돌 abort 뒤 HEAD·인덱스·파일 보존 검증을 보강
- PR CI 의 GITHUB_HEAD_REF 가 임시 테스트 리포로 새지 않도록 분리. 남의 claim 변경과 detached HEAD 검사는 실제 스테이지·실패 이유·종료 상태까지 확인

## 0.0.7 — sobaya 는 바꾸지 않는다 (sobaya#4 흡수)
- amazon 의 결정에 따라 9개 요청을 전부 협업 하네스 규칙으로 흡수. `harness/sobaya/PROPOSAL.md` → `RULES.md` (성질 ↔ 우리 규칙 표)
- `collab.sh run -- <명령>`: 워커 실행 전 동료가 편집 중인 허브 파일이면 중단(`COLLAB_RUN_FORCE=1` 강행), 실행 후 워커가 건드린 허브 파일과 겹침 보고
- `collab.sh worktree <branch>`: 승인 브랜치가 있는 클론에서 새 브랜치를 워크트리로 (설정 복사)
- AGENTS.md §8, start-work 스킬에 반영

## 0.0.6 — 온보딩 실전 테스트 후 수정
- 실제 클론에서 Claude 를 띄워 온보딩을 끝까지 돌려봄. 초기화 커밋의 첫 push 를 우리 pre-push 가 막던 것 수정: 하네스 메타만 바뀐 push 와 원격에 없던 브랜치의 첫 publish 는 통과
- GitHub 정책(squash·브랜치 삭제·main 보호)을 `init.sh` 에서 빼서 `harness/github-policy.sh` 로. 첫 push 뒤 온보딩이 부른다 (보호를 먼저 걸면 초기화 커밋을 못 올린다)
- onboard 스킬: 셸 승인이 안 나는 환경에서의 대처 절

## 0.0.5 — 첫 세션 온보딩
- `collab.sh state` 가 리포 상태를 `setup`(플레이스홀더 남음) / `join`(개인 설정만 없음) / `ready` 로 판정. 세션 시작 훅이 준비 안 됐으면 협업 현황 대신 온보딩을 주입
- `onboard` 스킬: 인사 → 메뉴(이 폴더 초기화 / 기존 GitHub 프로젝트에 붙이기 / 새 프로젝트 / 5분 설명) 또는 합류 절차 → 검증 → 첫 작업 제안. 허브 파일은 스택을 보고 에이전트가 먼저 제안
- `harness/join.sh <핸들>`: 합류자 개인 설정(핸들·rerere·git 훅·sobaya sync). `harness/install-into.sh <리포>`: 기존 리포에 하네스 복사 + init (기존 AGENTS.md 보존)
- 템플릿 개발 중엔 `git config collab.onboarded true` 로 건너뜀

## 0.0.4 — 동시 작업 점검 후 수정
- 판정: squash/rebase 머지된 브랜치도 머지된 것으로 인식(유령 claim·중복 이벤트 제거). CI(detached HEAD)에서 자기 브랜치를 남으로 보던 것 수정. digest 한 실행 안 이벤트 중복 제거
- 처리량: 허브 파일 차단을 "동료가 지금 편집 중(커밋 전)" 으로 좁힘. 커밋됐지만 미머지인 겹침은 알림 + 선행 PR 제안. claim `next:` 로 "곧 겹침" 예고. 동료 브랜치 마지막 커밋 시각, 14일 방치 표시
- sobaya: 루트 어댑터가 `loop.sh apps/shop` 도 앱으로 라우팅(정규식). sobaya 가 항목 진행 중이면 pulse 의 따라잡기 보류. 승인 브랜치가 있으면 새 브랜치는 워크트리 안내. handoff 의 plan 보관 순서와 주의문
- git 흐름: 기본 따라잡기 merge. wip ref 를 `refs/wip/<me>/<branch>` 로(워크트리·무인 루프 공존). post-commit 이 스냅샷·브랜치 push(루프 중에도 보임). pre-push 가 보호 브랜치 직접 push 차단, pre-merge-commit 이 main 로컬 머지 차단. prune 이 죽은 wip ref 정리. init.sh 가 GitHub squash-only + 브랜치 자동 삭제 설정 시도. `pr-body` 로 PR 본문 자동
- 캐시(seen/asked/overlaps)를 브랜치별로. import 판정에 배럴·별칭 키. hooksPath 꺼진 클론 경고. Bash 감시 오탐(따옴표 안 `>`, `*.log`) 제거

## 0.0.3 — 도구 중립
- 훅 스크립트를 `harness/hooks/` 로, 스킬을 `.agents/skills/` 로 (`.claude/skills` 는 심링크). `.claude/settings.json` 과 새 `.codex/hooks.json` 은 같은 스크립트를 가리키는 얇은 배선
- git 훅 `.githooks/pre-commit`(스테이지 파일마다 guard 와 같은 판정, sobaya 앱 훅 이어서 실행)·`pre-push`(저널 경고). `init.sh` 가 `core.hooksPath` 로 켠다
- `collab.sh precommit|prepush`. AGENTS.md 에 "훅이 없는 환경이면 digest/pulse 를 직접" 절. `Skill(x)` 표현을 도구 중립으로
- attach-sobaya: install 동안 hooksPath 를 잠깐 풀어 sobaya 의 거부를 피함. 검사도 자체 방식으로

## 0.0.2 — 개발 하네스 sobaya 결합
- `AGENTS.md` 가 실제 파일, `CLAUDE.md` 가 심링크 (sobaya 는 심링크를 읽지 않는다). `## App facts` 절에 `- Test:` 등 앱 계약
- `harness/attach-sobaya.sh attach|sync|update|check`: 앱 계약 설치, 루트 세션용 훅 어댑터, `harness/sobaya.lock` 으로 팀의 sobaya 버전 고정
- sobaya 승인 브랜치는 main 을 rebase 대신 merge 로 따라잡음 (`SYNC_MODE=auto`)
- `spec.md`·`failed-test.md` 는 브랜치 단위. handoff 가 `collab/journal/plans/` 로 옮기고 `check` 가 main 유입을 막음
- 훅의 상대경로를 훅 cwd 기준으로 해석. sobaya 루트에서 `apps/<x>/…` 를 쓰는 Bash 도 그 앱 규칙으로 판정
- 주간 CI: upstream sobaya 가 lock 보다 앞서면 이슈

## 0.0.1 — 첫 릴리즈
- 협업 전용 하네스. 여러 사람이 각자 AI 에이전트를 데리고 한 리포에서 **동시에** 일하기 위한 것
- claim(무엇을 만드는가) 없이는 Write/Edit 도 Bash 쓰기도 막힘
- 저널은 에이전트가 읽는 **이벤트 로그** (`- <type> <경로> <무엇> → <상대가 할 일>`). digest 는 나에게 영향 있는 이벤트만 주입
- pulse 가 작업 트리 스냅샷을 `refs/wip/<me>` 로 올려 커밋 전이라도 파일 단위 겹침을 냄. 허브 파일(HOTSPOTS)만 차단, 나머지 알림
- main 이 바뀌면 트리가 깨끗할 때 자동 rebase, 충돌이면 abort + 알림
- 저널 없이 끝내면 Stop 훅이 한 번 세움
- 훅 4 · 스킬 2 · `scripts/collab.sh` (digest · pulse · guard · check · prune) · 테스트 58개
- 다른 하네스용 접점: `collab.sh guard <path>`, `digest --json`, 파일 위치로 리포 루트 탐색
