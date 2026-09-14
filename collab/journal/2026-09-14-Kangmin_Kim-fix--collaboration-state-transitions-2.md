# fix/collaboration-state-transitions · Kangmin_Kim · CI 후속 검증
- claim: collab/active/fix--collaboration-state-transitions/claim.md

## 이벤트
- changed tests/hooks.sh 임시 테스트 리포는 바깥 PR 의 GITHUB_HEAD_REF 를 제거하고 CI 문맥은 해당 검사에만 주입 → PR 환경에서 테스트를 돌려도 가짜 브랜치를 실제 PR 로 오인하지 않음
- changed tests/hooks.sh 남의 claim 변경 검사는 실제 스테이지와 차단 이유를 확인하고 detached HEAD 검사는 자기 파일 제외·동료 파일 겹침 보존을 확인 → 단순 명령 실패를 규칙 검사 성공으로 보지 않음

## 남은 것
- 초안 PR #1 의 Linux CI 재실행 결과와 리뷰 확인. 머지는 하지 않았다.
- 실제 sobaya 전체 워커 실행과 WIP 최신성 검증은 앞 저널의 후속 범위 그대로다.

## 검증
- 첫 GitHub CI 에서 hooks 검사 1개 실패. PR 환경변수 유입을 로컬에서도 재현한 뒤 수정했다.
- `GITHUB_HEAD_REF=fix/collaboration-state-transitions` 를 넣은 로컬 실행에서 hooks 71개, loop 30개, sobaya 모의 검증 32개가 통과했다.
- 테스트 환경 분리와 거짓 통과 제거를 최종 검증 범위에 추가했다. 런타임 규칙의 범위는 늘리지 않았다.
