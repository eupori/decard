# 배치 테스트 보고서 — 카드 생성 품질 검증

**날짜:** 2026-02-28
**목적:** 다양한 학과/언어/형식의 PDF 26개로 카드 생성 파이프라인 전체 검증

---

## 1. 테스트 환경

| 항목 | 값 |
|------|-----|
| 서버 | uvicorn (--reload 없이 실행) |
| 모델 | claude-sonnet-4-5-20250929 |
| Semaphore | 3 (동시 CLI 호출 제한) |
| MAX_CARDS | 120 |
| CLI 타임아웃 | 180초 |
| 폴링 타임아웃 | 600초 |
| 폴링 간격 | 10초 |

---

## 2. 테스트 결과 요약

### 핵심 지표

| 지표 | 값 |
|------|-----|
| 성공률 | **26/26 (100%)** |
| 총 PDF 페이지 | 564p |
| 총 생성 카드 | **1,875장** |
| 총 채택 카드 | **1,291장** |
| 평균 카드/페이지 | **3.3장** |
| 평균 채택률 | **68.9%** |
| Plan Mode 에러 | **0건** (수정 전: 6건+) |

### 전체 결과

| # | 파일명 | 페이지 | 총 카드 | 채택 | 채택률 | 카드/페이지 |
|---|--------|--------|---------|------|--------|------------|
| 01 | economics_supply_demand.pdf | 3p | 14장 | 11장 | 78.6% | 4.7 |
| 02 | genetics_mendelian.pdf | 4p | 24장 | 19장 | 79.2% | 6.0 |
| 03 | algorithms_data_structures.pdf | 5p | 26장 | 20장 | 76.9% | 5.2 |
| 04 | statistics_bayes.pdf | 23p | 72장 | 47장 | 65.3% | 3.1 |
| 05 | psychology_intro.pdf | 36p | 120장 | 86장 | 71.7% | 3.3 |
| 06 | chemistry_principles.pdf | 4p | 22장 | 15장 | 68.2% | 5.5 |
| 07 | economics_monopoly.pdf | 3p | 17장 | 13장 | 76.5% | 5.7 |
| 08 | algorithms_dp.pdf | 8p | 45장 | 29장 | 64.4% | 5.6 |
| 09 | statistics_confidence.pdf | 16p | 71장 | 50장 | 70.4% | 4.4 |
| 10 | genetics_gene_structure.pdf | 3p | 20장 | 14장 | 70.0% | 6.7 |
| 11 | 심리학_감각과지각.pdf | 22p | 74장 | 53장 | 71.6% | 3.4 |
| 12 | 법학_민법기초.pdf | 21p | 115장 | 80장 | 69.6% | 5.5 |
| 13 | 경영학_마케팅관리.pdf | 31p | 101장 | 70장 | 69.3% | 3.3 |
| 14 | 회계학_IFRS회계원리.pdf | 42p | 120장 | 75장 | 62.5% | 2.9 |
| 15 | 경제학_수리경제학.pdf | 5p | 29장 | 21장 | 72.4% | 5.8 |
| 16 | 법학_행정법.pdf | 3p | 22장 | 16장 | 72.7% | 7.3 |
| 17 | 심리학_학습이론.pdf | 34p | 120장 | 77장 | 64.2% | 3.5 |
| 18 | 법학_민법이해.pdf | 38p | 120장 | 94장 | 78.3% | 3.2 |
| 19 | 경영학_재무관리.pdf | 21p | 69장 | 51장 | 73.9% | 3.3 |
| 20 | 경제학_분배와민주주의.pdf | 7p | 19장 | 15장 | 78.9% | 2.7 |
| 21 | code_python_recursion_dictionaries.pdf | 58p | 120장 | 88장 | 73.3% | 2.1 |
| 22 | code_python_functions_abstraction.pdf | 35p | 85장 | 56장 | 65.9% | 2.4 |
| 23 | code_python_sorting_searching.pdf | 38p | 120장 | 80장 | 66.7% | 3.2 |
| 27 | multilang_일본어기초.pdf | 18p | 90장 | 61장 | 67.8% | 5.0 |
| 28 | multilang_중국어문법작문.pdf | 41p | 120장 | 77장 | 64.2% | 2.9 |
| 29 | multilang_일본어문화.pdf | 45p | 120장 | 73장 | 60.8% | 2.7 |

### 카테고리별 분석

| 카테고리 | PDF 수 | 평균 카드/페이지 | 평균 채택률 |
|----------|--------|-----------------|------------|
| 영어 (MIT OCW) | 10 | 5.0 | 72.5% |
| 한국어 (KOCW) | 10 | 3.8 | 70.3% |
| 코드 (Python) | 3 | 2.6 | 68.6% |
| 다국어 (일본어/중국어) | 3 | 3.5 | 64.3% |

### 관찰

- **소형 PDF (3~8p)**: 카드/페이지 비율이 높음 (4.7~7.3) — 내용 밀도가 높은 PDF에서 카드가 집중적으로 생성
- **대형 PDF (30p+)**: MAX_CARDS=120 상한에 도달하는 경우 다수 (7/26) — 카드/페이지 비율 감소 (2.1~3.5)
- **코드 PDF**: 카드/페이지가 가장 낮음 (2.1~3.2) — 코드 슬라이드는 텍스트 밀도가 낮아 자연스러운 결과
- **다국어 PDF**: 정상 처리됨. 일본어/중국어 포함 카드도 올바르게 생성
- **채택률**: 60.8%~79.2% 범위. 목표 (60~75%) 에 부합

---

## 3. 테스트 PDF 목록

### 영어 (MIT OCW, 10개)
| # | 파일명 | 페이지 | 크기 | 과목 |
|---|--------|--------|------|------|
| 01 | economics_supply_demand.pdf | 3p | 0.11MB | 미시경제학 |
| 02 | genetics_mendelian.pdf | 4p | 0.09MB | 유전학 |
| 03 | algorithms_data_structures.pdf | 5p | 0.21MB | 알고리즘 |
| 04 | statistics_bayes.pdf | 23p | 0.13MB | 통계학 |
| 05 | psychology_intro.pdf | 36p | 0.18MB | 심리학 |
| 06 | chemistry_principles.pdf | 4p | 0.33MB | 화학 |
| 07 | economics_monopoly.pdf | 3p | 0.09MB | 미시경제학 |
| 08 | algorithms_dp.pdf | 8p | 0.14MB | 알고리즘 |
| 09 | statistics_confidence.pdf | 16p | 0.10MB | 통계학 |
| 10 | genetics_gene_structure.pdf | 3p | 0.11MB | 유전학 |

### 한국어 (KOCW, 10개)
| # | 파일명 | 페이지 | 크기 | 과목 |
|---|--------|--------|------|------|
| 11 | 심리학_감각과지각.pdf | 22p | 0.38MB | 심리학 |
| 12 | 법학_민법기초.pdf | 21p | 0.26MB | 법학 |
| 13 | 경영학_마케팅관리.pdf | 31p | 0.15MB | 경영학 |
| 14 | 회계학_IFRS회계원리.pdf | 42p | 0.39MB | 회계학 |
| 15 | 경제학_수리경제학.pdf | 5p | 0.20MB | 경제학 |
| 16 | 법학_행정법.pdf | 3p | 0.18MB | 법학 |
| 17 | 심리학_학습이론.pdf | 34p | 3.22MB | 심리학 |
| 18 | 법학_민법이해.pdf | 38p | 0.32MB | 법학 |
| 19 | 경영학_재무관리.pdf | 21p | 0.53MB | 경영학 |
| 20 | 경제학_분배와민주주의.pdf | 7p | 0.28MB | 경제학 |

### 코드 (MIT 6.0001, 3개)
| # | 파일명 | 페이지 | 크기 | 내용 |
|---|--------|--------|------|------|
| 21 | code_python_recursion_dictionaries.pdf | 58p | 1.30MB | 재귀/딕셔너리 |
| 22 | code_python_functions_abstraction.pdf | 35p | 0.47MB | 함수/추상화 |
| 23 | code_python_sorting_searching.pdf | 38p | 0.59MB | 정렬/검색 |

### 다국어 (3개)
| # | 파일명 | 페이지 | 크기 | 언어 |
|---|--------|--------|------|------|
| 27 | 일본어기초.pdf | 18p | 0.12MB | 한국어+일본어 |
| 28 | 중국어문법작문.pdf | 41p | 0.25MB | 한국어+중국어 |
| 29 | 일본어문화.pdf | 45p | 0.31MB | 일본어+한자 |

---

## 4. 발견된 문제와 해결

### P0: Plan Mode 오염 (Critical)

**증상:** Claude CLI가 JSON 카드 대신 "계획을 작성했습니다", "Plan Mode가 활성화되어 있어서" 같은 텍스트를 반환. 재시도 반복으로 Semaphore 낭비.

**근본 원인:** `~/.claude/settings.json`의 `"defaultMode": "plan"` 설정이 `claude -p` 호출에도 전파됨. CLI가 plan mode로 동작하여 모델이 계획/질문/확인 요청을 출력.

**해결:**
1. `claude_cli.py`: `--permission-mode default` 플래그 추가
   ```python
   cmd = ["claude", "-p", "--output-format", "json", "--permission-mode", "default"]
   ```
2. `card_service.py`: 시스템 프롬프트에 Plan Mode 금지 명시
   ```
   **절대 금지:**
   - 계획을 작성하지 마세요 (Plan Mode 금지)
   - 질문하거나 확인을 요청하지 마세요
   - JSON 배열 외의 어떤 텍스트도 출력하지 마세요
   첫 글자가 반드시 `[` 이어야 합니다.
   ```
3. 검수/보충 프롬프트에도 동일 적용

**검증:** 수정 후 Plan Mode 에러 0건, 26개 PDF 전수 성공 (이전: 6건 이상 에러)

### P1: uvicorn --reload가 백그라운드 태스크 소멸

**증상:** 로컬 개발 중 코드 수정 시 서버 재시작 → `asyncio.create_task()`로 생성된 카드 생성 태스크 소멸 → 세션이 "processing" 상태에서 영구 정지.

**해결:** 배치 테스트 시 `--reload` 없이 서버 실행
```bash
uvicorn app.main:app --host 0.0.0.0 --port 8001  # --reload 없이
```

**프로덕션:** Docker에서 `--reload` 미사용이므로 영향 없음.

### P2: 동시 세션 과부하

**증상:** 5개 이상 배치 동시 실행 시 Semaphore=3 병목으로 모든 세션 타임아웃.

**해결:** 동시 배치 수를 2개로 제한 (Semaphore=3에서 최적).

### P3: 폴링 타임아웃 600초 부족

**증상:** 대용량 PDF (30+ 페이지)와 동시 처리 시, Semaphore 경합으로 처리 시간이 600초를 초과. 배치 테스트에서 4건 "timeout"으로 기록 (서버에서는 정상 완료).

**영향 받은 파일:**
- 05_psychology_intro.pdf (36p) → 서버 완료: 120장 (86 accepted)
- 18_법학_민법이해.pdf (38p) → 서버 완료: 120장 (94 accepted)
- 22_code_python_functions_abstraction.pdf (35p) → 서버 완료: 85장 (56 accepted)
- 29_multilang_일본어문화.pdf (45p) → 서버 완료: 120장 (73 accepted)

**해결:** batch_test.py의 MAX_POLL을 600→900초로 상향 권장. 실제 사용자 앱에서는 폴링에 제한이 없으므로 영향 없음.

---

## 5. 개선된 코드 변경 사항

### `back/app/claude_cli.py`
- `--permission-mode default` 플래그 추가 → Plan Mode 전파 차단
- 환경 변수 정리 주석 강화

### `back/app/card_service.py`
- 카드 생성 프롬프트: "절대 금지" 섹션 추가 (Plan Mode 금지, JSON 강제)
- 검수 프롬프트: Plan Mode 금지 + JSON 강제 지시 추가
- 검수 시스템 프롬프트: "계획 작성 금지, 첫 글자 [" 명시

### `back/app/routes.py`
- 백그라운드 태스크 실패 시 세션 상태 업데이트에 try/except 추가 (이미 삭제된 세션 처리)

### `test_pdfs/batch_test.py`
- `sys.stdout.reconfigure(line_buffering=True)` — nohup 사용 시 실시간 출력
- `check_server()` — 테스트 전 서버 상태 확인
- `ConnectionError` 핸들링 — 서버 연결 실패 시 재시도

---

## 6. 배치 테스트 실행 가이드

### 전제 조건
```bash
# 서버 시작 (--reload 없이!)
cd back
source .venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8001
```

### 단일 PDF 테스트
```bash
cd test_pdfs
source ../back/.venv/bin/activate
python3 batch_test.py --result-file /tmp/single_test.json 01_economics_supply_demand.pdf
```

### 전체 배치 테스트 (2개 동시 권장)
```bash
# Batch A (영어+한국어 소형, 12개)
PYTHONUNBUFFERED=1 nohup python3 batch_test.py --result-file /tmp/batch_A.json \
  02_genetics_mendelian.pdf 03_algorithms_data_structures.pdf \
  04_statistics_bayes.pdf 05_psychology_intro.pdf \
  06_chemistry_principles.pdf 07_economics_monopoly.pdf \
  08_algorithms_dp.pdf 09_statistics_confidence.pdf \
  10_genetics_gene_structure.pdf 11_심리학_감각과지각.pdf \
  12_법학_민법기초.pdf 13_경영학_마케팅관리.pdf > /tmp/batch_A.log 2>&1 &

# Batch B (한국어 대형+코드+다국어, 12개)
PYTHONUNBUFFERED=1 nohup python3 batch_test.py --result-file /tmp/batch_B.json \
  14_회계학_IFRS회계원리.pdf 15_경제학_수리경제학.pdf \
  16_법학_행정법.pdf 17_심리학_학습이론.pdf \
  18_법학_민법이해.pdf 19_경영학_재무관리.pdf \
  20_경제학_분배와민주주의.pdf \
  22_code_python_functions_abstraction.pdf \
  23_code_python_sorting_searching.pdf \
  27_multilang_일본어기초.pdf 28_multilang_중국어문법작문.pdf \
  29_multilang_일본어문화.pdf > /tmp/batch_B.log 2>&1 &
```

### 결과 확인
```bash
# 로그 모니터링
tail -f /tmp/batch_A.log /tmp/batch_B.log

# JSON 결과 요약
python3 -c "
import json
for f in ['/tmp/batch_A.json', '/tmp/batch_B.json']:
    try:
        d = json.load(open(f))
        s = d['summary']
        print(f'{f}: {s[\"completed\"]}/{s[\"total_pdfs\"]} completed, {s[\"total_cards\"]} cards, {s[\"avg_cards_per_page\"]}/page')
    except: pass
"
```

---

## 7. 주의사항

1. **서버 실행 시 `--reload` 사용 금지** — 카드 생성 중 코드 수정하면 백그라운드 태스크 소멸
2. **동시 배치 2개 이하** — Semaphore=3 병목 방지
3. **대용량 PDF (30+ 페이지)** — 처리 시간 7~10분 이상 소요 가능 (동시 처리 시 Semaphore 경합)
4. **테스트 세션 정리** — 테스트 후 device_id='test-batch-runner' 세션 수동 정리 필요
5. **MAX_CARDS=120 상한** — 30p 이상 PDF에서는 상한에 도달할 수 있음. 충분한 수준이므로 조정 불필요
