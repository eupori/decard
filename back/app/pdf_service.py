import io
import logging
import tempfile
import os
from typing import List, Dict, Tuple

import pdfplumber

from .config import settings

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
    import re

    sample = pages[:8]  # 표지/목차를 넘기기 위해 8페이지까지
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
    # 예: "Orthogonalmatrix", "A3-dimensionalvectorv", "0fori"
    # 소문자 뒤에 대문자가 바로 붙는 패턴 (camelCase가 아닌 접합)
    concat_words = re.findall(r'[a-z]{2,}[A-Z][a-z]{2,}', all_text)
    # 숫자-문자 접합 (예: "3componentsv1", "0fori")
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

    # 5. 고립된 숫자/문자 행 (행렬 잔해)
    # 공백으로 분리된 숫자만 있는 줄
    matrix_lines = re.findall(r'^\s*(?:\d+\s+){2,}\d+\s*$', all_text, re.MULTILINE)
    if len(matrix_lines) >= 2:
        score += 1
        reasons.append(f"matrix_lines={len(matrix_lines)}")

    is_math = score >= 3
    logger.info("수학 PDF 감지: score=%d, reasons=[%s] → %s",
                score, ", ".join(reasons), "수학" if is_math else "일반")
    return is_math


def _extract_with_pdfplumber(file_content: bytes) -> List[Dict]:
    """pdfplumber로 페이지별 텍스트 추출 (기존 방식)."""
    pages = []
    with pdfplumber.open(io.BytesIO(file_content)) as pdf:
        for i, page in enumerate(pdf.pages):
            text = page.extract_text()
            if text and text.strip():
                pages.append({
                    "page_num": i + 1,
                    "text": text.strip(),
                })
    return pages


def _extract_with_docling(file_content: bytes) -> List[Dict]:
    """Docling으로 LaTeX 수식 포함 텍스트 추출."""
    from docling.document_converter import DocumentConverter, PdfFormatOption
    from docling.datamodel.pipeline_options import PdfPipelineOptions
    from docling.datamodel.base_models import InputFormat

    # 임시 파일에 저장 (Docling은 파일 경로 필요)
    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
        tmp.write(file_content)
        tmp_path = tmp.name

    try:
        pipeline_options = PdfPipelineOptions()
        pipeline_options.do_formula_enrichment = True
        pipeline_options.do_table_structure = False  # 속도 최적화
        pipeline_options.do_ocr = False  # 텍스트 PDF만 대상

        converter = DocumentConverter(
            format_options={
                InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_options)
            }
        )

        result = converter.convert(tmp_path)

        # 페이지별 텍스트 그룹핑 — iterate_items()로 정확한 페이지 매핑
        page_texts: Dict[int, List[str]] = {}
        for item, _level in result.document.iterate_items():
            page_no = 1
            if hasattr(item, 'prov') and item.prov:
                page_no = item.prov[0].page_no

            # FormulaItem → LaTeX 형식, TextItem/SectionHeaderItem → 텍스트
            item_type = type(item).__name__
            if item_type == "FormulaItem":
                text = f"$${item.text}$$" if hasattr(item, 'text') and item.text else ""
            elif hasattr(item, 'text') and item.text:
                text = item.text
            else:
                continue

            if text and text.strip():
                page_texts.setdefault(page_no, []).append(text.strip())

        pages = []
        for page_no in sorted(page_texts.keys()):
            text = "\n\n".join(page_texts[page_no])
            if text.strip():
                pages.append({
                    "page_num": page_no,
                    "text": text.strip(),
                })

        logger.info("Docling 추출 완료: %d페이지, 총 %d자",
                     len(pages), sum(len(p["text"]) for p in pages))
        return pages

    finally:
        os.unlink(tmp_path)


def extract_text_from_pdf(file_content: bytes) -> dict:
    """하이브리드 PDF 텍스트 추출.

    Returns:
        {"pages": List[Dict], "method": str, "is_math": bool}
    """
    # 1단계: pdfplumber로 빠르게 추출
    pdfplumber_pages = _extract_with_pdfplumber(file_content)

    # 2단계: 수학 PDF 감지
    is_math = _detect_math_pdf(pdfplumber_pages) if pdfplumber_pages else False

    # 3단계: 수학이면 Docling 시도
    if is_math and settings.USE_DOCLING:
        logger.info("수학 PDF 감지 → Docling으로 재추출 시작")
        try:
            docling_pages = _extract_with_docling(file_content)
            if docling_pages:
                return {"pages": docling_pages, "method": "docling", "is_math": True}
            else:
                logger.warning("Docling 결과 없음, pdfplumber 폴백")
        except Exception as e:
            logger.warning("Docling 추출 실패, pdfplumber 폴백: %s: %s", type(e).__name__, e)

    return {"pages": pdfplumber_pages, "method": "pdfplumber", "is_math": is_math}


def validate_pdf(file_content: bytes, max_size_mb: int = 10) -> Tuple[bool, str]:
    """PDF 파일을 검증합니다 (헤더 + 크기만 빠르게 확인, pdfplumber 미사용)."""
    size_mb = len(file_content) / (1024 * 1024)
    if size_mb > max_size_mb:
        return False, f"파일 크기가 {max_size_mb}MB를 초과합니다 ({size_mb:.1f}MB)."

    if not file_content.startswith(b"%PDF"):
        return False, "PDF 파일이 아닙니다."

    return True, ""
