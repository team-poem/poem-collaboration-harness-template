---
name: onboard
description: 첫 세션 온보딩. 세션 시작 훅이 "setup" 또는 "join" 상태를 알리면 사용한다. 인사 → 상태에 맞는 절차(프로젝트 초기화 / 기존 프로젝트에 붙이기 / 새 프로젝트 / 합류) → 검증 → 첫 작업 제안. 사용자가 "/onboard" "처음부터" "설정 다시" 라고 해도 사용.
---

# onboard — 첫 세션

사람이 칠 명령은 없다. 대화로 끝낸다. 질문은 한 번에 하나. 이미 감지된 값(핸들, 원격, sobaya)은 다시 묻지 않고 확인만 한다.
상태와 감지 정보는 `sh scripts/collab.sh state`.

## 인사 (setup 상태)

> 안녕하세요, 포엠 협업 하네스입니다.
> 여러 사람이 각자 AI 에이전트와 한 리포에서 **동시에** 일할 때, 서로 뭘 하는지 읽고 같은 파일을 동시에 고치지 않게 해주는 도구예요. 3분이면 설정이 끝납니다.
> 어떻게 시작할까요?
> 1. **이 폴더를 프로젝트로 초기화** — 지금 폴더가 곧 프로젝트예요 (Use this template 로 만든 리포를 clone 한 경우)
> 2. **이미 있는 GitHub 프로젝트에 붙이기** — 기존 리포에 하네스 파일을 넣습니다
> 3. **새 프로젝트 만들기** — GitHub 리포 생성부터 합니다
> 4. **먼저 5분 설명 듣기**

## 인사 (join 상태)

> 안녕하세요, 포엠 협업 하네스입니다. 이 프로젝트는 이미 설정돼 있네요. 합류 절차만 하면 됩니다 — 핸들, git 훅, (있으면) sobaya 동기화. 1분이면 됩니다.
> 저널과 @멘션에 쓸 핸들을 뭐로 할까요? (영문, 공백·하이픈 없이. 예: solp, amazon)

그 다음 `sh harness/join.sh <핸들>` 을 실행하고 결과를 보여준다. 끝.

## 공통으로 묻는 것 (setup 경로 1·2·3)

| 순서 | 질문 | 왜 |
|---|---|---|
| 1 | 핸들 | 저널 파일명, `@멘션`, wip ref 의 주인 |
| 2 | 프로젝트 이름 (1·3 만) | AGENTS.md 제목, GitHub 리포명 |
| 3 | 테스트 명령 (예: `npm test`, `go test ./...`) | AGENTS.md `- Test:`. sobaya 가 읽는다. 아직 없으면 "나중에" 가능 |
| 4 | 허브 파일 | `harness/config.sh` HOTSPOTS. 스택을 보고 **먼저 제안**한다: Next.js+Prisma 면 `package.json pnpm-lock.yaml prisma/schema.prisma app/layout.tsx`, Go 면 `go.mod go.sum`. 사용자는 고치기만 |
| 5 | sobaya 를 쓰나 | 워크스페이스가 감지됐으면 "붙일까요?" 만. 없으면 "나중에 `attach-sobaya.sh attach`" 한 줄 |

## 경로 1 — 이 폴더를 프로젝트로 초기화
1. 질문 1~4.
2. `sh harness/init.sh <이름> <핸들>` → 출력 확인. HOTSPOTS 는 `harness/config.sh` 에 직접 쓴다. 테스트 명령은 AGENTS.md `- Test:` 에.
3. `git add -A && git commit -m "chore: init collaboration harness" && git push` (원격이 없으면 3번 경로의 리포 생성 단계로). 초기화 커밋은 하네스 파일만 바꾸므로 pre-push 가 통과시킨다.
4. `sh harness/github-policy.sh` — squash 머지만, 브랜치 자동 삭제, main 보호. private + Free 플랜이면 보호는 실패하고 git 훅이 대신한다고 사용자에게 말한다.
5. sobaya 워크스페이스가 감지됐고 사용자가 원하면 `sh harness/attach-sobaya.sh attach --test "<테스트 명령>"` 후 커밋.
6. 검증(아래).

## 경로 2 — 기존 GitHub 프로젝트에 붙이기
1. 리포 URL 또는 로컬 경로를 묻는다. 로컬에 없으면 clone (sobaya 워크스페이스가 있으면 `<sobaya>/apps/<이름>` 에).
2. 질문 1, 3, 4. 이름은 리포명.
3. `sh harness/install-into.sh <대상 경로> <이름> <핸들>` — 하네스 파일을 복사하고 그 안에서 init.sh 를 돌린다. 대상에 `AGENTS.md` 가 이미 있으면 `AGENTS.collab.md` 로 두고 사용자와 합친다 (App facts 절과 협업 규칙을 기존 AGENTS.md 에 넣는다).
4. 대상 리포에서 커밋·push. 이후는 경로 1 의 4~5.
5. 이 세션은 템플릿 폴더에서 열린 것이므로, 마지막에 "다음부터는 `<대상 경로>` 에서 세션을 여세요" 라고 말한다.

## 경로 3 — 새 프로젝트 만들기
1. 질문 1~4 + public 여부 확인: "조직이 Free 플랜이라 private 이면 GitHub 의 main 보호를 못 겁니다. public 으로 만들까요?" 기본 public.
2. `gh repo create team-poem/<이름> --template team-poem/poem-collaboration-harness-template --public --clone` (sobaya 워크스페이스가 있으면 `<sobaya>/apps/` 안에서 실행). gh 가 없거나 로그인 안 됐으면 GitHub 웹의 "Use this template" 를 안내하고 clone 뒤 경로 1.
3. 새 폴더에서 경로 1 의 2~5. 마지막에 "다음부터는 `<새 폴더>` 에서 세션을 여세요".

## 경로 4 — 먼저 5분 설명
`docs/guide.md` 의 "한 장 요약" 과 "그래서 어떻게 아는가" 를 대화로 풀어 준다. 그림은 그대로 보여준다. 쇼핑몰 이틀 예시는 사용자가 더 원할 때만. 끝나면 "그럼 1·2·3 중 어떻게 할까요" 로 돌아간다.

## 검증 (모든 경로 끝)
1. `sh scripts/collab.sh state` 가 `state=ready` 인지. 아니면 무엇이 빠졌는지 그대로 보여준다.
2. `sh scripts/collab.sh digest --fetch` 를 보여주고 "앞으로 세션을 켜면 이게 먼저 뜹니다" 라고 말한다.
3. 외울 규칙 셋: **시작에 claim, 끝에 저널, 남한테 할 말은 `ask @핸들`.** 나머지는 훅이 한다.
4. "첫 작업을 시작할까요? start-work 로 브랜치와 claim 을 만듭니다." 로 마친다.

## 셸 명령 승인이 안 나는 환경이면
파일 편집으로 할 수 있는 것(AGENTS.md 의 이름·`- Test:`, `harness/config.sh` 의 HOTSPOTS)은 직접 하고, git 설정·커밋·push·`collab.sh` 는 사용자가 붙여넣을 수 있게 명령을 순서대로 보여준다.

## 하지 않는 것
- 온보딩이 끝나기 전에 코드를 고치지 않는다.
- 감지된 값을 다시 묻지 않는다. 사용자가 이미 답한 걸 되묻지 않는다.
- 설명을 길게 하지 않는다. 경로 4 를 고른 사람에게만 설명한다.
