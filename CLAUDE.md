# CLAUDE.md — 데카드 (Decard) 프로젝트 가이드

## 프로젝트 개요

**데카드**는 PDF를 올리면 시험 대비용 근거 포함 암기카드를 자동 생성하는 학습 도구.
타겟: 고등학생 ~ 대학생 ~ 자격증 준비생.

## 빠른 시작

### 백엔드 (FastAPI)
```bash
cd back
source .venv/bin/activate
uvicorn app.main:app --reload --port 8001
```

### 환경변수 (`back/.env`)
```
ANTHROPIC_API_KEY=sk-ant-...  # 필수
LLM_MODEL=claude-sonnet-4-5-20250929
DATABASE_URL=sqlite:///./decard.db
```

## API 엔드포인트

| Method | Path | 설명 |
|--------|------|------|
| GET | `/health` | 헬스체크 |
| POST | `/api/v1/generate` | PDF 업로드 + 카드 생성 (multipart: file + template_type) |
| GET | `/api/v1/sessions/{id}` | 세션(카드 목록) 조회 |
| PATCH | `/api/v1/cards/{id}` | 카드 상태/내용 수정 |
| POST | `/api/v1/sessions/{id}/accept-all` | 전체 채택 |
| GET | `/api/v1/sessions/{id}/download` | CSV 다운로드 (Anki 임포트용) |

### 템플릿 타입
- `definition`: 정의형 ("OO란?")
- `cloze`: 빈칸형 ("___에 들어갈 말은?")
- `comparison`: 비교형 ("A vs B")

## 핵심 파일

| 파일 | 역할 |
|------|------|
| `back/app/main.py` | FastAPI 앱 + CORS |
| `back/app/config.py` | 환경변수 (Pydantic Settings) |
| `back/app/models.py` | SQLAlchemy 모델 + Pydantic 스키마 |
| `back/app/pdf_service.py` | PDF 텍스트 추출 (pdfplumber) |
| `back/app/card_service.py` | Claude 카드 생성 (핵심 로직) |
| `back/app/routes.py` | API 라우트 |
| `back/app/database.py` | SQLite + SQLAlchemy |

## 기술 스택

- **백엔드:** FastAPI + SQLAlchemy + SQLite
- **AI:** Claude Sonnet 4.5 (anthropic SDK)
- **PDF:** pdfplumber
- **프론트:** Flutter (iOS + Android + Web) — 구현 예정

## 주의사항

- PDF는 텍스트 PDF만 지원 (스캔/OCR은 후순위)
- 파일 크기 제한: 10MB, 페이지 제한: 100페이지
- `.env` 파일은 절대 커밋 금지
- `decard.db`도 커밋 제외 (.gitignore에 포함)
