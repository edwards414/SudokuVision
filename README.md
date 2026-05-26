# Sudoku Vision

Sudoku Vision 是一個數獨視覺辨識與解題原型。目標是從相機或圖片中取得數獨題目，辨識 9x9 表格中的已知數字，經過人工確認與規則驗證後，自動求解並回傳答案。

目前專案聚焦在後端 vision/model pipeline、solver、Docker/GHCR 發布，以及 Windows/Linux 相機 discovery。Flutter 介面會在後續接 API 或 CLI 輸出的 JSON。

## Features

- OpenCV 棋盤偵測與透視校正。
- 9x9 cell 切割與 cell 前處理。
- CV 空格候選判斷。
- LeNet-like Tiny CNN 數字分類規格，輸出 `empty, 1-9`。
- TFLite int8 匯出流程。
- 低信心 cell 標記，預設 threshold 為 `0.85`。
- Sudoku grid validation。
- 唯一解 solver。
- Windows/Linux camera discovery。
- Docker multi-stage build。
- GHCR CI/CD workflow。
- TDD 開發流程。

## Architecture

```text
USB Camera / Image
-> Camera discovery or image input
-> Board detection
-> Perspective correction
-> 81 cell extraction
-> Empty-cell CV heuristic
-> Tiny CNN / TFLite classifier
-> 9x9 grid + confidence
-> Human review for low-confidence cells
-> Sudoku validation
-> Solver
-> JSON result for Flutter/API
```

重要約定：

- `0` 永遠代表空格。
- `1-9` 代表題目中的已知數字。
- 模型輸出不可直接視為可靠答案，必須經過 validation 或人工確認。
- `confidence < 0.85` 的 cell 需標記為 `low_confidence_cells`。

## Project Layout

```text
sudoku_vision/
  board.py          OpenCV 棋盤偵測與透視校正
  camera.py         Windows/Linux 相機 discovery
  cli.py            health/cameras CLI
  model.py          Tiny CNN model definition
  preprocessing.py  cell 前處理、空格判斷、切格
  recognizer.py     TFLite/classifier wrapper
  solver.py         Sudoku validation and solver

scripts/
  train_mnist.py       MNIST 起步訓練
  export_tflite.py     int8 TFLite 匯出
  recognize_image.py   圖片到辨識結果的端到端腳本

tests/
  test_camera.py
  test_ci_config.py
  test_cli.py
  test_preprocessing.py
  test_recognizer.py
  test_solver.py
```

## Requirements

- Python `>= 3.10`
- Docker, if building container images
- TensorFlow, only when training/exporting model
- OpenCV, only when probing cameras or running vision pipeline

Core tests do not require TensorFlow or OpenCV.

## Install

Base development install:

```bash
python3 -m pip install -e ".[dev]"
```

Install from requirements files:

```bash
python3 -m pip install -r requirements.txt
python3 -m pip install -r requirements-dev.txt
python3 -m pip install -r requirements-vision.txt
python3 -m pip install -r requirements-train.txt
python3 -m pip install -r requirements-all.txt
```

Recommended mapping:

- `requirements.txt`: runtime core dependencies.
- `requirements-dev.txt`: core + tests.
- `requirements-vision.txt`: core + OpenCV camera/vision dependencies.
- `requirements-train.txt`: core + TensorFlow model training/export.
- `requirements-all.txt`: dev + vision + train dependencies.

Vision dependencies:

```bash
python3 -m pip install -e ".[vision]"
```

Training dependencies:

```bash
python3 -m pip install -e ".[train]"
```

All common development extras:

```bash
python3 -m pip install -e ".[dev,vision,train]"
```

On Windows, `vision` installs `opencv-python`. On Linux and Docker-style environments, `vision` installs `opencv-python-headless`.

## CLI

Health check:

```bash
python3 -m sudoku_vision.cli health
```

Example output:

```json
{"status":"ok","service":"sudoku-vision","version":"0.1.0"}
```

List cameras:

```bash
python3 -m sudoku_vision.cli cameras
```

Example output:

```json
{
  "platform": "Linux",
  "devices": [
    {
      "id": "linux:/dev/video0",
      "name": "USB Camera",
      "platform": "Linux",
      "backend": "v4l2",
      "index": 0,
      "path": "/dev/video0",
      "width": null,
      "height": null
    }
  ],
  "warnings": []
}
```

## Camera Setup

### Linux

Linux discovery reads:

- `/dev/video*`
- `/sys/class/video4linux/<device>/name`

Run locally:

```bash
python3 -m sudoku_vision.cli cameras
```

Run inside Docker with a USB camera:

```bash
docker run --rm \
  --device=/dev/video0:/dev/video0 \
  ghcr.io/<owner>/<repo>:latest \
  python -m sudoku_vision.cli cameras
```

### Windows

Windows discovery probes OpenCV camera indices with DirectShow:

```powershell
python -m pip install -e ".[vision]"
python -m sudoku_vision.cli cameras --probe-opencv
```

Windows Docker Desktop usually cannot reliably pass a USB camera directly into Linux containers. Recommended architecture:

```text
Windows host camera
-> host-side RTSP/MJPEG/TCP stream
-> Docker vision container reads network stream
-> Flutter reads API/result JSON
```

## Train Starter Model

MNIST is only used to validate the training and TFLite pipeline. It is not the final quality benchmark for printed Sudoku photos.

TinyCNN Model Result Spec:

- [docs/TINY_CNN_MODEL_RESULT_SPEC.md](docs/TINY_CNN_MODEL_RESULT_SPEC.md)
- Tracks Accuracy, Model Size, and Inference Speed.
- Current official result status is `未量測` until model artifacts are generated.

Train:

```bash
python3 scripts/train_mnist.py --epochs 5 --output-dir artifacts/mnist
```

Export int8 TFLite:

```bash
python3 scripts/export_tflite.py \
  --model artifacts/mnist/model.keras \
  --output artifacts/mnist/digit_classifier_int8.tflite
```

Evaluate metrics:

```bash
python3 scripts/evaluate_tiny_cnn.py \
  --keras-model artifacts/mnist/model.keras \
  --tflite-model artifacts/mnist/digit_classifier_int8.tflite \
  --output artifacts/mnist/tiny_cnn_metrics.json
```

## Recognize Image

```bash
python3 scripts/recognize_image.py \
  --image path/to/sudoku.jpg \
  --model artifacts/mnist/digit_classifier_int8.tflite \
  --output result.json
```

Output shape:

```json
{
  "grid": [[0, 0, 0, 0, 0, 0, 0, 0, 0]],
  "confidence": [[1.0, 0.92, 0.88, 1.0, 1.0, 0.74, 1.0, 1.0, 1.0]],
  "low_confidence_cells": [
    { "row": 0, "col": 5, "predicted": 7, "confidence": 0.74 }
  ]
}
```

## Test

Run all tests:

```bash
pytest
```

Current test layers:

- Camera discovery contract.
- CI/Docker/GHCR configuration contract.
- CLI health and cameras JSON.
- Cell preprocessing.
- Digit recognizer confidence behavior.
- Sudoku validation and solver.

## Docker

Build and run runtime image:

```bash
docker build --target runtime -t sudoku-vision:ci .
docker run --rm sudoku-vision:ci
```

Build test target. This runs `pytest` inside the image:

```bash
docker build --target test -t sudoku-vision:test .
```

Runtime health command:

```bash
docker run --rm sudoku-vision:ci python -m sudoku_vision.cli health
```

## GHCR CI/CD

GitHub Actions workflow:

```text
.github/workflows/container.yml
```

The workflow runs on:

- push to `main`
- version tags matching `v*.*.*`
- pull requests
- manual dispatch

Workflow behavior:

1. Install project and run `pytest`.
2. Build Docker `test` target, which runs `pytest` inside the image.
3. Build runtime image.
4. Validate runtime image with `python -m sudoku_vision.cli health`.
5. Push image to GHCR for non-PR events.
6. Pull the pushed `sha-<commit>` image from GHCR.
7. Run health check again from the pulled image.

Image tags:

- `latest` for default branch.
- `sha-<commit-sha>` for each publishable commit.
- `v*.*.*` for version tags.

Pull image:

```bash
docker pull ghcr.io/<owner>/<repo>:latest
docker run --rm ghcr.io/<owner>/<repo>:latest
```

Pull exact commit image:

```bash
docker pull ghcr.io/<owner>/<repo>:sha-<commit-sha>
docker run --rm ghcr.io/<owner>/<repo>:sha-<commit-sha>
```

## TDD Workflow

This project follows Red-Green-Refactor:

```text
Red -> Green -> Refactor
```

Rules:

- Write a failing test first.
- Implement the minimum behavior needed to pass.
- Refactor only after tests pass.
- Any API/schema behavior change must update tests and docs.

See [docs/TDD_WORKFLOW.md](docs/TDD_WORKFLOW.md).

## Flutter Apple Design

Flutter UI must follow Apple-style interaction and visual patterns. Use Cupertino widgets as the default UI layer:

- `CupertinoApp`
- `CupertinoPageScaffold`
- `CupertinoNavigationBar`
- `CupertinoButton`
- `CupertinoColors`
- `CupertinoIcons`

Design details and acceptance criteria are in [docs/FLUTTER_APPLE_DESIGN.md](docs/FLUTTER_APPLE_DESIGN.md).

## Current Limitations

- MNIST is only a starter dataset; printed Sudoku accuracy needs synthetic fonts and real cell images.
- Real-time camera stream processing API is not implemented yet.
- Flutter UI is not implemented yet.
- Windows Docker camera pass-through is not assumed; use host-side streaming instead.
- Full model training and TFLite export require TensorFlow.

## Next Milestones

1. Add Docker/API service for camera stream input.
2. Define REST/WebSocket schema for Flutter.
3. Add RTSP/MJPEG frame reader.
4. Add printed Sudoku cell fixture dataset.
5. Train and validate the first real printed-digit model.
6. Build Flutter review UI for low-confidence cells.
