FROM python:3.11-slim

WORKDIR /app

# System deps + Node.js for Claude Code CLI
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc curl \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Python deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt gunicorn

# App code
COPY app ./app

# Non-root user
RUN useradd -r -s /bin/false appuser && chown -R appuser:appuser /app
USER appuser

ENV PYTHONPATH="/app"

EXPOSE 8001

CMD ["gunicorn", "app.main:app", "-k", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8001", "--workers", "2", "--timeout", "300"]
