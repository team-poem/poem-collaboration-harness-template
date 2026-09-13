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

## 어떻게 동작하는가 — 쇼핑몰을 처음 만드는 이틀

solp 와 amazon 이 Next.js + Prisma 로 쇼핑몰을 처음부터 만든다. 훅이 언제 무엇을 하는지 전부 적는다.
`[훅]` 표시가 하네스가 개입하는 순간이다. 그 외에는 평소처럼 Claude 와 일한다.

### 0일차 — 프로젝트 만들기 (solp)

```
$ gh repo create team-poem/shop --template team-poem/poem-collaboration-harness-template --private
$ git clone git@github.com:team-poem/shop && cd shop
$ sh harness/init.sh shop solp
  초기화 완료: shop · 나: @solp            ← 플레이스홀더 치환, git config collab.me solp, rerere 켬
```

`harness/config.sh` 의 허브 파일을 이 프로젝트에 맞게 고친다. 두 사람이 동시에 고치면 반드시 충돌 나는 파일들이다.

```sh
HOTSPOTS="package.json pnpm-lock.yaml prisma/schema.prisma app/layout.tsx lib/db.ts"
```

Next.js 를 깔고 첫 커밋, push. amazon 은 클론 후 한 줄만 한다.

```
$ git clone git@github.com:team-poem/shop && cd shop
$ git config collab.me amazon && git config rerere.enabled true
```

여기까지가 설정의 전부다. 이제 둘 다 `claude` 를 켠다.

### 1일차 오전 — solp: 상품 목록

```
$ claude
[훅 SessionStart] git fetch → 동료 브랜치·저널·wip 를 읽어 주입. 아직 아무것도 없다.
  # 협업 현황 · 나: @solp · 브랜치: main
  ## 내 claim        - 보호 브랜치. 코드 수정은 차단됩니다. 작업 시작은 start-work 스킬.
  ## 동료 작업 중    - 없음

solp: "상품 목록 페이지랑 상품 API 만들어줘. Product 모델도."

Claude 가 app/products/page.tsx 를 쓰려 한다
[훅 PreToolUse guard] 차단: 보호 브랜치(main)에서는 코드를 수정하지 않습니다. start-work 스킬 로 …
Claude → start-work:
  git switch -c feat/products origin/main
  collab/active/feat--products/claim.md   ← goal: 상품 목록 페이지 + 상품 API + Product 모델
  git commit -m "chore(collab): claim feat/products" && git push -u origin HEAD
  (이 순간부터 amazon 쪽 세션에 "feat/products · @solp · 작업 중" 이 보인다)

Claude 가 prisma/schema.prisma 에 Product 모델 추가, lib/api/products.ts, app/products/page.tsx 작성
[훅 PreToolUse guard] 매 수정마다 판정. claim 있음, 허브 파일(schema.prisma)이지만 지금 아무도 안 만지는 중 → 통과
[훅 PostToolUse post-edit] 15번째 수정에서 pulse:
  - 내 작업 트리(커밋 안 한 것 포함)를 커밋 객체로 만들어 refs/wip/solp 로 push   ← 브랜치 아님, 히스토리에 안 남음
  - git fetch → 새 겹침·새 이벤트·main 변경 없음 → 조용
```

### 1일차 오전 — amazon: 장바구니

```
$ claude
[훅 SessionStart]
  # 협업 현황 · 나: @amazon · 브랜치: main
  ## 동료 작업 중
  - feat/products · @solp · active · 상품 목록 페이지 + 상품 API + Product 모델
    지금 만지는 파일 (6분 전): prisma/schema.prisma lib/api/products.ts app/products/page.tsx
       ↑ solp 가 커밋을 안 했는데도 보인다. refs/wip/solp 를 fetch 해서 main 과 diff 한 것

amazon: "장바구니 만들어줘"
Claude → start-work: feat/cart, claim "장바구니 담기·조회 + Cart 모델", push

Claude 가 prisma/schema.prisma 에 Cart 모델을 추가하려 한다
[훅 PreToolUse guard] 차단: prisma/schema.prisma 는 허브 파일이고 지금 @solp(작업 트리 6분 전)이 만지는 중입니다.
  같은 파일을 동시에 고치면 머지 충돌이 납니다. 멈추고 사용자에게 알리세요. 상대가 끝나길 기다리는 게 원칙입니다.
Claude → amazon: "solp 가 지금 스키마를 고치는 중이라 막혔습니다. solp 의 Product 가 머지된 뒤 그 위에 Cart 를 얹는 게 안전합니다.
                 그동안 스키마가 필요 없는 장바구니 UI 부터 할까요?"
amazon: "그래, UI 먼저"
Claude 가 app/cart/page.tsx, components/cart/CartItem.tsx 작성 → 통과 (허브도 아니고 solp 가 안 만지는 파일)
```

### 1일차 점심 — solp 가 먼저 머지한다

```
solp: "여기까지 PR 올리자"
Claude → handoff:
  collab/journal/2026-09-03-solp-feat--products.md 를 새로 만든다
    ## 이벤트
    - added lib/api/products.ts getProduct(id), listProducts() → 상품 조회는 이걸 쓸 것
    - migrated prisma/schema.prisma Product 모델 추가 → prisma generate 필요
    - rule 서버 액션은 app/actions/ 아래에만 둔다
    ## 남은 것
    - 상품 이미지 업로드 미구현
  claim status: done
  scripts/collab.sh check → ✓ 규칙 위반 없음 · 통과
  git push, gh pr create
[CI] tests + collab.sh check 통과 → 머지
[CI main push] collab.sh prune → 머지된 feat/products 의 claim 디렉토리 삭제
```

### 1일차 오후 — amazon 쪽에 solp 의 변경이 도착한다

```
amazon 이 계속 UI 를 만드는 중
[훅 PostToolUse post-edit] 15번째 수정에서 pulse:
  - refs/wip/amazon push
  - git fetch → main 이 바뀜. 내 작업 트리가 깨끗함(방금 커밋함) → git rebase --autostash origin/main 자동 실행
  → [협업 알림]
    - main 이 갱신되어 자동으로 rebase 했습니다.
    - [added] lib/api/products.ts getProduct(id), listProducts() → 상품 조회는 이걸 쓸 것 (@solp)
    - [migrated] prisma/schema.prisma Product 모델 추가 → prisma generate 필요 (@solp)
    - [rule] 서버 액션은 app/actions/ 아래에만 둔다 (@solp)
       ↑ solp 저널의 이벤트 중 amazon 에게 영향 있는 것. added/migrated/rule 은 항상 주입된다
Claude → amazon: "solp 의 Product 가 머지됐습니다. rebase 했고, prisma generate 돌리고 이제 Cart 모델을 얹겠습니다."

Claude 가 prisma/schema.prisma 에 Cart 모델 추가
[훅 PreToolUse guard] 허브 파일. 지금 만지는 사람 있나? → solp 의 브랜치는 머지됐으니 wip 에 schema 변경이 없다 → 통과
Claude 가 lib/api/cart.ts 에서 getProduct(id) 를 import 해서 사용, app/actions/cart.ts 에 서버 액션 (rule 대로)

amazon: "오늘은 여기까지"
Claude 가 끝내려 한다
[훅 Stop] 코드 변경이 있는데 오늘 내 저널이 없습니다. handoff 스킬 로 … → Claude 가 멈추지 않고 handoff 를 한다
Claude → handoff:
  collab/journal/2026-09-03-amazon-feat--cart.md
    ## 이벤트
    - migrated prisma/schema.prisma Cart, CartItem 모델 추가 → prisma generate 필요
    - added lib/api/cart.ts addToCart(productId), getCart() → 장바구니는 이걸 쓸 것
    - ask @solp 상품 재고(stock)를 Product 에 둘 건가요, 별도 모델인가요? 장바구니 수량 검증에 필요
    ## 남은 것
    - 수량 변경 UI. 재고 검증은 solp 답 듣고
  claim status: active
  git push
```

### 2일차 아침 — solp: 상품 상세, 그리고 시그니처 변경

```
$ claude
[훅 SessionStart]
  ## 나에게 온 질문·메시지 (답은 내 저널 이벤트에 'reply @상대' 로)
  - @amazon (feat/cart): @solp 상품 재고(stock)를 Product 에 둘 건가요, 별도 모델인가요? 장바구니 수량 검증에 필요
  ## 동료 작업 중
  - feat/cart · @amazon · active · 장바구니 담기·조회 + Cart 모델
    지금 만지는 파일 (14시간 전): (없음 — 2시간 넘은 스냅샷은 "지금" 으로 치지 않는다)
Claude → solp: "amazon 이 재고를 어디 둘지 묻습니다."
solp: "Product 에 stock 컬럼으로. 그리고 상품 상세 페이지 만들어줘. URL 은 slug 로 가자."

Claude → start-work: feat/product-detail, claim, push
Claude 가 lib/api/products.ts 의 getProduct(id) 를 getProduct(slug) 로 바꾸고, prisma 에 stock, slug 추가, app/products/[slug]/page.tsx 작성
[훅 PreToolUse guard] schema.prisma: amazon 의 wip 는 14시간 전이라 "지금" 아님 → 통과
  (amazon 의 브랜치에 Cart 모델 변경이 커밋돼 있지만 아직 머지 전. 둘 중 나중에 머지되는 쪽이 rebase 한다 — check 가 알려준다)

solp: "PR 올리자"
Claude → handoff:
  collab/journal/2026-09-04-solp-feat--product-detail.md
    ## 이벤트
    - changed lib/api/products.ts getProduct 가 id 대신 slug 를 받음 → 호출부는 product.slug 를 넘길 것
    - migrated prisma/schema.prisma Product 에 slug(unique), stock 추가
    - reply @amazon 재고는 Product.stock. 별도 모델 없음
    ## 남은 것
    - 없음
  scripts/collab.sh check
    ✓ 규칙 위반 없음
    ! 다른 열린 브랜치와 같은 파일을 바꿈: prisma/schema.prisma(@amazon) — 먼저 머지되는 쪽이 이기고 나중 쪽이 rebase 한다
  git push, gh pr create → 머지
```

### 2일차 오전 — amazon: 시그니처 변경이 도착하고, 충돌은 작게 끝난다

```
$ claude
[훅 SessionStart]
  ## 나에게 온 질문·메시지
  - @solp (feat/product-detail): reply @amazon 재고는 Product.stock. 별도 모델 없음
  ## 동료가 바꾼 것 중 나에게 영향 있는 이벤트
  - [changed] lib/api/products.ts getProduct 가 id 대신 slug 를 받음 → 호출부는 product.slug 를 넘길 것 (@solp)
       ↑ amazon 의 lib/api/cart.ts 가 lib/api/products 를 import 하고 있어서 골라진 것. 다른 사람 코드였으면 안 떴다
  - [migrated] prisma/schema.prisma Product 에 slug(unique), stock 추가 (@solp)
    → changed/migrated 는 내 코드가 깨졌을 수 있다는 뜻. 작업 전에 해당 호출부를 확인한다.
Claude → amazon: "solp 가 getProduct 를 slug 기반으로 바꿨습니다. cart.ts 의 호출부 두 곳을 고쳐야 합니다.
                 재고는 Product.stock 이라고 답이 왔습니다. 먼저 main 을 따라잡겠습니다."

Claude: git rebase origin/main
  → prisma/schema.prisma 충돌 (solp 의 slug/stock 과 amazon 의 Cart 모델이 같은 파일)
  → 두 모델은 다른 위치라 Claude 가 양쪽 다 살려서 해결. rerere 가 기억해 둔다
  → getProduct(id) 호출 두 곳을 getProduct(product.slug) 로, 수량 검증에 product.stock 사용
[훅 PreToolUse guard] 매 수정 통과 (허브 파일 schema.prisma 는 이제 아무도 안 만지는 중)
[훅 PostToolUse post-edit] pulse: wip push, fetch, 조용

amazon: "수량 변경 UI 까지 하고 PR"
Claude 가 components/ui/button.tsx 에 loading prop 을 추가한다 (수량 버튼용)
[훅 PostToolUse post-edit]
  - 겹침: components/ui/button.tsx 를 @solp(작업 트리 3분 전)도 지금 만지는 중입니다. 작게 커밋하고 자주 pulse 하세요.
       ↑ solp 가 오늘 새 브랜치에서 같은 파일에 size prop 을 넣는 중. 허브 파일은 아니라 막지 않고 알린다
Claude → amazon: "solp 도 지금 button.tsx 를 만지는 중입니다. 저는 loading prop 한 줄이라 그냥 진행하고, 먼저 머지되는 쪽에 맞춰 rebase 하겠습니다."

Claude → handoff → 저널(events: changed lib/api/cart.ts addToCart 가 stock 검증 → 재고 부족 시 throw …), check, push, PR → 머지
```

### 이틀 동안 사람이 한 것

- solp 와 amazon 은 서로에게 **한 번도** 카톡을 안 보냈다. 재고 질문과 답도 저널 이벤트로 오갔다.
- 스키마를 둘이 동시에 고치는 사고는 1일차에 훅이 막았고, 2일차에는 먼저 머지된 쪽 위에 나중 쪽이 rebase 해서 작은 충돌로 끝났다.
- `getProduct` 시그니처 변경은 amazon 의 세션 시작 때 자동으로 떴다. amazon 의 Claude 는 cart.ts 를 고친 뒤에 새 코드를 짰다.
- 사람이 한 건 `start-work` 와 `handoff` 를 시킨 것, 훅이 물어볼 때 "UI 먼저" "그냥 진행" 같은 판단을 내린 것뿐이다.

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
AGENTS.md (= CLAUDE.md)   에이전트 계약 + sobaya 가 읽는 App facts. CLAUDE.md 는 심링크
CONTRIBUTING.md           사람이 지키는 것
collab/
  active/<slug>/          claim.md + 브랜치 산출물 (failed-test.md, spec.md …)
  journal/                YYYY-MM-DD-<owner>-<slug>.md · 이벤트 로그 · append-only
  templates/              claim / journal
.agents/skills/           start-work · handoff (.claude/skills 는 심링크)
.claude/settings.json     Claude Code 훅 배선 → harness/hooks
.codex/hooks.json         Codex 훅 배선 → 같은 harness/hooks
.githooks/                pre-commit(guard 와 같은 판정) · pre-push(저널 경고). 도구 무관
harness/
  hooks/                  guard · session-start · post-edit · stop · lib — 모든 판정의 본체
  config.sh               보호 브랜치, HOTSPOTS, pulse 주기, AUTO_REBASE, SYNC_MODE
  attach-sobaya.sh        sobaya 붙이기 · sync · update · check
  sobaya/                 루트 세션용 훅 어댑터, sobaya 에 보내는 제안
  sobaya.lock             (attach 후) 팀이 검증한 sobaya 커밋
  init.sh · VERSION · CHANGELOG.md
scripts/collab.sh         digest · pulse · guard · check · prune · precommit · prepush
tests/hooks.sh            훅 단위 검증
tests/loop.sh             클론 둘이 동시에 작업하며 실제로 서로를 보는지 검증
tests/sobaya.sh           sobaya 루트 세션 어댑터, merge 모드, plan 규칙 검증
.github/                  PR 템플릿, CI (테스트 · check · main 에서 prune · 주간 sobaya upstream 확인)
```

## Claude 든 Codex 든 같게 도는 이유

규칙은 세 겹인데, 아래 두 겹은 도구와 무관하다.

| 겹 | 어디서 | 누구에게 |
|---|---|---|
| **에디터 훅** | `.claude/settings.json`, `.codex/hooks.json` → 둘 다 `harness/hooks/*.sh` | Claude Code, Codex. 파일을 고치는 순간 막거나 알린다 |
| **git 훅** | `.githooks/pre-commit`, `pre-push` (`init.sh` 가 `core.hooksPath` 로 켠다) | 무엇으로 커밋하든. 스테이지된 파일에 guard 와 같은 판정 |
| **CI** | PR 마다 `collab.sh check` | 최종 방어선 |

계약은 `AGENTS.md` 하나(`CLAUDE.md` 는 심링크), 스킬은 `.agents/skills/` 하나(`.claude/skills` 는 심링크), 현황·판정은 `scripts/collab.sh` 하나다.
훅이 안 붙는 도구에서는 `collab.sh digest` 와 `pulse` 를 직접 부르면 같은 정보를 본다. `AGENTS.md` 가 그렇게 시킨다.

## 개발 하네스 sobaya 와 함께 쓰기

실제 구현은 [team-poem/sobaya](https://github.com/team-poem/sobaya) 가 한다. 사람이 승인한 실패 테스트를 하나씩 넣고, 워커가 구현하고, 하네스가 검증해서 커밋하는 루프다.
협업 하네스는 그 바깥에서 "누가 무엇을 하고 있고 무엇을 바꿨나" 를 관리한다. 둘은 이렇게 겹쳐진다.

```
~/sobaya/                      ← 각자의 sobaya 워크스페이스 (team-poem/sobaya 클론). brain, tdd-set, 스킬
  apps/
    shop/                      ← 팀 프로젝트 (이 템플릿으로 만든 리포). collab/, 훅, 저널
      AGENTS.md                ← 두 하네스가 같이 읽는 앱 계약. '- Test:' 는 sobaya 가, 나머지는 협업 규칙
      spec.md, failed-test.md  ← 브랜치(기능) 단위. main 에는 없다
      collab/active/<slug>/    ← claim. 브랜치 산출물도 여기
      harness/sobaya.lock      ← 팀이 검증한 sobaya 커밋
```

### 붙이기

```sh
cd ~/sobaya && git clone git@github.com:team-poem/shop apps/shop && cd apps/shop
sh harness/attach-sobaya.sh attach --test "npm test"
#  → AGENTS.md 의 - Test: 채움, sobaya 의 install.sh(spec.md·failed-test.md·pre-commit), 루트 세션용 훅 어댑터, harness/sobaya.lock
git add AGENTS.md spec.md failed-test.md harness/sobaya.lock && git commit -m "chore: attach sobaya" && git push
```

세션은 앱 안(`apps/shop`)에서 여는 게 기본이다. 앱의 `.claude/settings.json` 과 `.codex/hooks.json` 이 그대로 붙는다.
Claude 로 sobaya 루트에서 열면 `attach` 가 `~/sobaya/.claude/settings.local.json` 에 놓은 어댑터가 대상 앱을 찾아 그 앱의 훅을 대신 부른다. Codex 는 루트 훅 파일이 sobaya 리포에 추적되므로 앱 안에서 연다. 어느 쪽이든 커밋은 git 훅이 검사한다.

### 하루가 어떻게 달라지나

- `start-work` 가 브랜치와 claim 을 만든 뒤 `install.sh` 로 이 브랜치의 `spec.md`·`failed-test.md` 를 만든다. 사람이 spec 과 실패 테스트를 승인하면 `step.sh`/`loop.sh` 가 구현한다.
- 구현 중에도 협업 훅은 그대로 돈다. 워커가 고친 파일도 pulse 의 작업 트리 스냅샷에 들어가서 동료에게 "지금 만지는 파일" 로 보인다.
- sobaya 의 승인 기준은 커밋 sha 라서 rebase 하면 깨진다. 그래서 승인 상태가 있는 브랜치는 pulse 가 main 을 **merge** 로 따라잡는다 (자동 판별).
- PR 전에 `handoff` 가 `spec.md`·`failed-test.md` 를 `collab/journal/plans/<날짜-owner-slug>/` 로 옮긴다. main 에 plan 이 남으면 다음 사람의 브랜치와 같은 경로에서 충돌하고 승인이 깨지기 때문이다. `check` 가 이걸 막는다.

### sobaya 가 업데이트되면

sobaya 는 각자의 워크스페이스에 있으니 "우리 쪽 sobaya" 는 곧 각자의 클론이다. 팀이 같은 버전을 쓰게 하는 건 `harness/sobaya.lock` 하나다.

| 언제 | 누가 | 무엇 |
|---|---|---|
| upstream 에 새 커밋 | CI (매주 월요일, 또는 수동) | lock 보다 앞서면 "sobaya 업데이트 있음" 이슈를 열고 비교 링크를 붙인다 |
| 올리기로 함 | 아무나 한 명 | `sh harness/attach-sobaya.sh update` → 클론 pull, 앱 계약 재설치, lock 갱신 → 커밋·push |
| 다음 세션 | 나머지 | digest 가 "내 sobaya 가 팀 검증 버전과 다릅니다" → `sh harness/attach-sobaya.sh sync` |

`check` 로 언제든 클론·lock·upstream 세 버전을 볼 수 있다.

### sobaya 쪽에 바라는 것

지금은 협업 하네스가 우회해 둔 것들이다. `harness/sobaya/PROPOSAL.md` 에 적어 뒀다. 요지는 승인 기준을 커밋 sha 대신 내용 해시로, plan 경로를 앱 계약에서 지정할 수 있게, 루트에 `CLAUDE.md` 심링크. 받아주면 merge 강제와 plan 이동이 사라진다.

## CI 아우터 루프와의 자리

`check` 가 "다른 열린 브랜치와 같은 파일" 을 알려준다. 지금은 먼저 머지되는 쪽이 이기고 나중 쪽이 따라잡는다. 자동 병합 순서는 그때 `digest --json` 을 입력으로.

## 자주 겪을 것

- **동료 claim 이 안 보인다** → 상대가 push 를 안 한 것. `start-work` 가 첫 커밋으로 push 하는 이유.
- **"지금 만지는 파일" 이 오래됐다** → 상대의 pulse 가 안 돌았다. 스냅샷은 수정 15회 또는 15분마다 올라가고, 2시간 넘은 건 무시한다.
- **허브 파일을 꼭 지금 고쳐야 한다** → 상대와 한마디 하고 `scripts/collab.sh guard --allow <path>`. 이 세션에서만 풀린다.
- **자동 rebase 가 싫다** → `harness/config.sh` 의 `AUTO_REBASE=false`. 대신 pulse 가 "main 이 바뀌었다" 고만 알린다.
- **훅이 거슬린다** → `.claude/settings.local.json` 에서 개인적으로 조정. CI 검사는 그대로 돈다.
- **Codex 를 쓴다** → `AGENTS.md` 가 `CLAUDE.md` 심링크라 계약은 같다. 훅은 Claude Code 전용이니 CI 에 기댄다.
- **하네스를 고쳤다** → `tests/hooks.sh` 와 `tests/loop.sh`, 그리고 `harness/CHANGELOG.md` 에 한 줄.
