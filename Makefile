# Sudoku Vision dev workflows. Run `make help` for the catalogue.

SHELL := /bin/bash

PYTHON     ?= python3
PIP        ?= $(PYTHON) -m pip
APP_DIR    ?= app
ARTIFACTS  ?= artifacts/mnist
MODEL      ?= $(ARTIFACTS)/digit_classifier_int8.tflite
KERAS_MODEL?= $(ARTIFACTS)/model.keras
IMAGE      ?= sudoku-vision:local
COMPOSE    ?= docker compose
HOST       ?= 0.0.0.0
PORT       ?= 8080

# Host-side camera streaming knobs (used by stream-host / stream-rtsp).
CAM        ?= 0
CAM_W      ?= 1920
CAM_H      ?= 1080
CAM_FPS    ?= 15
STREAM_PORT?= 8554
RTSP_PATH  ?= cam
# AVFoundation on macOS uses the integer index. v4l2 on Linux uses /dev/videoN.
ifeq ($(shell uname),Darwin)
FFMPEG_INPUT_FORMAT ?= avfoundation
FFMPEG_INPUT        ?= $(CAM)
else
FFMPEG_INPUT_FORMAT ?= v4l2
FFMPEG_INPUT        ?= /dev/video$(CAM)
endif

.PHONY: help install install-vision install-train install-api install-dev \
        test lint train export evaluate recognize api \
        docker-build docker-test compose-up compose-down compose-logs \
        compose-rtsp-up compose-rtsp-down \
        stream-host stream-rtsp \
        flutter-pub flutter-test flutter-analyze screenshots \
        clean

help: ## Show this help.
	@awk 'BEGIN {FS = ":.*## "; printf "Targets:\n"} \
	  /^[a-zA-Z0-9_.\-]+:.*## / { \
	    printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 \
	  }' $(MAKEFILE_LIST)

# ---------- Install ----------------------------------------------------------

install: ## Install runtime + dev deps (editable).
	$(PIP) install -e ".[dev]"

install-vision: ## Add OpenCV (camera + image decoding) to the active env.
	$(PIP) install -e ".[vision]"

install-train: ## Add TensorFlow for training/export.
	$(PIP) install -e ".[train]"

install-api: ## Add FastAPI/uvicorn for the HTTP service.
	$(PIP) install -e ".[api]"

install-dev: ## Install everything (dev + vision + train + api).
	$(PIP) install -e ".[dev,vision,train,api]"

# ---------- Tests / lint ------------------------------------------------------

test: ## Run the Python test suite.
	$(PYTHON) -m pytest

lint: ## Static checks: flutter analyze + python -m compileall.
	cd $(APP_DIR) && flutter analyze
	$(PYTHON) -m compileall -q sudoku_vision scripts tests

# ---------- Model lifecycle ---------------------------------------------------

train: ## Train the TinyCNN with printed-font augmentation.
	$(PYTHON) scripts/train_mnist.py --epochs 10 --printed-per-digit 400 \
	  --output-dir $(ARTIFACTS)

export: ## Export the trained Keras model to int8 TFLite.
	$(PYTHON) scripts/export_tflite.py --model $(KERAS_MODEL) --output $(MODEL)

evaluate: ## Evaluate Keras + TFLite metrics on the combined test set.
	$(PYTHON) scripts/evaluate_tiny_cnn.py \
	  --keras-model $(KERAS_MODEL) \
	  --tflite-model $(MODEL) \
	  --printed-per-digit 200 \
	  --output $(ARTIFACTS)/tiny_cnn_metrics.json

recognize: ## Recognise IMG=path/to/sudoku.jpg with the local model.
	@[ -n "$(IMG)" ] || (echo "set IMG=path/to/sudoku.jpg" && exit 2)
	$(PYTHON) -m sudoku_vision.cli recognize --image "$(IMG)" --model "$(MODEL)"

# ---------- API ---------------------------------------------------------------

api: ## Run the FastAPI service on $(HOST):$(PORT). Uses SUDOKU_MODEL_PATH=$(MODEL).
	SUDOKU_MODEL_PATH=$(MODEL) \
	  $(PYTHON) -m uvicorn sudoku_vision.api:app --host $(HOST) --port $(PORT)

# ---------- Docker / Compose --------------------------------------------------

docker-build: ## Build the runtime image.
	docker build --target runtime -t $(IMAGE) .

docker-test: ## Build the test stage (runs pytest inside the image).
	docker build --target test -t sudoku-vision:test .

compose-up: ## Bring up the docker-compose stack (FastAPI on $(PORT)).
	$(COMPOSE) up --build -d
	@echo "API: http://localhost:$(PORT)/health"

compose-down: ## Tear down the docker-compose stack.
	$(COMPOSE) down

compose-logs: ## Follow docker-compose logs.
	$(COMPOSE) logs -f

compose-rtsp-up: ## Start the stack with the MediaMTX RTSP relay (profile=rtsp).
	$(COMPOSE) --profile rtsp up --build -d
	@echo "RTSP server: rtsp://localhost:$(STREAM_PORT)/$(RTSP_PATH)"
	@echo "Push from host:   make stream-rtsp CAM=$(CAM)"
	@echo "Container reads:  rtsp://mediamtx:$(STREAM_PORT)/$(RTSP_PATH)"

compose-rtsp-down: ## Tear down the RTSP-profile stack.
	$(COMPOSE) --profile rtsp down

# ---------- Host-side camera streaming ---------------------------------------
# These targets run ffmpeg on the host to make a local USB / built-in camera
# reachable by the Linux container (Docker Desktop on macOS/Windows can't share
# USB cameras directly). Adjust CAM=N (and CAM_W/CAM_H/CAM_FPS) per host.

stream-host: ## Push CAM=N as TCP MPEG-TS for the container. Reads tcp://host.docker.internal:$(STREAM_PORT).
	@command -v ffmpeg >/dev/null || (echo "ffmpeg not found. Install with: brew install ffmpeg" && exit 1)
	@echo "Streaming $(FFMPEG_INPUT) at $(CAM_W)x$(CAM_H)@$(CAM_FPS) to tcp://0.0.0.0:$(STREAM_PORT)?listen"
	@echo "Container env: SUDOKU_STREAM_URL=tcp://host.docker.internal:$(STREAM_PORT)"
	ffmpeg -f $(FFMPEG_INPUT_FORMAT) -framerate $(CAM_FPS) \
	  -video_size $(CAM_W)x$(CAM_H) -i "$(FFMPEG_INPUT)" \
	  -c:v mpeg1video -b:v 3M -bf 0 -f mpegts \
	  "tcp://0.0.0.0:$(STREAM_PORT)?listen"

stream-rtsp: ## Push CAM=N to the MediaMTX RTSP relay at rtsp://localhost:$(STREAM_PORT)/$(RTSP_PATH).
	@command -v ffmpeg >/dev/null || (echo "ffmpeg not found. Install with: brew install ffmpeg" && exit 1)
	@echo "Streaming $(FFMPEG_INPUT) -> rtsp://localhost:$(STREAM_PORT)/$(RTSP_PATH)"
	@echo "Container env: SUDOKU_STREAM_URL=rtsp://mediamtx:$(STREAM_PORT)/$(RTSP_PATH)"
	ffmpeg -f $(FFMPEG_INPUT_FORMAT) -framerate $(CAM_FPS) \
	  -video_size $(CAM_W)x$(CAM_H) -i "$(FFMPEG_INPUT)" \
	  -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
	  -g $(CAM_FPS) -f rtsp -rtsp_transport tcp \
	  "rtsp://localhost:$(STREAM_PORT)/$(RTSP_PATH)"

# ---------- Flutter -----------------------------------------------------------

flutter-pub: ## Resolve Flutter packages.
	cd $(APP_DIR) && flutter pub get

flutter-test: ## Run the Flutter widget/unit tests.
	cd $(APP_DIR) && flutter test

flutter-analyze: ## Run flutter analyze (Dart static checks).
	cd $(APP_DIR) && flutter analyze

screenshots: ## Regenerate docs/screenshots/*.png from the Cupertino UI.
	cd $(APP_DIR) && flutter test test/screenshot_capture.dart

# ---------- Housekeeping ------------------------------------------------------

clean: ## Remove caches and Flutter build artefacts.
	rm -rf .pytest_cache .mypy_cache .ruff_cache \
	  sudoku_vision/__pycache__ scripts/__pycache__ tests/__pycache__
	cd $(APP_DIR) && flutter clean >/dev/null 2>&1 || true
