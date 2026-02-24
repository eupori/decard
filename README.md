# 데카드 (Decard)

PDF를 올리면 근거 포함 암기카드를 자동 생성하는 시험 대비 학습 도구입니다.

## 다운로드

- **웹:** https://decard.eupori.dev
- **Android APK:** [최신 릴리스](https://github.com/eupori/decard/releases/latest)

## 주요 기능

- PDF 업로드 → AI 카드 자동 생성 (정의형 / 빈칸형 / 비교형)
- AI 자동 채택 + 수동 검수 (채택 / 삭제 / 수정)
- 플래시카드 학습
- 보관함 — 과목별 폴더 관리 (로그인 필요)
- 카카오 로그인

## 기술 스택

- **프론트엔드:** Flutter (Web + Android)
- **백엔드:** FastAPI + SQLite
- **AI:** Claude API (카드 생성 + 채점)
- **배포:** Docker Compose + EC2
