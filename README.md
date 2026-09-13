# Poem Collaboration Harness

여러 사람이 각자 AI 에이전트를 데리고 **한 리포에서 동시에** 일하기 위한 하네스 템플릿.
이 문서는 **에이전트가 이 리포를 이해하기 위한 것**이다. 사람이 그림으로 이해하려면 [docs/guide.md](docs/guide.md).

## 읽는 순서

1. `AGENTS.md` — 계약. 무엇이 강제되고, 언제 멈추고, 이벤트를 어떻게 쓰는가. (`CLAUDE.md` 는 심링크)
2. 이 문서 — 구조, 명령, 데이터 형식, 흐름.
3. 세션 시작 시 주입되는 협업 현황(digest). 훅이 없으면 `sh scripts/collab.sh digest --fetch`.

## 한 문장

내 에이전트가 동료 에이전트가 한 일을 **읽고**, 같은 파일을 동시에 고치지 **않고**, 끝날 때 다음 사람이 이어받을 수 있게 **남긴다**.
코드 컨벤션·테스트·병합 순서는 다루지 않는다. 그건 개발 하네스(sobaya)와 CI 의 몫.

## 정보는 어디로 흐르나

모든 상태는 git 원격의 파일과 ref 다. 서버·채팅·데이터베이스 없음.

| 내가 올리는 것 | 어디에 | 언제 | 동료가 보는 것 |
|---|---|---|---|
| claim (`collab/active/<slug>/claim.md`) | 내 브랜치 | start-work 첫 커밋·push | "누가 무엇을 만드는 중" |
| 작업 트리 스냅샷 | `refs/wip/<me>/<branch-slug>` (숨은 ref) | pulse (수정 15회 또는 15분마다) + 커밋마다 | "지금 편집 중인 파일 / 브랜치에 커밋된 파일" — 커밋 전이라도 |
| 저널 (`collab/journal/<날짜>-<me>-<slug>.md`) | 내 브랜치 | handoff | "무엇을 바꿨고 상대가 무엇을 해야 하나" (이벤트) |

동료 세션은 시작 때와 pulse 때 `git fetch` 로 이 셋을 읽는다. 저널은 전부가 아니라 **나에게 영향 있는 이벤트만** 주입된다.

## 구조

```
AGENTS.md                 계약 + sobaya 가 읽는 App facts (- Test:). CLAUDE.md 는 심링크
collab/
  active/<slug>/claim.md  브랜치 하나 = 디렉토리 하나. 브랜치 산출물(spec.md, failed-test.md …)도 여기
  journal/                이벤트 로그. append-only. plans/ 아래는 보관된 sobaya plan
  templates/              claim.md · journal.md
harness/
  hooks/                  guard · session-start · post-edit · stop · lib — 모든 판정의 본체
  config.sh               PROTECTED_BRANCHES · HOTSPOTS · PULSE_* · AUTO_REBASE · SYNC_MODE · SOBAYA_ROOT
  attach-sobaya.sh        sobaya 결합 attach|sync|update|check · sobaya.lock (팀의 sobaya 커밋)
  sobaya/                 루트 세션용 훅 어댑터, sobaya 에 보내는 제안
  init.sh · VERSION · CHANGELOG.md
scripts/collab.sh         유일한 CLI. 훅·git 훅·CI·다른 하네스가 전부 이것만 부른다
.agents/skills/           start-work · handoff (.claude/skills 는 심링크)
.claude/settings.json     Claude Code 훅 배선 → harness/hooks
.codex/hooks.json         Codex 훅 배선 → 같은 harness/hooks
.githooks/                pre-commit(guard 와 같은 판정) · pre-push(저널 경고). core.hooksPath 로 켬. 도구 무관
.github/                  PR 템플릿 · CI (tests · check · main 에서 prune · 주간 sobaya upstream 확인)
tests/                    hooks.sh(51) · loop.sh(19, 클론 둘) · sobaya.sh(19)
docs/guide.md             사람용 안내
```

## 명령 — `scripts/collab.sh`

| 명령 | 누가 부르나 | 하는 일 |
|---|---|---|
| `digest [--fetch] [--json]` | session-start 훅, 사람, 다른 하네스 | 나에게 온 질문 · 영향 있는 이벤트 · 동료 작업 중 · 같은 파일 만지는 중 · sobaya 버전. `--json` 은 아우터 루프 입력 |
| `pulse` | post-edit 훅 | wip push → fetch → 새 겹침·새 이벤트 알림 → main 뒤처졌으면 따라잡기(rebase, sobaya 승인 브랜치는 merge). 깨끗한 트리에서만, 충돌이면 abort |
| `guard <path>` / `guard --allow <path>` | guard 훅과 같은 판정을 CLI 로 | exit 2 = 차단. `--allow` 는 이 세션에서 허브 차단 해제 |
| `check [--base REF]` | handoff, CI | PR 규칙: claim 형식, 저널 존재와 필수 절, append-only, 남의 claim, 루트 plan 파일, 다른 브랜치와 겹친 파일(정보) |
| `wip` | `.githooks/post-commit` | 커밋마다 작업 트리 스냅샷 push + 브랜치 push(upstream 있으면) + 겹침 경고. sobaya 체크포인트 커밋도 여기 걸린다 |
| `pr-body` | handoff | claim goal + 저널 이벤트 + 겹친 파일 + sobaya review HEAD 로 PR 본문 |
| `precommit` / `prepush` | `.githooks/` | 스테이지된 파일마다 guard 판정 / 보호 브랜치로의 push 차단, 저널 없는 push 경고 |
| `prune` | CI (main push), 사람 | 머지·소멸 브랜치의 claim 삭제 |

## 강제되는 것 (판정은 `harness/hooks/lib.sh` 의 `check_write` 한 곳)

| 규칙 | 에디터 훅 | git pre-commit | CI |
|---|---|---|---|
| claim 없는 브랜치에서 수정 | 차단 | 차단 | claim 없으면 실패 |
| 보호 브랜치(main)에서 코드 수정 | 차단 | 차단 | — |
| 커밋된 저널 수정 · 남의 claim 수정 | 차단 | 차단 | 실패 |
| 동료가 지금 **편집 중**(커밋 전)인 허브 파일(HOTSPOTS) | 차단 (`--allow` 로 해제) | 경고 | — |
| 동료 브랜치에 커밋됐지만 미머지인 파일 · 그 외 겹침 | 알림 (선행 PR 제안) | — | 정보 |
| 보호 브랜치로 직접 push · 로컬 머지 | — | 차단 (pre-push, pre-merge-commit) | — |
| 코드 변경 있는데 저널 없이 종료 | Stop 훅이 1회 세움 | pre-push 경고 | 저널 없으면 실패 |
| 루트 `spec.md`·`failed-test.md` 가 PR 에 포함 | — | — | 실패 |

훅이 못 잡은 것은 CI 가 잡는다. 훅이 안 붙는 도구에서는 `digest`·`pulse` 를 직접 부른다 (AGENTS.md §0).

## 데이터 형식

**claim** — frontmatter 5키 + 선택 `next:`. scope 없음. "영역 점유" 가 아니라 "무엇을 만드는가". `next:` 는 다음에 만질 공유 파일 (동료 세션에 "곧 겹침" 으로 뜬다).
```
---
branch: feat/checkout
owner: solp            # git config collab.me
started: 2026-09-03
status: active         # active | paused | done
goal: 결제 페이지
---
```

**저널 이벤트** — `- <type> <경로?> <무엇> → <상대가 할 일>`. 한 줄 = 한 사건. 동료 에이전트가 읽는다.

| type | 주입 조건 (digest) |
|---|---|
| `changed` `migrated` `removed <경로>` | 경로가 내가 만진 파일이거나, 내 파일이 그 경로를 import |
| `added` `dep` `rule` | 항상 |
| `touching <경로>` | 경로가 내가 만진 파일 |
| `ask @핸들` | 나를 불렀으면 항상, `reply @상대` 가 내 저널에 생길 때까지 |
| `done` `reply` | 주입 안 함 (기록용) |

주입된 이벤트는 clone 별 `.claude/cache/seen` 에 기록돼 다시 뜨지 않는다. `ask` 만 예외.

## 흐름

```
start-work ──▶ (작업 · pulse · 커밋마다 wip) ──▶ handoff ──▶ PR(squash) ──▶ 브랜치 삭제 ──▶ CI prune
 브랜치           wip push/fetch                  저널          pr-body
 claim push       겹침 알림/차단                   claim status   제목 = goal
                  main 을 merge 로 따라잡기         check · push
```

- **start-work**: 보호 브랜치면 `git switch -c <type>/<slug> origin/main`. `collab/active/<slug>/claim.md` 작성, 첫 커밋으로 push. sobaya 를 쓰면 `install.sh` 로 이 브랜치의 `spec.md`·`failed-test.md` 생성.
- **중간**: 알림에 반응. 허브 파일 차단이면 사용자에게 알린다. 결정은 저널 `rule` 이벤트로.
- **handoff**: 저널(이벤트 + 남은 것) → claim status → (sobaya) `gate`·`review` 후 plan 을 `collab/journal/plans/` 로 이동 → `check` → push.
- **이어받기**: 남의 브랜치에서 digest 가 "owner 가 @X" 라고 알림 → 최근 저널 `남은 것` 읽고 owner 교체 → 첫 저널에 `reply @X`.

## 다른 하네스와의 접점

<a id="sobaya"></a>
- **sobaya (개발 하네스)**: 이 리포는 `<sobaya>/apps/<이름>` 에 산다. `attach-sobaya.sh attach` 가 앱 계약(AGENTS.md `- Test:`), sobaya 의 `install.sh`, 루트 세션용 어댑터, `harness/sobaya.lock` 을 처리한다. 승인 브랜치는 merge 로 따라잡음. sobaya 에 바라는 변경은 `harness/sobaya/PROPOSAL.md`.
- **sobaya 버전 동기화**: `harness/sobaya.lock` 이 팀 기준. digest 가 클론과 다르면 `sync` 를 권하고, 주간 CI 가 upstream 이 앞서면 이슈. 올릴 때 `update` 후 lock 커밋.
- **아우터 루프 (CI)**: `check` 의 "다른 열린 브랜치와 같은 파일", `digest --json` 의 `overlaps`. 자동 병합 순서는 그때.
- **다른 도구**: `collab.sh guard <path>` 로 같은 판정, `digest --json` 으로 같은 현황. 파일 위치로 리포 루트를 찾으므로 워크스페이스 루트에서 앱 파일을 건드려도 그 앱의 규칙이 걸린다.

## 검증

```sh
sh tests/hooks.sh    # 훅 판정 · Bash 감시 · 설정 일관성(Claude≡Codex) · git pre-commit
sh tests/loop.sh     # bare 원격에 클론 둘: 서로의 이벤트·질문·wip 겹침·자동 따라잡기·충돌 abort
sh tests/sobaya.sh   # 가짜 sobaya 루트: 어댑터 라우팅 · cwd 경로 · merge 모드 · lock · plan 규칙
```

훅을 고치면 셋 다 돌리고 `harness/CHANGELOG.md` 에 한 줄. 새 규칙에는 테스트를 붙인다.

## 시작

```sh
sh harness/init.sh <project-name> <my-handle>   # 플레이스홀더 · git config collab.me · rerere · core.hooksPath
# harness/config.sh 의 HOTSPOTS, AGENTS.md 의 - Test: 를 프로젝트에 맞게
# 합류자: git config collab.me <handle> && git config rerere.enabled true && git config core.hooksPath .githooks
```
