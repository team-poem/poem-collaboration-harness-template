# 하네스 변경 기록

하위 프로젝트는 `harness/VERSION` 으로 어느 템플릿에서 왔는지 안다. 필요한 항목만 가져간다.

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
