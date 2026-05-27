# syntax=docker/dockerfile:1

FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY pyproject.toml README.md ./
COPY sudoku_vision ./sudoku_vision
COPY scripts ./scripts

# opencv-python-headless needs a small set of native libs even in headless mode.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libglib2.0-0 \
        libgl1 \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip install --upgrade pip \
    && python -m pip install .

FROM base AS test

RUN apt-get update \
    && apt-get install -y --no-install-recommends make \
    && rm -rf /var/lib/apt/lists/*
COPY Dockerfile .dockerignore ./
COPY Makefile docker-compose.yaml ./
COPY .github ./.github
COPY SPEC.md ./
COPY docs ./docs
COPY requirements*.txt ./
COPY tests ./tests
RUN python -m pip install ".[dev]" \
    && pytest

FROM base AS runtime

ARG VCS_REF=""
ARG BUILD_DATE=""
ARG SOURCE_URL="https://github.com/sudoku-vision/sudoku-vision"

LABEL org.opencontainers.image.title="sudoku-vision" \
      org.opencontainers.image.description="Sudoku vision recognition prototype" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

# Install API + vision so /recognize works out of the box. .[api,vision]
# pulls in fastapi/uvicorn/python-multipart and opencv-python-headless.
# ai-edge-litert is the modern TFLite-only runtime (replacement for
# tflite-runtime); broader wheel coverage including linux/arm64.
RUN python -m pip install ".[api,vision]" ai-edge-litert

# SUDOKU_MODEL_PATH points the API at a mounted TFLite model.
# SUDOKU_STREAM_URL lets the CLI/API grab frames from RTSP/MJPEG sources.
ENV SUDOKU_MODEL_PATH="" \
    SUDOKU_STREAM_URL="" \
    SUDOKU_API_HOST="0.0.0.0" \
    SUDOKU_API_PORT="8080"

EXPOSE 8080

# Local sanity check (no daemon needed): python -m sudoku_vision.cli health.
# The container HEALTHCHECK uses the live /health endpoint instead.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import os,sys,urllib.request; \
sys.exit(0 if urllib.request.urlopen(f\"http://localhost:{os.environ.get('SUDOKU_API_PORT','8080')}/health\", timeout=3).status==200 else 1)"

CMD ["sh", "-c", "exec uvicorn sudoku_vision.api:app --host \"${SUDOKU_API_HOST}\" --port \"${SUDOKU_API_PORT}\""]
