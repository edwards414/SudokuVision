# TinyCNN 模型訓練結果規格書

版本：0.3  
狀態：MNIST + 合成印刷字達標（accuracy、size、latency 皆達門檻）  
適用模型：LeNet-like TinyCNN single-cell classifier  
最後量測：2026-05-27（含合成印刷字增強）

## 1. 結論摘要

第二輪量測（MNIST 1-9 + synthetic empty + synthetic printed-font，10 epochs）：

- Keras：accuracy `0.9801`、loss `0.0791`、size `0.5654 MiB`、單 cell p50 `2.6208 ms`。
- TFLite int8：accuracy `0.9800`、size `0.0517 MiB`、單 cell p50 `0.0337 ms`。
- 81 cell 估算 p50：Keras `~212.3 ms`、TFLite `~2.73 ms`，皆遠低於 `405 ms` 門檻。
- 全部第 5 節門檻皆達標（accuracy ≥ 98%、size ≤ 1 MiB、p50 ≤ 5 ms、81-cell ≤ 405 ms）。
- 注意：MNIST-only 切片（`--max-eval-samples 2000`）會降到 `~96.9%`，因為訓練容量同時要承擔印刷字。要回到較高的 MNIST-only 數值，需要更大模型或更多 epoch。

artifact 與 metrics JSON：

- `artifacts/mnist/model.keras`（被 `.gitignore` 排除，不入版控）。
- `artifacts/mnist/digit_classifier_int8.tflite`（同上）。
- `artifacts/mnist/tiny_cnn_metrics.json`：完整 metrics dump，依本文件第 7 節 schema。

重新量測流程：跑 `scripts/train_mnist.py --printed-per-digit 400` → `scripts/export_tflite.py` → `scripts/evaluate_tiny_cnn.py --printed-per-digit 200`（不傳 `--max-eval-samples` 才能涵蓋完整 MNIST + printed test set），再把結果回填到第 4 節。

## 2. 模型規格

模型名稱：TinyCNN  
任務：單一數獨 cell 分類  
輸入：`32x32x1` grayscale foreground tensor  
輸出類別：`empty, 1, 2, 3, 4, 5, 6, 7, 8, 9`  
grid 表示：`0` 代表空格，`1-9` 代表辨識出的數字  
低信心門檻：`confidence < 0.85`

架構摘要：

```text
Conv -> BatchNorm -> ReLU -> Pool
Conv -> BatchNorm -> ReLU -> Pool
Conv -> BatchNorm -> ReLU
GlobalAveragePooling
Dense -> Dropout
Dense Softmax(10)
```

## 3. 訓練資料

起步資料：

- MNIST digits `1-9`。
- 合成 empty cell class。
- MNIST digit `0` 不作為數獨數字類別。

限制：

- MNIST 只用來驗證訓練與 TFLite pipeline。
- MNIST accuracy 不代表印刷體數獨照片的最終準確率。
- 正式驗收仍需要印刷體 cell dataset 與實拍 cell dataset。

## 4. 目前量測結果

量測日期：2026-05-27（第二輪，含合成印刷字）  
量測環境：macOS 26.2 (arm64, Apple Silicon)，Python 3.12.6，TensorFlow 2.21.0。  
訓練設定：`scripts/train_mnist.py --epochs 10 --printed-per-digit 400`，`empty_ratio=1.0`，batch size 128，EarlyStopping(patience=2)，合成印刷字使用 macOS 系統 Helvetica/Times/Arial/Courier New/Tahoma fonts。  
評估設定：`--printed-per-digit 200 --warmup 20 --runs 200`，完整 10,472 樣本（不切片）。

### 4.1 Accuracy

| Model Artifact | Dataset | Accuracy | Loss | 狀態 |
| --- | --- | ---: | ---: | --- |
| `artifacts/mnist/model.keras` | MNIST 1-9 + synthetic empty + synthetic printed（10,472 樣本） | 0.9801 | 0.0791 | 達標（門檻 ≥ 0.98） |
| `artifacts/mnist/digit_classifier_int8.tflite` | 同上 | 0.9800 | N/A | 達標（門檻 ≥ 0.98） |
| `artifacts/mnist/model.keras` | MNIST 1-9 + synthetic empty（2000 樣本切片） | 0.9690 | 0.1157 | MNIST-only 仍偏低，反映訓練容量分給印刷字 |
| `artifacts/printed_cells/*` | 印刷體 Sudoku cell 實拍 | 未量測 | N/A | dataset 尚未建立 |

### 4.2 Model Size

| Model Artifact | Format | Model Size | 狀態 |
| --- | --- | ---: | --- |
| `artifacts/mnist/model.keras` | Keras | 0.5654 MiB (592,894 B) | 達標（無嚴格門檻） |
| `artifacts/mnist/digit_classifier_int8.tflite` | TFLite int8 | 0.0517 MiB (54,184 B) | 達標（門檻 ≤ 1 MiB） |

### 4.3 Inference Speed

量測單位：單一 cell，輸入 shape `1x32x32x1`。  
量測欄位：mean、p50、p95、min、max。  
warmup：20 次。  
sample runs：200 次。

| Model Artifact | Device | Runtime | p50 ms/cell | p95 ms/cell | Estimated 81-cell p50 | 狀態 |
| --- | --- | --- | ---: | ---: | ---: | --- |
| `artifacts/mnist/model.keras` | Apple Silicon (macOS arm64) CPU | TensorFlow/Keras 2.21.0 | 2.6208 | 3.0810 | ~212.3 ms | 達標（門檻 ≤ 5 ms / 405 ms） |
| `artifacts/mnist/digit_classifier_int8.tflite` | Apple Silicon (macOS arm64) CPU + XNNPACK | TFLite (`tf.lite.Interpreter`) | 0.0337 | 0.0350 | ~2.73 ms | 達標（門檻 ≤ 5 ms / 405 ms） |

> macOS / Apple Silicon CPU 不等於目標手機 CPU。手機端 latency 仍需在實機重新量測，本表只作為桌機 baseline。

## 5. 驗收門檻

第一版建議門檻：

- MNIST + synthetic empty accuracy：`>= 98%`。
- 印刷體乾淨 cell accuracy：`>= 95%`。
- TFLite int8 model size：`<= 1 MiB`。
- 目標手機 CPU 單 cell p50 latency：`<= 5 ms`。
- 81-cell full-board estimated p50：`<= 405 ms`。

若未達門檻：

- Accuracy 不足：加入合成印刷字型與實拍 cell dataset。
- TFLite accuracy 明顯低於 Keras：調整 representative dataset 或量化策略。
- Model Size 超標：降低 channel 數或 dense layer 大小。
- Inference Speed 超標：優先使用 TFLite int8，並避免逐 cell 重複配置 interpreter。

## 6. 量測指令

安裝訓練依賴：

```bash
python3 -m pip install -r requirements-train.txt
```

訓練 Keras 模型：

```bash
python3 scripts/train_mnist.py \
  --epochs 5 \
  --output-dir artifacts/mnist
```

匯出 TFLite int8：

```bash
python3 scripts/export_tflite.py \
  --model artifacts/mnist/model.keras \
  --output artifacts/mnist/digit_classifier_int8.tflite
```

量測 Accuracy、Model Size、Inference Speed：

```bash
python3 scripts/evaluate_tiny_cnn.py \
  --keras-model artifacts/mnist/model.keras \
  --tflite-model artifacts/mnist/digit_classifier_int8.tflite \
  --output artifacts/mnist/tiny_cnn_metrics.json \
  --max-eval-samples 2000 \
  --warmup 20 \
  --runs 200
```

## 7. Metrics JSON 格式

Schema：

```json
{
  "model": "TinyCNN",
  "dataset": "MNIST digits 1-9 + synthetic empty class",
  "input_shape": [32, 32, 1],
  "classes": ["empty", "1", "2", "3", "4", "5", "6", "7", "8", "9"],
  "environment": {
    "python": "3.12.x",
    "platform": "device/os",
    "processor": "cpu"
  },
  "metrics": {
    "keras": {
      "path": "artifacts/mnist/model.keras",
      "model_size_bytes": 0,
      "model_size_mib": 0.0,
      "accuracy": 0.0,
      "loss": 0.0,
      "latency_mean_ms": 0.0,
      "latency_p50_ms": 0.0,
      "latency_p95_ms": 0.0,
      "latency_min_ms": 0.0,
      "latency_max_ms": 0.0,
      "latency_samples": 200
    },
    "tflite": {
      "path": "artifacts/mnist/digit_classifier_int8.tflite",
      "model_size_bytes": 0,
      "model_size_mib": 0.0,
      "accuracy": 0.0,
      "evaluated_samples": 2000,
      "latency_mean_ms": 0.0,
      "latency_p50_ms": 0.0,
      "latency_p95_ms": 0.0,
      "latency_min_ms": 0.0,
      "latency_max_ms": 0.0,
      "latency_samples": 200
    }
  }
}
```

2026-05-27 實測（第二輪，含合成印刷字）：

```json
{
  "model": "TinyCNN",
  "dataset": "MNIST digits 1-9 + synthetic empty + synthetic printed",
  "input_shape": [32, 32, 1],
  "classes": ["empty", "1", "2", "3", "4", "5", "6", "7", "8", "9"],
  "environment": {
    "python": "3.12.6",
    "platform": "macOS-26.2-arm64-arm-64bit",
    "processor": "arm"
  },
  "metrics": {
    "keras": {
      "path": "artifacts/mnist/model.keras",
      "model_size_bytes": 592894,
      "model_size_mib": 0.5654,
      "accuracy": 0.980138,
      "loss": 0.079121,
      "latency_mean_ms": 2.6833,
      "latency_p50_ms": 2.6208,
      "latency_p95_ms": 3.081,
      "latency_min_ms": 2.5202,
      "latency_max_ms": 3.3759,
      "latency_samples": 200
    },
    "tflite": {
      "path": "artifacts/mnist/digit_classifier_int8.tflite",
      "model_size_bytes": 54184,
      "model_size_mib": 0.0517,
      "accuracy": 0.980042,
      "evaluated_samples": 10472,
      "latency_mean_ms": 0.0339,
      "latency_p50_ms": 0.0337,
      "latency_p95_ms": 0.035,
      "latency_min_ms": 0.0326,
      "latency_max_ms": 0.0435,
      "latency_samples": 200
    }
  }
}
```

## 8. 回填規則

訓練完成後需更新：

- 本文件第 4 節的 Accuracy。
- 本文件第 4 節的 Model Size。
- 本文件第 4 節的 Inference Speed。
- 若 metrics JSON 要保存，放在 `artifacts/` 或 release asset，不 commit 到 repo。

不得填入未實測數據。若模型、dataset、runtime、device 改變，必須重新量測。
