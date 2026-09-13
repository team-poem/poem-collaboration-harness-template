---
name: start-work
description: 작업 브랜치를 만들고 claim(무엇을 만드는지)을 써서 push 한다. 새 작업을 시작할 때, 훅이 "claim 이 없습니다" 로 막았을 때, 남의 브랜치를 이어받을 때 사용.
---

# start-work — 작업 선언

파일을 고치기 전에 "무엇을 만드는지" 선언하고 push 한다. 훅이 claim 없는 수정을 막으므로 항상 첫 행동이다. 30초면 된다.

## 절차
1. 세션 시작 시 주입된 "동료 작업 중" 과 "지금 같은 파일을 만지는 중" 을 본다. 같은 걸 만들고 있으면 사용자에게 먼저 말한다.
2. 보호 브랜치면 `git fetch origin && git switch -c <type>/<slug> origin/main` (type: feat/fix/chore/docs/refactor).
3. `mkdir -p collab/active/<branch-slug>` (`/`→`--`), `collab/templates/claim.md` 를 `claim.md` 로 복사해 `owner`(= `git config collab.me`)와 `goal` 한 줄을 채운다.
4. claim 만 담은 첫 커밋을 만들고 push 한다. push 해야 동료 세션에 보인다.
   ```
   git add collab/active/<slug> && git commit -m "chore(collab): claim <branch>" && git push -u origin HEAD
   ```

## sobaya 로 구현할 브랜치라면 (harness/sobaya.lock 이 있으면 기본)
5. `bash <sobaya>/tdd-set/bin/install.sh .` (앱 안에서) 또는 `tdd-set/bin/install.sh apps/<이름>` (루트에서) — 이 브랜치의 `spec.md`, `failed-test.md` 가 없으면 만든다. main 에는 없으므로 새 브랜치마다 새로 생긴다.
6. 사용자와 spec.md 와 실패 테스트 초안을 채우고, 사용자가 승인하면 `approve.sh`. 이후 구현은 `step.sh`/`loop.sh` 가 한다. 이 파일들은 sobaya 가 보호하므로 에이전트가 직접 고치지 않는다.

## 이어받기 (남의 브랜치에서 계속할 때)
1. 그 브랜치로 switch. digest 가 "owner 가 @X" 라고 알려준다.
2. 그 브랜치의 최근 저널 `## 남은 것` 을 읽고 사용자에게 요약한다.
3. claim 의 `owner` 를 나로 바꾸고 `## 메모` 에 "YYYY-MM-DD @X → @나 이어받음". 커밋·push.
4. 내 첫 저널 이벤트에 `- reply @X <branch> 이어받았습니다`.

## 하지 않는 것
- claim 전에 코드를 고치지 않는다 (Write/Edit 도 Bash 도 막힌다).
- 다른 브랜치의 claim 을 수정하지 않는다.
