# Sudoku Vision

Sudoku Vision 將相機或圖片中的數獨題目轉成可驗證的 `9x9` grid，標記低信心格，交給 solver 產生答案。第一版以 OpenCV 做棋盤校正與切格，以 TinyCNN/TFLite 做單格 `empty, 1-9` 分類。

目前重點：Python vision/model pipeline、Windows/Linux 相機 discovery、Docker/GHCR image、Flutter Cupertino-style review UI。

## Quick Start

```bash
python3 -m pip install -e ".[dev]"
pytest
python3 -m sudoku_vision.cli health
python3 -m sudoku_vision.cli cameras
```

## Pipeline

```text
Camera / Image
-> board detection + perspective correction
-> 81 cell extraction
-> CV empty-cell heuristic
-> TinyCNN / TFLite classifier
-> grid + confidence + low_confidence_cells
-> human review
-> Sudoku validation
-> solver
```

核心約定：

- `0` 永遠代表空格。
- `1-9` 代表題目中的已知數字。
- `confidence < 0.85` 會進入 `low_confidence_cells`。
- solver 只接受通過合法性驗證的 grid。

## Project Layout

```text
sudoku_vision/   Python package: camera, preprocessing, recognizer, solver
scripts/         train, export, evaluate, recognize image
tests/           TDD contract and unit tests
docs/            specs and implementation notes
app/             Flutter Cupertino-style interface
```

## Install Profiles

```bash
python3 -m pip install -r requirements.txt
python3 -m pip install -r requirements-dev.txt
python3 -m pip install -r requirements-vision.txt
python3 -m pip install -r requirements-train.txt
python3 -m pip install -r requirements-all.txt
```

- `requirements.txt`: runtime core。
- `requirements-dev.txt`: tests。
- `requirements-vision.txt`: OpenCV camera/vision。
- `requirements-train.txt`: TensorFlow training/export。
- `requirements-all.txt`: dev + vision + train。

Editable extras:

```bash
python3 -m pip install -e ".[dev,vision,train]"
```

## Common Commands

| Task | Command |
| --- | --- |
| Health check | `python3 -m sudoku_vision.cli health` |
| List cameras | `python3 -m sudoku_vision.cli cameras` |
| Windows OpenCV camera probe | `python -m sudoku_vision.cli cameras --probe-opencv` |
| Run tests | `pytest` |
| Train MNIST starter model | `python3 scripts/train_mnist.py --epochs 5 --output-dir artifacts/mnist` |
| Export int8 TFLite | `python3 scripts/export_tflite.py --model artifacts/mnist/model.keras --output artifacts/mnist/digit_classifier_int8.tflite` |
| Evaluate model metrics | `python3 scripts/evaluate_tiny_cnn.py --keras-model artifacts/mnist/model.keras --tflite-model artifacts/mnist/digit_classifier_int8.tflite --output artifacts/mnist/tiny_cnn_metrics.json` |
| Recognize image | `python3 scripts/recognize_image.py --image path/to/sudoku.jpg --model artifacts/mnist/digit_classifier_int8.tflite --output result.json` |

## Camera

Linux discovery reads `/dev/video*` and `/sys/class/video4linux/<device>/name`.

```bash
python3 -m sudoku_vision.cli cameras
```

Linux Docker USB camera:

```bash
docker run --rm --device=/dev/video0:/dev/video0 ghcr.io/edwards414/sudokuvision:latest python -m sudoku_vision.cli cameras
```

Windows discovery can probe DirectShow through OpenCV:

```powershell
python -m pip install -e ".[vision]"
python -m sudoku_vision.cli cameras --probe-opencv
```

Windows Docker Desktop 通常不適合直接把 USB camera pass-through 到 Linux container。建議架構是：

```text
Windows host camera
-> host-side RTSP/MJPEG/TCP stream
-> Docker vision container reads the stream
-> Flutter receives API/result JSON
```

## Docker / GHCR

```bash
docker build --target test -t sudoku-vision:test .
docker build --target runtime -t sudoku-vision:runtime .
docker run --rm sudoku-vision:runtime python -m sudoku_vision.cli health
docker pull ghcr.io/edwards414/sudokuvision:latest
```

GitHub Actions 會跑 unit tests、Docker test target、runtime image build、GHCR publish，並 pull 回 image 做驗證。

## Model

第一版採 LeNet-like TinyCNN，不使用 LaneNet 做數字辨識。Lane/edge 類問題保留在棋盤偵測與 OpenCV 校正流程。

- Cell input: grayscale `32x32`。
- Classes: `empty, 1, 2, 3, 4, 5, 6, 7, 8, 9`。
- Deployment: TFLite，優先 int8 quantization。
- MNIST 只用來驗證 pipeline，不作為最終印刷數獨品質依據。

模型訓練結果、準確度、模型大小、推理速度請看 TinyCNN Model Result Spec: [docs/TINY_CNN_MODEL_RESULT_SPEC.md](docs/TINY_CNN_MODEL_RESULT_SPEC.md)。

## Flutter

Flutter app 放在 `app/`，介面風格以 Apple/Cupertino 為主，重點是即時預覽、低信心格確認、解題結果回傳。

設計規格請看 Flutter Apple Design: [docs/FLUTTER_APPLE_DESIGN.md](docs/FLUTTER_APPLE_DESIGN.md)。

## Docs

- [SPEC.md](SPEC.md): overall vision/model/solver specification。
- [docs/TDD_WORKFLOW.md](docs/TDD_WORKFLOW.md): TDD workflow。
- [docs/TINY_CNN_MODEL_RESULT_SPEC.md](docs/TINY_CNN_MODEL_RESULT_SPEC.md): TinyCNN Model Result Spec。
- [docs/FLUTTER_APPLE_DESIGN.md](docs/FLUTTER_APPLE_DESIGN.md): Flutter Apple Design。

## Status

- CI currently validates Python tests and Docker image flow.
- Real printed Sudoku cell dataset is still required for production-quality metrics.
- Current official TinyCNN metric status remains `未量測` until generated artifacts are evaluated.
