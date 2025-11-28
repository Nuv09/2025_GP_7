FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 libgomp1 curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080 \
    PYTHONPATH=/app

WORKDIR /app

RUN python -m pip install --no-cache-dir --extra-index-url https://download.pytorch.org/whl/cpu \
    torch==2.3.1+cpu torchvision==0.18.1+cpu

COPY requirements.txt .
RUN python -m pip install --no-cache-dir -r requirements.txt

COPY app ./app
RUN mkdir -p /tmp

RUN useradd -m appuser
USER appuser

EXPOSE 8080

CMD ["gunicorn", "app.main:app", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "2", "--timeout", "120", "--max-requests", "10", "--max-requests-jitter", "5"]
