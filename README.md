# Sudoku Vision

Sudoku Vision 將相機或圖片中的數獨題目轉成可驗證的 `9x9` grid，標記低信心格，交給 solver 產生答案。第一版以 OpenCV 做棋盤校正與切格，以 TinyCNN/TFLite 做單格 `empty, 1-9` 分類。

目前重點：Python vision/model pipeline、Windows/Linux 相機 discovery、Docker/GHCR image、Flutter Cupertino-style live recognition UI。

## Quick Start

```bash
python3 -m pip install -e ".[dev]"
pytest
python3 -m sudoku_vision.cli health
python3 -m sudoku_vision.cli cameras
```

Or via the Makefile (`make help` for the catalogue):

```bash
make install-dev    # editable install with dev+vision+train+api extras
make test           # pytest
make api            # uvicorn sudoku_vision.api:app on :8080
make compose-up     # docker compose stack (FastAPI + camera knobs)
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
| Solve a grid (stdin) | `echo '[[5,3,0,...]]' \| python3 -m sudoku_vision.cli solve --grid -` |
| Recognise image | `python3 -m sudoku_vision.cli recognize --image path/to/sudoku.jpg --model artifacts/mnist/digit_classifier_int8.tflite` |
| Recognise with manual corners | `python3 -m sudoku_vision.cli recognize --image x.jpg --model m.tflite --corners corners.json` |
| Grab single RTSP/MJPEG frame | `python3 -m sudoku_vision.cli stream rtsp://host/stream --save-frame frame.png` |
| Run tests | `pytest` |
| Train MNIST starter model | `python3 scripts/train_mnist.py --epochs 5 --output-dir artifacts/mnist` |
| Train with printed-font aug | `python3 scripts/train_mnist.py --epochs 10 --printed-per-digit 400 --output-dir artifacts/mnist` |
| Export int8 TFLite | `python3 scripts/export_tflite.py --model artifacts/mnist/model.keras --output artifacts/mnist/digit_classifier_int8.tflite` |
| Evaluate model metrics | `python3 scripts/evaluate_tiny_cnn.py --keras-model artifacts/mnist/model.keras --tflite-model artifacts/mnist/digit_classifier_int8.tflite --output artifacts/mnist/tiny_cnn_metrics.json` |
| Start HTTP API | `SUDOKU_MODEL_PATH=artifacts/mnist/digit_classifier_int8.tflite uvicorn sudoku_vision.api:app --host 0.0.0.0 --port 8080` |

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

## HTTP API

`sudoku_vision/api.py` exposes the recognise/solve pipeline as a FastAPI service. Install the `api` extra (`pip install -e ".[api]"`) and run:

```bash
SUDOKU_MODEL_PATH=artifacts/mnist/digit_classifier_int8.tflite \
  uvicorn sudoku_vision.api:app --host 0.0.0.0 --port 8080
```

Endpoints:

- `GET /health` — `{"status": "ok", "service": "sudoku-vision", "model_loaded": true}`.
- `POST /solve` — JSON body `{"grid": [[...9x9...]]}`, returns `{validation, solve}` matching `sudoku_vision.solver.SolveResult`.
- `POST /recognize` — multipart with `image` (file), optional `corners` (JSON string, 4×2), optional `board_size` (int). Returns the recognise payload plus `validation`, `solve`, and a top-level `status` in `{solved, needs_review, invalid_puzzle, no_solution, multiple_solutions}`.
- `POST /recognize/capture` — backend grabs one camera/stream frame and returns the same recognise/solve payload. App-sent `corners` or `fallback_corners` may be normalized `0..1`; the API scales them to frame pixels. `fallback_corners` is used when automatic board detection cannot find the Sudoku square.

CORS is pre-allowed for `localhost`/`127.0.0.1` and `app://sudoku-vision`. Override via `SUDOKU_API_ALLOW_ORIGINS=comma,separated`.

## Docker / GHCR

Runtime image now boots the FastAPI service by default (`uvicorn sudoku_vision.api:app` on `:8080`). The CLI is still installed for ad-hoc commands.

```bash
docker build --target runtime -t sudoku-vision:runtime .
docker run --rm -p 8080:8080 \
  -v "$PWD/artifacts:/app/artifacts:ro" \
  -e SUDOKU_MODEL_PATH=/app/artifacts/mnist/digit_classifier_int8.tflite \
  sudoku-vision:runtime
```

Or use `docker compose` — it wires the model volume, port, env knobs, and ships a commented Linux `/dev/video0` pass-through:

```bash
SUDOKU_STREAM_URL=rtsp://host/sudoku docker compose up --build
curl http://localhost:8080/health
```

Configurable per host:

- Linux USB camera → uncomment the `devices:` block in `docker-compose.yaml`.
- macOS / Windows → host-side RTSP/MJPEG/HTTP stream → `SUDOKU_STREAM_URL`.
- Model file → drop `.tflite` into `./artifacts/mnist/` (mounted read-only).

GitHub Actions runs unit tests, the Docker `test` stage, builds the runtime image, validates it, and publishes to GHCR.

## Model

第一版採 LeNet-like TinyCNN，不使用 LaneNet 做數字辨識。Lane/edge 類問題保留在棋盤偵測與 OpenCV 校正流程。

- Cell input: grayscale `32x32`。
- Classes: `empty, 1, 2, 3, 4, 5, 6, 7, 8, 9`。
- Deployment: TFLite，優先 int8 quantization。
- MNIST 只用來驗證 pipeline，不作為最終印刷數獨品質依據。

模型訓練結果、準確度、模型大小、推理速度請看 TinyCNN Model Result Spec: [docs/TINY_CNN_MODEL_RESULT_SPEC.md](docs/TINY_CNN_MODEL_RESULT_SPEC.md)。

## Flutter

Flutter app 放在 `app/`，介面風格以 Apple/Cupertino 為主。Camera tab 會在同一個不捲動的手機視窗中顯示相機 stream、辨識外框、辨識結果與 solver 答案；Review/Solution tabs 保留給低信心格修正與完整檢視。

設計規格請看 Flutter Apple Design: [docs/FLUTTER_APPLE_DESIGN.md](docs/FLUTTER_APPLE_DESIGN.md)。

## Docs

- [SPEC.md](SPEC.md): overall vision/model/solver specification。
- [docs/TDD_WORKFLOW.md](docs/TDD_WORKFLOW.md): TDD workflow。
- [docs/TINY_CNN_MODEL_RESULT_SPEC.md](docs/TINY_CNN_MODEL_RESULT_SPEC.md): TinyCNN Model Result Spec。
- [docs/FLUTTER_APPLE_DESIGN.md](docs/FLUTTER_APPLE_DESIGN.md): Flutter Apple Design。

## Status

- CI currently validates Python tests and Docker image flow.
- Real printed Sudoku cell dataset is still required for production-quality metrics.
- TinyCNN 已通過第 5 節驗收（2026-05-27, macOS arm64, 含合成印刷字）：Keras accuracy `0.9801` / size `0.5654 MiB` / p50 `2.62 ms/cell`；TFLite int8 accuracy `0.9800` / size `0.0517 MiB` / p50 `0.034 ms/cell`。詳見 [docs/TINY_CNN_MODEL_RESULT_SPEC.md](docs/TINY_CNN_MODEL_RESULT_SPEC.md)。
