import asyncio
import json
import logging
from typing import List, Dict

from .config import settings
from .claude_cli import run_claude

logger = logging.getLogger(__name__)

REVIEW_PERSONAS = [
    {
        "name": "교수",
        "system_prompt": """당신은 해당 분야의 대학 교수입니다.
생성된 암기카드를 원문과 대조하여 **학술적 정확성**을 검증합니다.

## 검증 항목
1. 카드의 내용(질문+답)이 원문 근거와 **사실적으로 일치**하는가?
2. 답이 학술적으로 정확한가? (오개념, 누락, 왜곡 없는가?)
3. 근거(evidence)가 실제 원문에 존재하는 문장인가?
4. 원문에 없는 내용을 지어낸 것은 아닌가?

## 출력 형식
반드시 아래 JSON 배열만 출력하세요.
[
  {"index": 0, "verdict": "pass"},
  {"index": 1, "verdict": "fix", "front": "수정된 질문", "back": "수정된 답"},
  {"index": 2, "verdict": "remove", "reason": "삭제 사유"}
]

verdict:
- "pass": 정확함, 수정 불필요
- "fix": 부정확하지만 수정 가능 → front/back 수정본 제시
- "remove": 원문 근거 없거나 완전히 잘못됨 → 삭제""",
    },
    {
        "name": "출제위원",
        "system_prompt": """당신은 국가시험 출제위원입니다.
암기카드의 **문제 품질과 명확성**을 검증합니다.

## 검증 항목
1. 질문이 명확하고 모호하지 않은가?
2. 정답이 **하나로 특정**되는가? (여러 답이 가능하면 fix 또는 remove)
3. 빈칸형(cloze): 빈칸이 **핵심 전문 용어**인가? (일반 조사/동사/형용사면 remove)
4. 정의형: 질문과 답이 정확히 대응하는가?
5. 시험 출제 기준에 부합하는가?

## 출력 형식
반드시 아래 JSON 배열만 출력하세요.
[
  {"index": 0, "verdict": "pass"},
  {"index": 1, "verdict": "fix", "front": "수정된 질문", "back": "수정된 답"},
  {"index": 2, "verdict": "remove", "reason": "삭제 사유"}
]""",
    },
    {
        "name": "수험생",
        "system_prompt": """당신은 시험을 준비하는 대학생입니다.
암기카드가 **실제 학습에 유용한지** 최종 검증합니다.

## 검증 항목
1. 질문만 보고 무엇을 묻는지 이해할 수 있는가?
2. 빈칸형: 주변 맥락만으로 정답을 **유일하게 추론**할 수 있는가?
3. 시험에 실제로 나올 법한 핵심 내용인가? (너무 지엽적이면 remove)
4. 답을 보았을 때 납득이 되고 학습 효과가 있는가?

## 출력 형식
반드시 아래 JSON 배열만 출력하세요.
[
  {"index": 0, "verdict": "pass"},
  {"index": 1, "verdict": "fix", "front": "수정된 질문", "back": "수정된 답"},
  {"index": 2, "verdict": "remove", "reason": "삭제 사유"}
]""",
    },
]


def _parse_review_json(text: str) -> list:
    """Claude 응답에서 JSON 배열을 추출합니다."""
    content = text.strip()

    if "```json" in content:
        content = content.split("```json", 1)[1].split("```", 1)[0]
    elif "```" in content:
        content = content.split("```", 1)[1].split("```", 1)[0]

    start = content.find("[")
    end = content.rfind("]")
    if start == -1 or end == -1:
        raise ValueError("JSON 배열을 찾을 수 없습니다.")

    return json.loads(content[start : end + 1])


async def _run_single_review(
    persona: Dict, cards: List[Dict], source_text: str, template_type: str
) -> Dict:
    """단일 페르소나 검수 실행. 결과를 {name, review_map} 형태로 반환."""

    cards_for_review = [
        {
            "index": i,
            "front": c["front"],
            "back": c["back"],
            "evidence": c["evidence"],
            "evidence_page": c["evidence_page"],
        }
        for i, c in enumerate(cards)
    ]
    cards_json = json.dumps(cards_for_review, ensure_ascii=False, indent=2)

    user_prompt = (
        f"## 원문 텍스트\n{source_text}\n\n"
        f"## 검수 대상 카드 (총 {len(cards)}장, 유형: {template_type})\n"
        f"{cards_json}\n\n"
        "위 카드들을 원문과 대조하여 하나씩 검수해주세요. "
        "모든 카드에 대해 verdict를 반드시 출력하세요."
    )

    raw = await run_claude(
        persona["system_prompt"], user_prompt, model=settings.LLM_MODEL
    )
    reviews = _parse_review_json(raw)

    review_map = {}
    for r in reviews:
        idx = r.get("index")
        if idx is not None:
            review_map[idx] = r

    return {"name": persona["name"], "review_map": review_map}


# verdict 우선순위: remove > fix > pass
_VERDICT_PRIORITY = {"remove": 0, "fix": 1, "pass": 2}


async def review_cards(
    cards: List[Dict], source_text: str, template_type: str
) -> List[Dict]:
    """3개 페르소나 병렬 검수. 결과를 병합하여 최종 카드 반환.

    병합 규칙:
    - 1명이라도 remove → 삭제
    - 1명이라도 fix (remove 없을 때) → 수정 적용 (교수 > 출제위원 > 수험생 우선)
    - 모두 pass → 통과
    """
    if not cards:
        return cards

    card_count_before = len(cards)

    # 교수 1명만 검수 (프로덕션 속도 최적화)
    tasks = [
        _run_single_review(REVIEW_PERSONAS[0], cards, source_text, template_type)
    ]
    raw_results = await asyncio.gather(*tasks, return_exceptions=True)

    # 성공한 검수 결과만 수집
    results = []
    for r in raw_results:
        if isinstance(r, Exception):
            logger.warning("[검수] 페르소나 호출 실패, 스킵: %s", r)
            continue
        results.append(r)

    if not results:
        logger.warning("[검수] 모든 페르소나 실패, 원본 카드 반환")
        return cards

    # 카드별로 3개 검수 결과 병합
    updated_cards = []
    for i, card in enumerate(cards):
        verdicts = []
        fix_candidate = None

        for res in results:
            review = res["review_map"].get(i)
            if not review:
                verdicts.append("pass")
                continue

            verdict = review.get("verdict", "pass")
            verdicts.append(verdict)

            # fix 후보: 우선순위 순서 (results는 교수→출제위원→수험생 순)
            if verdict == "fix" and fix_candidate is None:
                fix_candidate = review

        # 병합: remove가 하나라도 있으면 삭제
        if "remove" in verdicts:
            # 삭제 사유 로깅
            for res in results:
                review = res["review_map"].get(i, {})
                if review.get("verdict") == "remove":
                    logger.info(
                        "[%s] 카드 삭제: #%d, 사유: %s",
                        res["name"], i, review.get("reason", "N/A"),
                    )
            continue

        # fix가 있으면 수정 적용
        if "fix" in verdicts and fix_candidate:
            fixed = card.copy()
            if fix_candidate.get("front"):
                fixed["front"] = str(fix_candidate["front"]).strip()
            if fix_candidate.get("back"):
                fixed["back"] = str(fix_candidate["back"]).strip()
            updated_cards.append(fixed)
            logger.info("[검수] 카드 수정: #%d", i)
        else:
            updated_cards.append(card)

    logger.info(
        "[병렬 검수 완료] %d장 → %d장 (페르소나 %d명 참여)",
        card_count_before, len(updated_cards), len(results),
    )

    return updated_cards
