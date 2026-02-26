"""SM-2 간격 반복 알고리즘 서비스."""

from datetime import datetime, timedelta


def calculate_sm2(
    rating: int,
    previous_interval: float = 0,
    previous_ease: float = 2.5,
) -> tuple[float, float, datetime]:
    """SM-2 알고리즘으로 다음 복습 간격을 계산합니다.

    Args:
        rating: 1=Again, 2=Hard, 3=Good, 4=Easy
        previous_interval: 이전 간격 (일 단위)
        previous_ease: 이전 ease factor (기본 2.5)

    Returns:
        (new_interval_days, new_ease_factor, due_date)
    """
    if rating < 1 or rating > 4:
        raise ValueError(f"rating must be 1~4, got {rating}")

    if rating == 1:  # Again — 10분 후 다시
        new_interval = 0.007  # ~10분 (0.007일)
        new_ease = max(1.3, previous_ease - 0.2)
    elif rating == 2:  # Hard
        if previous_interval < 1:
            new_interval = 1
        else:
            new_interval = previous_interval * 1.2
        new_ease = max(1.3, previous_ease - 0.15)
    elif rating == 3:  # Good
        if previous_interval < 1:
            new_interval = 1
        else:
            new_interval = previous_interval * previous_ease
        new_ease = previous_ease
    else:  # Easy
        if previous_interval < 1:
            new_interval = 4
        else:
            new_interval = previous_interval * previous_ease * 1.3
        new_ease = previous_ease + 0.15

    due_date = datetime.utcnow() + timedelta(days=new_interval)

    return round(new_interval, 2), round(new_ease, 2), due_date
