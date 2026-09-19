# fix/reported-collab-issues · solp · 2026-09-19
- claim: collab/active/fix--reported-collab-issues/claim.md

## 이벤트
- changed harness/hooks/lib.sh for_each_other_claim·wip_table 이 owner 가 나인 브랜치를 제외 → 내 다른 브랜치는 겹침·차단 판정에 안 잡힌다. 동료 목록에서 빠지고 digest 의 "내 다른 브랜치" 로만 보인다
- changed harness/hooks/lib.sh claim 디렉토리 경로 자신도 내 claim 으로 인정 → `git add collab/active/<slug>` 가 더는 막히지 않는다
- changed scripts/collab.sh precommit 이 머지·체리픽 중에는 소유권 규칙을 건너뜀 → 작업 브랜치에서 base 를 merge 로 따라잡는 게 실제로 된다 (문서와 훅의 모순 해소)
- changed .githooks/pre-merge-commit 은 보호 브랜치에서만 검사 → 작업 브랜치의 통합 커밋은 통과
- added scripts/collab.sh branch_merged_reason 과 pre-push 차단 → 이미 머지된 브랜치에 push 하면 막고 새 브랜치를 안내한다. gh 가 있으면 PR 상태, 없으면 origin 브랜치 내용이 base 에 들어갔는지로 판정
- changed scripts/collab.sh pr-body 는 goal → 변경 요약 → 검증 을 앞에 두고 이벤트·겹침은 details 로 접는다 → PR 본문을 사람이 읽을 수 있다
- rule claim 에 `base: <아래 브랜치>` 를 적으면 스택 PR 이 된다. check·pr-body·따라잡기가 그 기준을 쓴다
- rule 저널을 고칠 수 없으므로 내가 쓴 이벤트가 틀리면 새 저널에 `supersedes <경로|낱말>` 로 무효화한다. digest 가 낡은 줄을 숨긴다
- changed scripts/collab.sh 머지 충돌 안내가 "동료와 충돌" 로 단정하지 않는다 → 충돌 파일을 바꾼 동료가 있으면 이름을, 없으면 머지 여부 확인을 안내

## 남은 것
- cairn-landing 쪽 하네스 갱신은 그쪽 세션이 별도 chore 브랜치로 처리한다.
- gh 없이 squash 머지를 감지하는 폴백은 origin 브랜치 기준이라, 머지 후 이미 push 까지 한 브랜치는 못 잡는다. pre-push 가 그 직전을 막으므로 실사용에는 충분하다고 판단했다.

## 검증
- tests/hooks.sh 75 · tests/loop.sh 45 · tests/sobaya.sh 32 = 152개 통과
- 보고된 9건을 임시 리포에서 먼저 재현한 뒤 고쳤고, 각 건에 회귀 테스트를 붙였다
- POSIX sh 에서 `VAR=1 함수` 가 호출 뒤에도 변수를 남기는 것을 테스트가 잡아냈다 (내 브랜치 제외가 한 호출만 적용되던 버그)
