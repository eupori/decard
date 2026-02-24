---
name: qa
description: 프로덕션 환경 QA 테스트 실행. 20명 시뮬레이션 유저로 E2E, 스트레스, 보안, 엣지케이스 테스트 수행.
disable-model-invocation: true
argument-hint: "[full|quick|stress|security] [api-url]"
---

# 프로덕션 QA 테스트

프로덕션 환경에서 시뮬레이션 유저를 생성하여 자동화된 QA 테스트를 실행합니다.

## 인자

- `$ARGUMENTS` 로 테스트 모드와 API URL을 받습니다.
  - 첫번째 인자: 테스트 모드 (기본값: `full`)
    - `full` — 20명 전체 QA (E2E 10명 + 특수 10명)
    - `quick` — 빠른 검증 3명 (definition/cloze/comparison 각 1명)
    - `stress` — 스트레스 테스트만 (5명 동시 업로드)
    - `security` — 보안 테스트만 (악성 입력 + 데이터 격리)
  - 두번째 인자: API URL (기본값: 프로덕션 URL from CLAUDE.md)

## 실행 절차

### 1단계: 환경 확인
- CLAUDE.md를 읽어서 프로덕션 API URL 확인 (기본: `https://decard-api.eupori.dev`)
- `back/.venv`의 Python venv 활성화
- 필요 패키지 확인: `requests`, `fpdf2` (없으면 설치)
- API 헬스체크 (`/health`)

### 2단계: 테스트 PDF 생성
- `fpdf2`로 한국어 교육 콘텐츠 PDF 생성 (3페이지, 심리학 내용)
- macOS 한국어 폰트 자동 감지 (`AppleSDGothicNeo.ttc`)

### 3단계: 모드별 테스트 실행

`tests/test_production.py` 스크립트를 활용하되, 인자에 따라 범위를 조절합니다.

#### `full` 모드 (기본)
```bash
cd back && source .venv/bin/activate
PYTHONUNBUFFERED=1 python ../tests/test_production.py
```

#### `quick` 모드
3명만 빠르게 검증:
```python
# definition, cloze, comparison 각 1명 → 3명 동시 업로드
# 각 유저: 업로드 → 완료 대기 → 카드 수 확인 → 자동 채택 확인 → 삭제
```

#### `stress` 모드
5명 동시 업로드 후 전원 완료 확인

#### `security` 모드
- 비-PDF 파일 업로드 (400 확인)
- 빈 파일 업로드 (400 확인)
- SQL injection in template_type (400 확인)
- XSS 파일명 (이스케이프 확인)
- 존재하지 않는 세션/카드 (404 확인)
- 타 유저 세션 접근 차단 (데이터 격리)

### 4단계: 결과 리포트

테스트 완료 후 아래 형식으로 결과를 보고합니다:

```
## QA 결과: X/Y PASSED (Z%)

### 성공
| 유저 | 테스트 | 카드 수 | 채택/대기 | 소요시간 |

### 실패 (있을 경우)
| 유저 | 테스트 | 원인 |

### 검증 항목
- [ ] 카드 생성: 13~30장 범위
- [ ] 자동 채택: accepted >= 10
- [ ] 보안: SQL injection / XSS 차단
- [ ] 격리: 유저 간 데이터 분리
- [ ] 동시성: N명 동시 → 전원 성공
```

### 5단계: 정리
- 테스트 세션 삭제 (정리 실패한 세션 ID 목록 출력)
- Docker 로그에서 에러 확인: `ssh eupori-server "docker logs --tail 50 decard-api-1 2>&1 | grep -E '(ERROR|실패|Exception)'"`

## 주의사항
- 카드 생성에 Claude API를 사용하므로 비용 발생 (full 모드: ~20회 API 호출)
- 각 생성에 60~120초 소요, full 모드 전체 약 15~20분
- Semaphore=3이므로 3명 이상 동시 시 대기 발생
- 테스트 후 잔여 세션 반드시 정리
