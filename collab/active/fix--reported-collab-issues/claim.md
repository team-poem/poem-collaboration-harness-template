---
branch: fix/reported-collab-issues
owner: solp
started: 2026-09-19
status: done
goal: cairn-landing 실전에서 보고된 협업 하네스 문제 9건을 고친다
---

## 메모
- 출처: cairn-landing 세션(2인·PR 10개) 보고. 9건 전부 재현 확인, 오용 없음.
- P0: merge 가 훅에 막힘(v0.0.4 회귀) · 내 다른 브랜치를 동료로 오인 · claim 디렉토리 경로 오판정
- P1: PR 본문이 사람용이 아님(겹침 한 줄·이벤트 통째)
- P2: 스택 브랜치(base) · 저널 정정(supersedes) · 머지된 PR 에 계속 커밋
