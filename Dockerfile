# syntax=docker/dockerfile:1

FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY pyproject.toml README.md ./
COPY sudoku_vision ./sudoku_vision
COPY scripts ./scripts

RUN python -m pip install --upgrade pip \
    && python -m pip install .

FROM base AS test

COPY Dockerfile .dockerignore ./
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

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD python -m sudoku_vision.cli health

CMD ["python", "-m", "sudoku_vision.cli", "health"]
