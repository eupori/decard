from fastapi import Request


def get_device_id(request: Request) -> str:
    """Extract device ID from X-Device-ID header, default to 'anonymous'."""
    return request.headers.get("X-Device-ID", "anonymous")
