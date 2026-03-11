import io
import logging
import re
from typing import List, Dict, Tuple

import pdfplumber

logger = logging.getLogger(__name__)

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


def extract_text_from_pdf(file_content: bytes) -> dict:
    """PDF에서 페이지별 텍스트를 추출합니다.

    Returns:
        {"pages": List[Dict], "method": "pdfplumber", "is_math": bool}
    """
    pages = []
    with pdfplumber.open(io.BytesIO(file_content)) as pdf:
        for i, page in enumerate(pdf.pages):
            text = page.extract_text()
            if text and text.strip():
                pages.append({
                    "page_num": i + 1,
                    "text": text.strip(),
                })

    is_math = _detect_math_pdf(pages) if pages else False

    return {"pages": pages, "method": "pdfplumber", "is_math": is_math}


def validate_pdf(file_content: bytes, max_size_mb: int = 10) -> Tuple[bool, str]:
    """PDF 파일을 검증합니다 (헤더 + 크기만 빠르게 확인, pdfplumber 미사용)."""
    size_mb = len(file_content) / (1024 * 1024)
    if size_mb > max_size_mb:
        return False, f"파일 크기가 {max_size_mb}MB를 초과합니다 ({size_mb:.1f}MB)."

    if not file_content.startswith(b"%PDF"):
        return False, "PDF 파일이 아닙니다."

    return True, ""
