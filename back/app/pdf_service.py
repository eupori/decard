import asyncio
import io
import logging
import re
from typing import List, Dict, Tuple, Awaitable, Callable, Optional

import pdfplumber

logger = logging.getLogger(__name__)

# OCR 폴백 임계값: pdfplumber로 추출된 페이지가 이 비율 미만이면 OCR로 재추출
_OCR_TRIGGER_RATIO = 0.5  # 50% 미만 페이지에서만 텍스트 추출되면 OCR
_OCR_MIN_CHARS_PER_PAGE = 30  # 페이지당 30자 미만이면 빈 페이지로 간주
_OCR_LANGS = "jpn+kor+eng+chi_sim"
_OCR_DPI = 200

OcrProgressCallback = Callable[[int, int], Awaitable[None]]


class OcrPageLimitExceeded(ValueError):
    """이미지 PDF가 OCR 페이지 제한을 초과한 경우."""
    pass

# 수학 기호 감지용 패턴
_MATH_UNICODE = set("∫∑∏∂∇→⇒⇔≤≥≠≈∞±√∈∉⊂⊃∪∩∀∃∅⊕⊗⟨⟩αβγδεζηθικλμνξπρστυφχψω")
_MATH_KEYWORDS = {"\\frac", "\\int", "\\sum", "\\begin{", "\\end{", "$$", "\\sqrt",
                   "\\lim", "\\infty", "\\partial", "\\nabla", "\\mathbb", "\\text{"}


def _detect_math_pdf(pages: List[Dict]) -> bool:
    """pdfplumber 추출 결과에서 수학 PDF 여부를 감지합니다.

    LaTeX 컴파일 PDF의 특징:
    1. 단어가 접합됨 (Orthogonalmatrix, A3-dimensionalvectorv)
    2. 수식 잔해 (QTQ=I, R ij = 0fori > j)
    3. 수학 유니코드 기호
    4. LaTeX 소스 잔재
    """
    sample = pages[:8]
    if not sample:
        return False

    all_text = " ".join(p["text"] for p in sample)
    total_chars = len(all_text)
    if total_chars < 100:
        return False

    score = 0
    reasons = []

    # 1. 수학 유니코드 기호 밀도
    math_char_count = sum(1 for c in all_text if c in _MATH_UNICODE)
    density = math_char_count / total_chars
    if density >= 0.005:
        score += 1
        reasons.append(f"unicode={density:.4f}")

    # 2. LaTeX 소스 잔재 (강한 신호)
    if any(kw in all_text for kw in _MATH_KEYWORDS):
        score += 2
        reasons.append("latex_source")

    # 3. 접합 단어 감지 — LaTeX PDF의 가장 강한 신호
    concat_words = re.findall(r'[a-z]{2,}[A-Z][a-z]{2,}', all_text)
    num_letter_concat = re.findall(r'[0-9][a-z]{3,}|[a-z]{3,}[0-9][a-z]{2,}', all_text)
    concat_count = len(concat_words) + len(num_letter_concat)
    if concat_count >= 5:
        score += 2
        reasons.append(f"concat={concat_count}")
    elif concat_count >= 2:
        score += 1
        reasons.append(f"concat={concat_count}")

    # 4. 수식 등호 패턴 (예: A=LU, QTQ=I, v+w)
    equation_patterns = re.findall(r'[A-Za-z][=+\-][A-Za-z]', all_text)
    if len(equation_patterns) >= 5:
        score += 1
        reasons.append(f"equations={len(equation_patterns)}")

    # 5. 고립된 숫자 행 (행렬 잔해)
    matrix_lines = re.findall(r'^\s*(?:\d+\s+){2,}\d+\s*$', all_text, re.MULTILINE)
    if len(matrix_lines) >= 2:
        score += 1
        reasons.append(f"matrix_lines={len(matrix_lines)}")

    is_math = score >= 3
    logger.info("수학 PDF 감지: score=%d, reasons=[%s] → %s",
                score, ", ".join(reasons), "수학" if is_math else "일반")
    return is_math


def _extract_with_pdfplumber(file_content: bytes) -> Tuple[List[Dict], int]:
    """pdfplumber 텍스트 레이어 추출 (동기). (pages, total_pdf_pages) 반환."""
    pages = []
    with pdfplumber.open(io.BytesIO(file_content)) as pdf:
        total_pdf_pages = len(pdf.pages)
        for i, page in enumerate(pdf.pages):
            text = page.extract_text()
            if text and text.strip() and len(text.strip()) >= _OCR_MIN_CHARS_PER_PAGE:
                pages.append({"page_num": i + 1, "text": text.strip()})
    return pages, total_pdf_pages


async def _ocr_pdf(
    file_content: bytes,
    on_progress: Optional[OcrProgressCallback] = None,
) -> List[Dict]:
    """이미지 PDF에서 OCR로 텍스트를 추출합니다 (한/일/중/영 다국어).

    페이지별로 to_thread를 통해 worker 스레드에서 실행, 이벤트 루프 블로킹 방지.
    """
    from pdf2image import convert_from_bytes
    import pytesseract

    images = await asyncio.to_thread(convert_from_bytes, file_content, dpi=_OCR_DPI)
    total = len(images)
    logger.info("OCR 시작: %d페이지, dpi=%d, langs=%s", total, _OCR_DPI, _OCR_LANGS)

    pages = []
    for i, img in enumerate(images):
        try:
            text = await asyncio.to_thread(pytesseract.image_to_string, img, lang=_OCR_LANGS)
        except pytesseract.TesseractError as e:
            logger.warning("OCR 실패 page=%d: %s", i + 1, e)
            text = ""
        except Exception as e:
            logger.warning("OCR 예외 page=%d: %s: %s", i + 1, type(e).__name__, e)
            text = ""
        if text and text.strip():
            pages.append({"page_num": i + 1, "text": text.strip()})
        if on_progress:
            try:
                await on_progress(i + 1, total)
            except Exception as e:
                logger.warning("OCR 진행률 콜백 실패: %s: %s", type(e).__name__, e)

    logger.info("OCR 완료: %d/%d 페이지에서 텍스트 추출", len(pages), total)
    return pages


async def extract_text_from_pdf(
    file_content: bytes,
    on_ocr_progress: Optional[OcrProgressCallback] = None,
    max_ocr_pages: int = 10,
) -> dict:
    """PDF에서 페이지별 텍스트를 추출합니다.

    1차: pdfplumber 텍스트 레이어 추출
    폴백: 텍스트 레이어가 거의 없으면 Tesseract OCR로 재추출 (이미지 PDF 대응)

    OCR 폴백은 worker 스레드에서 실행되어 이벤트 루프를 블로킹하지 않습니다.

    Args:
        file_content: PDF 바이트
        on_ocr_progress: OCR 페이지별 진행률 콜백 (page_num, total) → Coroutine
        max_ocr_pages: OCR 폴백 시 페이지 수 제한 (초과 시 OcrPageLimitExceeded)

    Returns:
        {"pages": List[Dict], "method": "pdfplumber"|"ocr", "is_math": bool}
    """
    pages, total_pdf_pages = await asyncio.to_thread(_extract_with_pdfplumber, file_content)

    method = "pdfplumber"
    extracted_ratio = len(pages) / max(total_pdf_pages, 1)

    # 텍스트 레이어가 비어있거나 너무 적으면 OCR 폴백
    if total_pdf_pages > 0 and extracted_ratio < _OCR_TRIGGER_RATIO:
        logger.info("OCR 폴백 트리거: %d/%d 페이지만 추출됨 (%.0f%% < %.0f%%)",
                    len(pages), total_pdf_pages, extracted_ratio * 100, _OCR_TRIGGER_RATIO * 100)

        if total_pdf_pages > max_ocr_pages:
            raise OcrPageLimitExceeded(
                f"이미지 PDF는 최대 {max_ocr_pages}페이지까지 지원합니다 "
                f"(현재 {total_pdf_pages}페이지). 텍스트 PDF로 변환하거나 페이지를 줄여주세요."
            )

        ocr_pages = await _ocr_pdf(file_content, on_progress=on_ocr_progress)
        if ocr_pages:
            pages = ocr_pages
            method = "ocr"

    is_math = _detect_math_pdf(pages) if pages else False

    return {"pages": pages, "method": method, "is_math": is_math}


def validate_pdf(file_content: bytes, max_size_mb: int = 10) -> Tuple[bool, str]:
    """PDF 파일을 검증합니다 (헤더 + 크기만 빠르게 확인, pdfplumber 미사용)."""
    size_mb = len(file_content) / (1024 * 1024)
    if size_mb > max_size_mb:
        return False, f"파일 크기가 {max_size_mb}MB를 초과합니다 ({size_mb:.1f}MB)."

    if not file_content.startswith(b"%PDF"):
        return False, "PDF 파일이 아닙니다."

    return True, ""
