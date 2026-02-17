# 데카드 MVP 체크리스트 (3일)

> 목표: "PDF 올리고 → 근거 포함 카드 받고 → 검수하고 → 학습" 루프 완성

---

## Day 1: 백엔드 (API + AI) ✅ 완료

### 프로젝트 세팅
- [x] FastAPI 프로젝트 구조 생성 (`back/`)
- [x] 의존성 설치 (fastapi, uvicorn, pdfplumber, anthropic, python-multipart)
- [x] 환경변수 설정 (`.env` — ANTHROPIC_API_KEY, APP_ENV 등)
- [x] CORS 설정 (localhost + 로컬 IP 허용)

### PDF 처리
- [x] PDF 업로드 + 카드 생성 통합 엔드포인트 (`POST /api/v1/generate`)
- [x] pdfplumber로 페이지별 텍스트 추출
- [x] 페이지 번호 ↔ 텍스트 매핑 구조 저장
- [x] 파일 크기 제한 (10MB) + 텍스트 PDF 검증

### 카드 생성 (Claude API)
- [x] Claude Sonnet 4.5 프롬프트 설계 (근거 필수, 페이지 번호 포함)
- [x] 템플릿 3종 지원: 정의형 / 빈칸형(Cloze) / 비교형
- [x] 응답 파싱 → 필수 필드 검증
- [x] 생성 결과 SQLite 저장 (세션 ID 기반)
- [x] 긴 PDF 청크 분할 + 병렬 처리 (5페이지씩)

### 카드 조회/관리
- [x] 세션 목록 조회 (`GET /api/v1/sessions`)
- [x] 세션 상세 조회 (`GET /api/v1/sessions/{id}`)
- [x] 세션 삭제 (`DELETE /api/v1/sessions/{id}`)
- [x] 카드 상태 업데이트 (`PATCH /api/v1/cards/{id}`) — 채택/삭제/수정
- [x] 전체 채택 (`POST /api/v1/sessions/{id}/accept-all`)

### 데이터 모델
- [x] `Session` — id, created_at, filename, page_count, template_type, status
- [x] `Card` — id, session_id, front, back, evidence, evidence_page, tags, status, template_type

---

## Day 2: 프론트엔드 (Flutter) ✅ 완료

### 프로젝트 세팅
- [x] Flutter 프로젝트 생성 (`front/`)
- [x] 크로스플랫폼: Web + Android + iOS
- [x] API 클라이언트 (`services/api_service.dart`)
- [x] 다크/라이트 모드 테마 (`config/theme.dart`)
- [x] 눈 피로감 최소 팔레트 (민트 #C2E7DA + 블루 #6290C3 + 남색 #1A1B41)

### 홈 화면 (`home_screen.dart`)
- [x] 로고 + 타이틀 + 설명
- [x] PDF 파일 선택 (file_picker, 웹/모바일 호환)
- [x] 템플릿 선택 (정의/빈칸/비교 — 탭 UI)
- [x] "카드 만들기" 버튼 → 로딩 → 결과 페이지 이동
- [x] 로딩 상태 (스피너 + "약 15~30초 소요" 안내)
- [x] 다크/라이트 모드 토글 (우상단)
- [x] 이전 기록 목록 (최근 10개, 삭제 가능)

### 리뷰 화면 (`review_screen.dart`)
- [x] 카드 리스트 뷰 (앞면/뒷면/근거 표시)
- [x] 카드별 액션: 채택 / 삭제 / 수정 / 되돌리기
- [x] 수정 시 인라인 에디팅 (앞면/뒷면)
- [x] 근거 토글 (페이지 번호 + 원문 스니펫)
- [x] 상단 통계: 전체 / 대기 / 채택 / 삭제
- [x] 필터 칩 (전체/대기/채택/삭제)
- [x] 전체 채택 버튼
- [x] 학습하기 버튼

### 학습 화면 (`study_screen.dart`)
- [x] 풀스크린 플래시카드 (탭하여 앞/뒤 전환)
- [x] 랜덤 셔플 + 다시 섞기 버튼
- [x] 좌우 스와이프로 이전/다음
- [x] 진행률 바 (3/15)
- [x] 근거 보기 토글
- [x] 마지막 카드에서 "완료" 버튼

### 공통
- [x] 에러 상태 UI (업로드 실패, 생성 실패, 연결 실패)
- [x] 빈 상태 UI (카드 0장)
- [x] Android cleartext 허용 (로컬 테스트용)
- [x] 웹 file_picker 호환 (bytes vs path)

---

## Day 2.5: 빌드 + 테스트 ✅ 완료

### 빌드
- [x] Flutter 웹 빌드 + Chrome 테스트
- [x] Android APK 빌드 (release, 48.9MB)
- [x] Android Studio + SDK 36 + Java 21 설정
- [x] 로컬 IP 네트워크 테스트 (Mac → Android 폰)

### 버그 수정
- [x] 웹 file_picker `path` 에러 수정 (kIsWeb 분기)
- [x] 다운로드 한국어 파일명 인코딩 에러 수정 (RFC 5987)
- [x] FilledButton infinite width 에러 수정 (minimumSize override)
- [x] 카드 편집 모드 UI 겹침 수정 (액션 버튼 숨김)
- [x] AnimatedCrossFade 텍스트 겹침 수정 (단순 조건부 렌더링)

---

## Day 3: 마무리 + 배포

### UX 마무리
- [ ] 빈칸형 카드의 빈칸 스타일링 (`_____` → 하이라이트)
- [ ] 토스트/알림 일관성 (삭제, 채택 등)
- [ ] 모바일 터치 UX 세밀 확인 (버튼 크기, 스와이프)
- [ ] 앱 아이콘 커스텀 (현재 Flutter 기본 아이콘)

### 배포
- [ ] 백엔드: EC2 Docker Compose 배포 (기존 인프라 활용)
- [ ] 프론트: Vercel 웹 배포 (또는 별도 도메인)
- [ ] 도메인 설정 (decard.eupori.dev 또는 별도)
- [ ] HTTPS 확인
- [ ] API URL을 프로덕션으로 변경 (환경변수화)

### 테스트
- [ ] 텍스트 PDF 3종 테스트 (강의자료, 교재, 필기)
- [ ] 카드 생성 품질 확인 (근거 정확성, 템플릿별)
- [ ] 전체 플로우 E2E 테스트 (업로드→생성→검수→학습)
- [ ] 모바일 앱 최종 테스트

### 배포 후
- [ ] 공유 링크 생성 (지아현 + 테스터 배포용)
- [ ] 피드백 수집 방법 준비 (구글 폼 또는 카톡)
- [ ] Google Play Store 등록 준비 (앱 이름, 설명, 스크린샷)

---

## 변경 사항 (원래 계획 대비)

| 원래 | 변경 | 이유 |
|------|------|------|
| Next.js 프론트 | Flutter | 앱(Android/iOS) + 웹 동시 지원 |
| CSV 다운로드 (Anki) | 앱 내 학습 모드 | 외부 앱 의존성 제거, 자체 학습 기능 |
| 드래그앤드롭 업로드 | 탭 업로드 | 모바일 우선 UX |
| 코스 패스 결제 | 이후 | MVP는 무료 |

---

## 과감하게 뺀 것 (MVP 이후)

| 기능 | 이유 | 시기 |
|------|------|------|
| 로그인/회원가입 | 검증 단계에서 불필요 | 2주차 |
| 결제 시스템 | 무료로 써보게 한 후 판단 | 5-6주차 |
| 이력 페이지 | 홈 화면 10개 리스트로 충분 | 3-4주차 |
| 코스/워크스페이스 | 단일 업로드로 충분 | 3-4주차 |
| 중복 카드 감지 | 후순위 | 3-4주차 |
| OCR (스캔 PDF) | 텍스트 PDF만 지원 | 7주차+ |
| SRS 반복학습 | 단순 플래시카드로 시작 | 3-4주차 |
| 덱 공유/마켓 | 저작권 리스크 | 검토 후 |
| iOS 앱스토어 | Xcode 필요, 후순위 | 3-4주차 |

---

## 기술 스택 (실제)

| 구분 | 선택 | 비고 |
|------|------|------|
| 프론트 | Flutter 3.41.1 | Web + Android + iOS |
| 백엔드 | FastAPI + pdfplumber | uvicorn --reload |
| AI | Claude Sonnet 4.5 | 청크 병렬 처리 |
| DB | SQLite | SQLAlchemy ORM |
| 테마 | Material 3 | 다크/라이트, 민트 팔레트 |
| 폰트 | Noto Sans KR (Google Fonts) | |

---

## 성공 기준 (MVP)

| 지표 | 목표 |
|------|------|
| PDF→카드 생성 성공률 | 90% 이상 |
| 카드 채택률 (accept rate) | 60% 이상 |
| 생성 소요 시간 | 60초 이내 |
| "유용하다" 피드백 | 10명 중 5명 이상 |
| 결제 의향 | 10명 중 3명 이상 |
