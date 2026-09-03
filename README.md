# Poem Collaboration Harness

팀 포엠에서 각자 AI 에이전트를 데리고 **한 리포에서 동시에** 일하기 위한 하네스.
지금은 solp·amazon 둘이지만, 누가 합류해도 이 문서와 `CLAUDE.md` 만 읽으면 바로 붙을 수 있게 만든다.

---

## 한 문장으로

> **내 에이전트가 동료 에이전트가 한 일을 읽고, 같은 파일을 동시에 고치지 않고, 끝날 때 다음 사람이 이어받을 수 있게 남긴다.**

코드 컨벤션, 테스트, 병합 순서는 여기서 다루지 않는다. 그건 나중에 붙는 개발 하네스(sobaya)와 CI 의 몫이다.
이 하네스는 **"누가 지금 무엇을 어디서 하고 있고, 무엇을 바꿨는가"** 를 사람과 에이전트가 읽을 수 있게 유지하는 것까지다.

## 왜 필요한가

가장 흔한 사고 하나로 설명한다.

> 월요일 10시. amazon 이 자기 브랜치에서 `lib/api/user.ts` 의 `getUser` 가 `id` 를 받도록 바꾼다.
> 11시. solp 의 Claude 가 main 기준으로 `getUser()` 를 호출하는 결제 페이지를 짠다.
> 두 PR 은 각각 통과한다. 머지하면 깨진다.

solp 의 Claude 는 알 방법이 없었다. amazon 의 브랜치를 보라고 아무도 안 시켰고, 봤다 해도 diff 수백 줄에서 "getUser 시그니처가 바뀌었다" 를 읽어내지 못한다.
사람은 카톡으로 "getUser 바꿨어" 라고 말하면 되지만, **에이전트는 그 카톡을 못 본다.** 이게 문제의 전부다.

같은 이유로 생기는 것들:

| 상황 | 결과 |
|---|---|
| 상대가 바꾼 함수·컴포넌트·스키마 위에 모른 채 코드를 짠다 | 머지 후 깨짐. 머지 충돌보다 비싸고 거의 매일 생긴다 |
| 둘 다 `components/ui/button.tsx` 에 prop 을 추가하고, 둘 다 `package.json` 에 패키지를 넣는다 | 저녁에 머지할 때 한꺼번에 충돌 |
| solp 가 세션을 끝냈고, 내일 amazon 의 에이전트가 그 브랜치를 이어받는다 | 무엇이 남았는지, 왜 그렇게 했는지 아무 데도 없다 |

## 그래서 어떻게 아는가

**모든 정보는 GitHub 원격에 있는 파일과 ref 로만 오간다.** 채팅도 서버도 없다.
amazon 쪽 훅이 세 가지를 원격에 올리고, solp 쪽 훅이 세션 시작 때와 수정 15회마다 `git fetch` 로 당겨와 읽는다.

```
amazon 쪽에서 일어나는 일              origin (GitHub)                      solp 쪽에서 읽는 것
──────────────────────────           ─────────────────────               ──────────────────────────
start-work: claim 커밋·push    ───▶  feat/settings 브랜치의          ──▶  "amazon · 사용자 설정 · 작업 중"
                                     collab/active/…/claim.md

훅이 수정 15회마다 작업 트리를  ───▶  refs/wip/amazon (숨은 ref,     ──▶  "지금 만지는 파일 (3분 전):
커밋 객체로 만들어 push               브랜치 목록에 안 보임)               button.tsx, package.json"
                                                                          → 내 파일과 겹치면 알림, 허브 파일이면 차단

handoff: 저널 커밋·push        ───▶  feat/settings 브랜치의          ──▶  "changed lib/api/user.ts getUser 가
                                     collab/journal/…amazon….md           id 를 받음 → 호출부 수정"
                                                                          → 내 파일이 lib/api/user 를 import 하면 주입
```

그래서 "amazon 이 작업했는지" 는 이렇게 갈린다.

- 아무것도 안 했다 → 원격에 아무것도 없다 → "없음".
- 브랜치를 파고 claim 만 push 했다 → "작업 중, 목표는 X" 까지 보인다.
- 한창 코딩 중이고 커밋은 안 했다 → wip 스냅샷 덕에 "지금 이 파일들 만지는 중" 이 보인다. 이벤트는 아직 없다.
- handoff 까지 했다 → 저널 이벤트가 내 코드에 영향 있는 것만 걸러져서 보인다.
- push 를 안 했다 → 안 보인다. 그래서 `start-work` 가 첫 커밋으로 push 하고, Stop 훅이 저널 없이 못 끝내게 한다.

위 사고는 이렇게 끝난다. amazon 의 handoff 가 남긴 한 줄 `changed lib/api/user.ts getUser 가 id 를 받음 → 호출부는 id 를 넘길 것` 이
solp 의 세션 시작 때 뜨고, solp 의 Claude 는 처음부터 `getUser(userId)` 로 짠다. 사람이 말해준 게 아무것도 없는데도.

## 핵심 가치 세 가지

**1. 서로 읽는다.** 세션을 켜면 동료가 바꾼 것 중 **나에게 영향 있는 것만** 자동으로 보인다. "amazon 이 어제 뭐 했더라" 를 사람이 설명할 필요가 없다. 저널은 사람 읽으라고 쓰는 회고가 아니라, 상대 에이전트가 읽는 **이벤트 로그** 다.

**2. 겹치면 안다.** 영역을 나누지 않는다. Next.js 같은 코드베이스에서 충돌은 디렉토리가 아니라 허브 파일 몇 개에서 나기 때문이다. 대신 **지금 누가 어느 파일을 만지는 중인지** 를 git 으로 본다. 커밋 전이라도.

**3. 가볍다.** 훅 4개, 스킬 2개, 명령 1개. 사람이 외울 규칙은 셋이다. **시작에 claim, 끝에 저널, 남한테 할 말은 `ask @핸들`.** 훅은 POSIX 셸이고 LLM 을 부르지 않고 판단이 안 서면 통과시킨다. 훅이 못 잡은 건 CI 가 잡는다.

## 어떻게 동작하는가

하루를 따라가 보자. solp 가 결제 페이지를, amazon 이 사용자 설정을 만든다.

```
 09:00  solp 가 claude 를 켠다
        ┌─ 세션 시작 훅 ─────────────────────────────────────────────────┐
        │ 나에게 온 질문      @amazon: 결제 웹훅이 세션 토큰을 읽나?        │
        │ 영향 있는 이벤트    [changed] lib/api/user.ts getUser 가 id 를 받음 │
        │                     [added] components/ui/toast.tsx 공용 토스트     │
        │ 동료 작업 중        feat/settings · @amazon · 사용자 설정          │
        │                     지금 만지는 파일 (12분 전): app/settings/…      │
        └───────────────────────────────────────────────────────────────┘
        에이전트는 getUser 호출부를 먼저 고치고, 토스트를 새로 만들지 않는다.

 09:05  start-work  →  브랜치 feat/checkout + claim(goal 한 줄) + push
        이 순간부터 amazon 의 세션에 "solp · 결제 페이지 · 작업 중" 이 보인다.

 10:00  둘 다 components/ui/button.tsx 를 만진다 (커밋 전)
        수정 15회마다 훅이 조용히 돈다(pulse):
          내 작업 트리 스냅샷을 refs/wip/solp 로 올리고, amazon 것을 당겨온다
        → "겹침: button.tsx 를 @amazon 도 만지는 중 (3분 전)"   ← 알림. 막지는 않는다
        → package.json 이면                                       ← 허브 파일. 막는다
          "차단: 지금 @amazon 이 만지는 중. 사용자에게 알리세요."

 11:00  amazon 이 먼저 머지했다
        다음 pulse 가 main 변경을 보고, 내 작업 트리가 깨끗하면 자동으로 rebase 한다.
        충돌이면 되돌리고 알린다. 충돌은 30분 뒤에 만나면 사소하고 9시간 뒤에 만나면 사고다.

 18:00  handoff  →  저널 한 파일 + claim status + 검사 + push
        ## 이벤트
        - changed lib/api/checkout.ts createOrder 가 userId 를 받음 → 호출부 수정
        - reply @amazon 웹훅은 토큰을 읽지 않음
        ## 남은 것
        - 결제 확인 화면. 쿠키 도메인에서 막힘
        저널 없이 끝내려 하면 Stop 훅이 한 번 세운다.

 다음날 amazon 의 세션에 solp 의 changed 와 reply 가 뜬다. 사람이 설명한 게 없는데도.
```

### 장치 여섯 개

| 장치 | 무엇 | 어떻게 |
|---|---|---|
| **claim** | "무엇을 만드는가" 한 줄 | `collab/active/<branch>/claim.md` 없으면 Write/Edit 도 Bash 쓰기도 막힘. 영역 점유가 아니라 의도 표시 |
| **digest** | 세션 시작 시 주입 | 원격 브랜치의 저널을 읽어 **나에게 영향 있는 이벤트만**: 내가 만진 파일·import 하는 파일의 `changed`, 모든 `added/rule`, 나를 부른 `ask` |
| **wip 스냅샷** | 지금 누가 어느 파일을 만지나 | pulse 가 작업 트리를 `refs/wip/<me>` 로 올림. 브랜치도 아니고 히스토리에도 안 남는다. 파일 단위 겹침을 낸다 |
| **허브 차단** | 동시 수정이 곧 충돌인 파일 | `harness/config.sh` HOTSPOTS (lockfile, 스키마 …). 동료가 지금 만지면 차단, 그 외 겹침은 알림 |
| **자동 rebase** | 짧은 divergence | main 이 바뀌고 트리가 깨끗하면 pulse 가 rebase. 충돌이면 abort + 알림. `rerere` 로 같은 충돌은 두 번 안 푼다 |
| **저널 = 이벤트** | 에이전트 간 언어 | `- <type> <경로> <무엇> → <상대가 할 일>`. append-only 라 머지 충돌이 구조적으로 없다. `ask` 는 `reply` 가 올 때까지 상대 세션에 계속 뜬다 |

### 이벤트 타입

| type | 뜻 | 상대 에이전트가 하는 일 |
|---|---|---|
| `changed <경로>` | 시그니처·동작이 바뀜 | 호출부 확인 |
| `added <경로>` | 새 공용 컴포넌트·유틸·훅 | 중복 만들지 않음 |
| `removed` `migrated` | 삭제, 스키마·데이터 변경 | 의존하는 곳 확인 |
| `dep` | 패키지 추가 | 알고 있음 |
| `rule` | 앞으로 지킬 규칙 | 따름 |
| `touching <경로>` `done <경로>` | 만지는 중 / 끝남 | 피함 / 자유롭게 |
| `ask @핸들` `reply @핸들` | 질문 / 답 | 사용자에게 전달, 답은 이벤트로 |

## 시작하기

```sh
# 새 프로젝트 (GitHub "Use this template" 후)
git clone <repo> && cd <repo>
sh harness/init.sh <project-name> <my-handle>       # 플레이스홀더 치환, git config collab.me, rerere
#  → harness/config.sh 의 HOTSPOTS 를 이 프로젝트의 허브 파일로 맞춘다
git add -A && git commit -m "chore: init collaboration harness" && git push

# 합류하는 사람 (클론 후 한 번)
git config collab.me <handle> && git config rerere.enabled true

claude          # 협업 현황이 먼저 뜬다. 첫 작업은 start-work
```

| 스킬 | 언제 | 하는 일 |
|---|---|---|
| `start-work` | 새 작업. 훅이 "claim 없음" 으로 막았을 때. 남의 브랜치 이어받을 때 | 브랜치 + claim + push |
| `handoff` | 세션 끝, PR 전 | 저널(이벤트 + 남은 것) + claim status + `collab.sh check` + push |

`scripts/collab.sh` 하나에 `digest` `pulse` `guard` `check` `prune` 이 있다. 훅도, 사람도, 나중에 붙는 하네스도 이것만 부른다.

## 구조

```
CLAUDE.md (= AGENTS.md)   에이전트 계약 (40줄)
CONTRIBUTING.md           사람이 지키는 것
collab/
  active/<slug>/          claim.md + 브랜치 산출물 (failed-test.md, spec.md …)
  journal/                YYYY-MM-DD-<owner>-<slug>.md · 이벤트 로그 · append-only
  templates/              claim / journal
.claude/
  settings.json           훅 배선 (팀 공유). 개인 조정은 settings.local.json
  hooks/                  guard · session-start · post-edit · stop · lib
  skills/                 start-work · handoff
harness/
  config.sh               보호 브랜치, HOTSPOTS, pulse 주기, AUTO_REBASE
  init.sh · VERSION · CHANGELOG.md
scripts/collab.sh         digest · pulse · guard · check · prune
tests/hooks.sh            훅 단위 검증
tests/loop.sh             클론 둘이 동시에 작업하며 실제로 서로를 보는지 검증
.github/                  PR 템플릿, CI (테스트 · check · main 에서 prune)
```

## 나중에 붙는 것들과 만나는 자리

- **개발 하네스 (sobaya, TDD 루프)**: 브랜치에 묶인 산출물(`failed-test.md`, spec)은 `collab/active/<slug>/` 에. 브랜치를 넘는 지식은 그쪽 brain 에. 저널에는 지식을 쓰지 않는다. 같은 판정을 쓰려면 `scripts/collab.sh guard <path>`, 현황을 가져가려면 `digest --json`. 워크스페이스 루트에서 앱 파일을 건드려도 파일 위치로 그 앱의 collab 을 찾는다.
- **CI 아우터 루프**: `check` 가 "다른 열린 브랜치와 같은 파일" 을 알려준다. 지금은 먼저 머지되는 쪽이 이기고 나중 쪽이 rebase 한다. 자동 병합 순서는 그때 `digest --json` 을 입력으로.

## 자주 겪을 것

- **동료 claim 이 안 보인다** → 상대가 push 를 안 한 것. `start-work` 가 첫 커밋으로 push 하는 이유.
- **"지금 만지는 파일" 이 오래됐다** → 상대의 pulse 가 안 돌았다. 스냅샷은 수정 15회 또는 15분마다 올라가고, 2시간 넘은 건 무시한다.
- **허브 파일을 꼭 지금 고쳐야 한다** → 상대와 한마디 하고 `scripts/collab.sh guard --allow <path>`. 이 세션에서만 풀린다.
- **자동 rebase 가 싫다** → `harness/config.sh` 의 `AUTO_REBASE=false`. 대신 pulse 가 "main 이 바뀌었다" 고만 알린다.
- **훅이 거슬린다** → `.claude/settings.local.json` 에서 개인적으로 조정. CI 검사는 그대로 돈다.
- **Codex 를 쓴다** → `AGENTS.md` 가 `CLAUDE.md` 심링크라 계약은 같다. 훅은 Claude Code 전용이니 CI 에 기댄다.
- **하네스를 고쳤다** → `tests/hooks.sh` 와 `tests/loop.sh`, 그리고 `harness/CHANGELOG.md` 에 한 줄.
