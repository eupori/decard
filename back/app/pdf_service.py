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
    """PDF 파일을 검증합니다 (헤더 + 크기만 빠르게 확인, pdfplumber 미사용)."""
    size_mb = len(file_content) / (1024 * 1024)
    if size_mb > max_size_mb:
        return False, f"파일 크기가 {max_size_mb}MB를 초과합니다 ({size_mb:.1f}MB)."

    if not file_content.startswith(b"%PDF"):
        return False, "PDF 파일이 아닙니다."

    return True, ""
