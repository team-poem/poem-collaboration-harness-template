# 하네스 설정. 훅과 scripts/collab.sh 가 읽는다. 키 이름은 바꾸지 않는다.

# 직접 커밋을 막는 보호 브랜치 (공백 구분). 첫 항목이 기준(main).
PROTECTED_BRANCHES="main master develop"

# 협업 메모리
CLAIM_DIR="collab/active"        # collab/active/<branch-slug>/claim.md + 브랜치 산출물
JOURNAL_DIR="collab/journal"     # YYYY-MM-DD-<owner>-<slug>.md, append-only

# 보호 브랜치에서 수정 가능한 경로 (공백 구분)
PROTECTED_BRANCH_ALLOW="collab/ harness/ .claude/ .github/ scripts/ tests/ CLAUDE.md AGENTS.md README.md CONTRIBUTING.md .gitignore"

# claim 없이도 수정 가능한 경로
CLAIM_EXEMPT=".claude/settings.local.json"

# 허브 파일: 동료가 지금 만지고 있으면 차단한다 (그 외 파일의 겹침은 알림만). 디렉토리는 / 로 끝낸다.
HOTSPOTS="package.json package-lock.json pnpm-lock.yaml yarn.lock prisma/schema.prisma"

# pulse(원격 당겨오기 + 내 작업 트리 스냅샷 올리기) 주기: 수정 N회마다, 또는 마지막 pulse 후 S초
PULSE_EVERY_EDITS=15
PULSE_MAX_AGE_SEC=900

# 동료의 작업 트리 스냅샷(refs/wip/<owner>)이 이보다 오래됐으면 "지금 만지는 중" 으로 보지 않는다
WIP_STALE_SEC=7200

# main 이 바뀌고 내 작업 트리가 깨끗하면 pulse 가 자동으로 rebase 한다. 충돌 시 즉시 abort 하고 알린다.
AUTO_REBASE=true

# 동료 저널을 며칠 전까지 읽을지 (미머지 브랜치 저널은 기간 무관하게 읽는다)
JOURNAL_LOOKBACK_DAYS=14
