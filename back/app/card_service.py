import asyncio
import json
import logging
from typing import List, Dict

from .config import settings
from .claude_cli import run_claude

logger = logging.getLogger(__name__)

TEMPLATE_INSTRUCTIONS = {
    "definition": """정의형 카드를 만드세요.
- 앞면: "OO란?", "OO의 정의는?", "OO을 설명하시오" 형태
- 뒷면: 간결하고 정확한 답변 (1~3문장)

예시:
- 앞면: "피아제의 감각운동기란?"
- 뒷면: "출생~2세, 감각과 운동을 통해 세계를 탐색하는 인지 발달 단계"
""",

    "cloze": """빈칸형 카드를 만드세요.
- 앞면: 문장에서 **핵심 전문 용어/개념**을 _____로 대체
- 뒷면: 빈칸에 들어갈 정답 (정확한 용어)

## 빈칸 규칙 (매우 중요)
1. 빈칸은 반드시 **시험에 출제될 핵심 전문 용어, 고유명사, 학술 개념**이어야 합니다.
2. "할 수", "있게", "하는" 같은 일반적인 조사/동사를 빈칸으로 만들지 마세요.
3. 빈칸의 정답이 **하나로 특정**되어야 합니다. 여러 답이 가능한 빈칸은 만들지 마세요.
4. 문장만 읽고도 정답을 유추할 수 있을 정도로 **충분한 맥락**을 포함하세요.

좋은 예시:
- 앞면: "피아제의 인지발달 단계 중 _____기는 출생부터 약 2세까지의 시기이다."
- 뒷면: "감각운동"

- 앞면: "에릭슨의 심리사회적 발달 이론에서 영아기의 핵심 과업은 _____이다."
- 뒷면: "기본적 신뢰감 대 불신감"

나쁜 예시 (절대 이렇게 만들지 마세요):
- 앞면: "효과적인 한계 설정을 위해 규칙은 _____ 유지되어야 한다." → 답이 여러 개 가능
- 앞면: "자아통제는 타인의 요구에 _____ 하는 수준이다." → 빈칸이 핵심 용어가 아님
""",

    "comparison": """비교형 카드를 만드세요.
- 앞면: 헷갈리기 쉬운 두 개념을 비교하는 질문
- 뒷면: 각 개념의 핵심 차이를 간결히 대비

예시:
- 앞면: "동화(assimilation) vs 조절(accommodation)의 차이점은?"
- 뒷면: "동화: 기존 스키마에 새 정보를 맞춤 / 조절: 새 정보에 맞게 스키마를 변경"
""",

    "subjective": """주관식(서술형) 카드를 만드세요.
- 앞면: 서술형 개방 질문 ("~를 서술하시오", "~의 과정을 설명하시오", "~의 의의를 논하시오")
- 뒷면: 모범답안 3~5문장 (핵심 키워드를 반드시 포함 — AI 채점 기준이 됩니다)

예시:
- 앞면: "피아제의 인지발달 이론에서 동화와 조절의 개념을 설명하고, 두 과정의 관계를 서술하시오."
- 뒷면: "동화(assimilation)란 새로운 정보를 기존의 인지 구조(스키마)에 맞추어 해석하는 과정이다. 조절(accommodation)은 기존 스키마로 설명할 수 없는 새 정보에 맞게 스키마를 수정하거나 새로 만드는 과정이다. 두 과정은 상호보완적이며, 동화와 조절의 균형을 통해 평형화(equilibration)가 이루어지고, 이것이 인지 발달의 핵심 원동력이 된다."
""",
}


def _build_system_prompt(template_type: str) -> str:
    template_guide = TEMPLATE_INSTRUCTIONS.get(template_type, TEMPLATE_INSTRUCTIONS["definition"])

    return f"""당신은 시험 출제 경력 20년의 대학 교수입니다.
학생이 제출한 강의자료(PDF)를 읽고, 시험에 출제할 암기카드를 만들어야 합니다.

## 작업 순서 (반드시 이 순서로 사고하세요)

### 1단계: 내용 분석
텍스트를 꼼꼼히 읽고 아래를 파악하세요:
- 이 자료의 **주제와 학습 목표**는 무엇인가?
- **핵심 개념, 정의, 이론, 분류, 수치, 인물, 공식**은 무엇인가?
- 개념 간 **관계, 비교, 인과관계**는 무엇인가?
- 텍스트가 슬라이드/요약형이면 키워드에서 **숨겨진 의미**를 추론하세요.

### 2단계: 출제 포인트 선정
분석한 내용에서 **시험에 나올 수 있는 모든 포인트**를 선정하세요:
- 정의를 묻는 문제 (개념, 용어)
- 비교/구분 문제 (유사 개념 간 차이)
- 적용/사례 문제 (이론을 실제에 적용)
- 수치/분류 문제 (단계, 유형, 숫자)
- 하나의 개념에서도 **여러 각도**로 출제 가능하면 여러 카드를 만드세요.

### 3단계: 카드 작성

{template_guide}

## 생성 규칙

1. **근거 필수**: 원문에서 발췌한 근거(evidence)를 1~2문장으로 포함. 근거 없는 카드는 만들지 마세요.
2. **페이지 번호 필수**: 근거의 출처 페이지를 정확히 표기.
3. **한 카드 = 한 개념**: 하나의 카드는 하나의 개념만 테스트.
4. **언어**: 원문 언어와 동일하게 작성 (한국어 원문 → 한국어 카드).
5. **카드 수**: 핵심을 빠뜨리지 않는 것이 기준. 내용이 풍부하면 많이, 적으면 적게.
   텍스트가 짧아도(슬라이드, 요약) 개념이 있으면 반드시 카드를 만드세요.
6. **난이도 태그**: easy(기본 개념), medium(응용), hard(심화/비교).
7. **recommend 필드**:
   - true → 반드시 암기해야 할 핵심 문제 (전체의 절반 이상)
   - false → 보충 학습용

## 자체 검수 (출력 전 필수)

모든 카드를 아래 기준으로 검수하세요:
- 원문 근거와 **사실적으로 일치**하는가?
- 답이 **학술적으로 정확**한가?
- 질문이 **명확하고 모호하지 않은가**?
- 원문에 없는 내용을 **지어낸 것은 아닌가**?
- 부정확한 카드 → 수정, 근거 없는 카드 → 제외

## 출력 형식

반드시 JSON 배열만 출력하세요. 다른 텍스트, 설명, 마크다운을 추가하지 마세요.
학습 내용이 전혀 없는 경우(표지, 목차만)에만 빈 배열 []을 출력하세요.

[
  {{
    "front": "질문 또는 빈칸 문장",
    "back": "정답 또는 설명",
    "evidence": "원문에서 발췌한 근거 문장",
    "evidence_page": 페이지번호,
    "tags": "type:{template_type}, difficulty:easy|medium|hard",
    "recommend": true
  }}
]"""


def _build_user_prompt(pages: List[Dict]) -> str:
    parts = []
    for page in pages:
        parts.append(f"=== 페이지 {page['page_num']} ===\n{page['text']}")
    return "\n\n".join(parts)


def _parse_cards_json(text: str) -> List[Dict]:
    """Claude 응답에서 JSON 카드 배열을 추출합니다."""
    content = text.strip()

    if "```json" in content:
        content = content.split("```json", 1)[1].split("```", 1)[0]
    elif "```" in content:
        content = content.split("```", 1)[1].split("```", 1)[0]

    start = content.find("[")
    end = content.rfind("]")
    if start == -1 or end == -1:
        raise ValueError("JSON 배열을 찾을 수 없습니다.")

    return json.loads(content[start:end + 1])


MAX_RETRIES = 3  # 최초 1회 + 재시도 2회
RETRY_DELAYS = [2, 5, 10]  # 재시도 간 대기 (초)


async def _generate_chunk(pages: List[Dict], template_type: str, chunk_idx: int = 0) -> List[Dict]:
    """페이지 청크 하나에 대해 카드를 생성합니다. 실패 시 지수 백오프로 재시도."""
    system_prompt = _build_system_prompt(template_type)
    user_prompt = _build_user_prompt(pages)

    page_nums = [p["page_num"] for p in pages]
    total_text_len = sum(len(p["text"]) for p in pages)
    logger.info("청크 #%d 시작: pages=%s, 텍스트=%d자", chunk_idx, page_nums, total_text_len)

    last_error = None
    raw_text = ""
    for attempt in range(MAX_RETRIES):
        try:
            raw_text = await run_claude(system_prompt, user_prompt, model=settings.LLM_MODEL)
            cards_raw = _parse_cards_json(raw_text)
            logger.info("청크 #%d 파싱 성공 (시도 %d): %d장", chunk_idx, attempt + 1, len(cards_raw))
            break
        except (ValueError, json.JSONDecodeError) as e:
            last_error = e
            if attempt < MAX_RETRIES - 1:
                delay = RETRY_DELAYS[min(attempt, len(RETRY_DELAYS) - 1)]
                logger.warning("청크 #%d JSON 파싱 실패 (시도 %d/%d, %ds 후): %s | 응답 앞 300자: %s",
                               chunk_idx, attempt + 1, MAX_RETRIES, delay, e, raw_text[:300])
                await asyncio.sleep(delay)
            else:
                logger.error("청크 #%d JSON 파싱 최종 실패: %s | 응답 앞 500자: %s", chunk_idx, e, raw_text[:500])
                raise
        except RuntimeError as e:
            last_error = e
            if attempt < MAX_RETRIES - 1:
                delay = RETRY_DELAYS[min(attempt, len(RETRY_DELAYS) - 1)]
                logger.warning("청크 #%d CLI 오류 (시도 %d/%d, %ds 후): %s", chunk_idx, attempt + 1, MAX_RETRIES, delay, e)
                await asyncio.sleep(delay)
            else:
                logger.error("청크 #%d CLI 최종 실패: %s", chunk_idx, e)
                raise

    validated = []
    for card in cards_raw:
        if not all(k in card for k in ("front", "back", "evidence", "evidence_page")):
            logger.warning("청크 #%d 필수 필드 누락 카드 스킵: %s", chunk_idx, card)
            continue
        validated.append({
            "front": str(card["front"]).strip(),
            "back": str(card["back"]).strip(),
            "evidence": str(card["evidence"]).strip(),
            "evidence_page": int(card["evidence_page"]),
            "tags": str(card.get("tags", f"type:{template_type}")),
            "template_type": template_type,
            "recommend": bool(card.get("recommend", True)),
        })

    if not validated and cards_raw:
        logger.warning("청크 #%d: 파싱된 %d장 중 검증 통과 0장", chunk_idx, len(cards_raw))
    elif not validated:
        logger.warning("청크 #%d: 카드 0장 생성됨 (빈 응답)", chunk_idx)

    logger.info("청크 #%d 완료: %d장 검증 통과", chunk_idx, len(validated))
    return validated


MIN_RECOMMEND = 10
MAX_CARDS = 50
CHUNK_SIZE = 5  # 5페이지씩 분할


async def generate_cards(pages: List[Dict], template_type: str = "definition") -> List[Dict]:
    """PDF 텍스트에서 Claude를 이용해 암기카드를 생성합니다. 청크 병렬 처리 + 3단계 검수."""
    total_text_len = sum(len(p["text"]) for p in pages)
    logger.info("카드 생성 시작: %d페이지, 총 %d자, 템플릿=%s", len(pages), total_text_len, template_type)

    if len(pages) <= CHUNK_SIZE:
        result = await _generate_chunk(pages, template_type, chunk_idx=0)
    else:
        # 5페이지씩 분할 후, 텍스트가 너무 적은 청크는 이전 청크에 합침
        raw_chunks = [pages[i:i + CHUNK_SIZE] for i in range(0, len(pages), CHUNK_SIZE)]
        MIN_CHUNK_CHARS = 200
        chunks: List[List[Dict]] = []
        for chunk in raw_chunks:
            chunk_len = sum(len(p["text"]) for p in chunk)
            if chunks and chunk_len < MIN_CHUNK_CHARS:
                chunks[-1].extend(chunk)
                logger.info("짧은 청크 (%d자, %d페이지) → 이전 청크에 병합", chunk_len, len(chunk))
            else:
                chunks.append(list(chunk))
        logger.info("PDF %d페이지 → %d청크 병렬 처리", len(pages), len(chunks))

        tasks = [_generate_chunk(chunk, template_type, chunk_idx=i) for i, chunk in enumerate(chunks)]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        result = []
        failed_chunks = 0
        for i, r in enumerate(results):
            if isinstance(r, Exception):
                failed_chunks += 1
                logger.error("청크 #%d 예외 실패: %s: %s", i, type(r).__name__, r)
                continue
            logger.info("청크 #%d 결과: %d장", i, len(r))
            result.extend(r)

        if failed_chunks > 0:
            logger.warning("전체 %d청크 중 %d개 실패, %d장 수집", len(chunks), failed_chunks, len(result))

    # 50장 초과 시 truncate
    if len(result) > MAX_CARDS:
        result = result[:MAX_CARDS]

    # recommend=true 카드 자동 채택 (최소 10장 보장)
    recommended = [c for c in result if c.get("recommend", False)]
    if len(recommended) < MIN_RECOMMEND:
        non_rec = [c for c in result if not c.get("recommend", False)]
        recommended.extend(non_rec[:MIN_RECOMMEND - len(recommended)])
    rec_set = set(id(c) for c in recommended)
    for c in result:
        c["status"] = "accepted" if id(c) in rec_set else "pending"

    if not result:
        raise ValueError("생성된 카드가 없습니다. PDF 내용을 확인해주세요.")

    logger.info("최종 카드: %d장 (생성+자체검수 완료)", len(result))
    return result
