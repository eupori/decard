import io
from typing import List, Dict, Tuple

import pdfplumber


def extract_text_from_pdf(file_content: bytes) -> List[Dict]:
    """PDF에서 페이지별 텍스트를 추출합니다."""
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


def validate_pdf(file_content: bytes, max_size_mb: int = 10) -> Tuple[bool, str]:
    """PDF 파일을 검증합니다 (파싱 가능 여부만 빠르게 확인)."""
    size_mb = len(file_content) / (1024 * 1024)
    if size_mb > max_size_mb:
        return False, f"파일 크기가 {max_size_mb}MB를 초과합니다 ({size_mb:.1f}MB)."

    try:
        with pdfplumber.open(io.BytesIO(file_content)) as pdf:
            if len(pdf.pages) == 0:
                return False, "빈 PDF 파일입니다."
            # 첫 페이지만 빠르게 텍스트 확인
            first_text = pdf.pages[0].extract_text()
            if not first_text or not first_text.strip():
                return False, "텍스트를 추출할 수 없는 PDF입니다. 스캔 PDF는 아직 지원하지 않습니다."
            return True, ""
    except Exception as e:
        return False, f"PDF를 읽을 수 없습니다: {e}"
