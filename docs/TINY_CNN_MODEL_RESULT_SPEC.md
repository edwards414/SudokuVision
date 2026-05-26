# TinyCNN 模型訓練結果規格書

版本：0.1  
狀態：未量測  
適用模型：LeNet-like TinyCNN single-cell classifier

## 1. 結論摘要

目前 repo 尚未包含正式訓練 artifact，因此 Accuracy、Model Size、Inference Speed 尚未量測。

原因：

- 目前沒有 `artifacts/mnist/model.keras`。
- 目前沒有 `artifacts/mnist/digit_classifier_int8.tflite`。
- `.keras` 與 `.tflite` 會被 `.gitignore` 排除，不直接 commit 到原始碼 repo。

本文件先固定結果規格、量測方法、驗收門檻與填寫格式。模型訓練完成後，使用 `scripts/evaluate_tiny_cnn.py` 產生 metrics JSON，再把結果回填到本規格書。

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

### 4.1 Accuracy

| Model Artifact | Dataset | Accuracy | Loss | 狀態 |
| --- | --- | ---: | ---: | --- |
| `artifacts/mnist/model.keras` | MNIST 1-9 + synthetic empty | 未量測 | 未量測 | artifact 尚未產生 |
| `artifacts/mnist/digit_classifier_int8.tflite` | MNIST 1-9 + synthetic empty | 未量測 | N/A | artifact 尚未產生 |
| `artifacts/printed_cells/*` | printed Sudoku cells | 未量測 | N/A | dataset 尚未建立 |

### 4.2 Model Size

| Model Artifact | Format | Model Size | 狀態 |
| --- | --- | ---: | --- |
| `artifacts/mnist/model.keras` | Keras | 未量測 | artifact 尚未產生 |
| `artifacts/mnist/digit_classifier_int8.tflite` | TFLite int8 | 未量測 | artifact 尚未產生 |

### 4.3 Inference Speed

量測單位：單一 cell，輸入 shape `1x32x32x1`。  
量測欄位：mean、p50、p95、min、max。  
warmup：預設 20 次。  
sample runs：預設 200 次。

| Model Artifact | Device | Runtime | p50 ms/cell | p95 ms/cell | Estimated 81-cell p50 | 狀態 |
| --- | --- | --- | ---: | ---: | ---: | --- |
| `artifacts/mnist/model.keras` | 未量測 | TensorFlow/Keras | 未量測 | 未量測 | 未量測 | artifact 尚未產生 |
| `artifacts/mnist/digit_classifier_int8.tflite` | 未量測 | TFLite | 未量測 | 未量測 | 未量測 | artifact 尚未產生 |

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

## 8. 回填規則

訓練完成後需更新：

- 本文件第 4 節的 Accuracy。
- 本文件第 4 節的 Model Size。
- 本文件第 4 節的 Inference Speed。
- 若 metrics JSON 要保存，放在 `artifacts/` 或 release asset，不 commit 到 repo。

不得填入未實測數據。若模型、dataset、runtime、device 改變，必須重新量測。
