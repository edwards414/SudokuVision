# 視覺模型數獨辨識與解題系統規格書

版本：0.1 討論稿  
日期：2026-05-27  
狀態：需求討論中，尚未進入實作

## 1. 專案目標

建立一個能透過圖片或相機畫面判讀數獨題目的系統，將 9x9 數獨表格轉換成結構化資料，並自動求解答案。系統應能讓使用者確認辨識結果，避免視覺模型誤判後直接產生錯誤解答。

核心流程：

1. 使用者提供數獨圖片、截圖或相機畫面。
2. 系統偵測數獨棋盤位置。
3. 系統校正透視、切割 81 個格子。
4. 系統判斷每格是空格或數字 1-9。
5. 使用者可檢查與修正辨識結果。
6. 系統驗證題目是否合法。
7. 系統求解並顯示答案。

## 2. 使用情境

### 2.1 拍照辨識

使用者用手機拍攝紙本數獨題目，系統自動框選棋盤、辨識數字並求解。

### 2.2 圖片匯入

使用者匯入截圖或照片，系統從圖片中找出數獨表格並辨識。

### 2.3 手動校正

當辨識錯誤時，使用者可以點選單格修改數字或清空格子。

### 2.4 顯示答案

系統可以用以下方式呈現答案：

- 在完整 9x9 表格中顯示所有答案。
- 只標示原本空格的解答。
- 疊加在原始圖片上，讓使用者對照題目。

## 3. MVP 範圍

第一版目標先完成「穩定可用」而不是追求所有情境。

### 3.1 必做功能

- 支援上傳單張數獨圖片。
- 偵測圖片中的 9x9 數獨棋盤。
- 自動做透視校正。
- 將棋盤切成 81 個格子。
- 辨識每格數字或空白。
- 顯示辨識後的 9x9 表格。
- 允許使用者手動修正任一格。
- 檢查題目是否違反數獨規則。
- 求解唯一解。
- 顯示解答。

### 3.2 暫不納入第一版

- 即時相機串流辨識。
- 多題同時辨識。
- 手寫數字高準確率辨識。
- 非標準尺寸數獨，例如 4x4、16x16。
- 變形規則數獨，例如對角線數獨、殺手數獨。
- 自動產生題目。

## 4. 系統架構

建議拆成四個主要模組：

### 4.1 影像前處理模組

職責：

- 讀取圖片。
- 灰階化、降噪、二值化。
- 偵測最大方形或近似方形區域。
- 進行透視校正。
- 產出標準化 9x9 棋盤圖片。

可用方法：

- OpenCV 輪廓偵測。
- Hough line detection。
- 角點偵測。
- 邊緣偵測後尋找最大四邊形。

### 4.2 格子切割模組

職責：

- 將校正後棋盤切成 81 個 cell。
- 去除格線干擾。
- 判斷 cell 是否可能含有數字。
- 輸出每格的小圖片。

輸出格式：

```json
{
  "cells": [
    {
      "row": 0,
      "col": 0,
      "image_ref": "cell_0_0.png",
      "is_empty_candidate": false
    }
  ]
}
```

### 4.3 視覺辨識模組

職責：

- 判斷每格是空白或數字。
- 輸出數字與信心分數。
- 對低信心格子標記需要人工確認。

建議策略：

- MVP 可先使用雲端視覺模型或 OCR 模型辨識完整棋盤。
- 若要提高穩定性，可結合 OpenCV 切格與單格數字分類模型。
- 長期可訓練本地 CNN 或使用 ONNX/TFLite，降低成本並支援離線。

輸出格式：

```json
{
  "grid": [
    [5, 3, 0, 0, 7, 0, 0, 0, 0],
    [6, 0, 0, 1, 9, 5, 0, 0, 0],
    [0, 9, 8, 0, 0, 0, 0, 6, 0],
    [8, 0, 0, 0, 6, 0, 0, 0, 3],
    [4, 0, 0, 8, 0, 3, 0, 0, 1],
    [7, 0, 0, 0, 2, 0, 0, 0, 6],
    [0, 6, 0, 0, 0, 0, 2, 8, 0],
    [0, 0, 0, 4, 1, 9, 0, 0, 5],
    [0, 0, 0, 0, 8, 0, 0, 7, 9]
  ],
  "confidence": [
    [0.98, 0.97, 1.0, 1.0, 0.96, 1.0, 1.0, 1.0, 1.0]
  ],
  "low_confidence_cells": [
    { "row": 0, "col": 4, "confidence": 0.62 }
  ]
}
```

### 4.4 數獨驗證與求解模組

職責：

- 檢查初始題目是否違反 row、column、box 規則。
- 判斷題目是否無解。
- 判斷是否唯一解。
- 產生完整答案。

建議演算法：

- Backtracking。
- Constraint propagation。
- Minimum Remaining Values，優先填候選數最少的格子。

輸出格式：

```json
{
  "status": "solved",
  "has_unique_solution": true,
  "solution": [
    [5, 3, 4, 6, 7, 8, 9, 1, 2],
    [6, 7, 2, 1, 9, 5, 3, 4, 8],
    [1, 9, 8, 3, 4, 2, 5, 6, 7],
    [8, 5, 9, 7, 6, 1, 4, 2, 3],
    [4, 2, 6, 8, 5, 3, 7, 9, 1],
    [7, 1, 3, 9, 2, 4, 8, 5, 6],
    [9, 6, 1, 5, 3, 7, 2, 8, 4],
    [2, 8, 7, 4, 1, 9, 6, 3, 5],
    [3, 4, 5, 2, 8, 6, 1, 7, 9]
  ],
  "message": null
}
```

## 5. 使用者介面需求

### 5.1 圖片輸入畫面

- 提供圖片上傳入口。
- 顯示原始圖片預覽。
- 顯示棋盤偵測框。
- 若偵測失敗，允許使用者重新上傳或手動標記四個角。

### 5.2 辨識確認畫面

- 顯示 9x9 數獨表格。
- 原始題目數字與空格應有明顯區分。
- 低信心格子需要標示。
- 點選格子後可修改數字 1-9 或清空。
- 修改後立即重新驗證是否合法。

### 5.3 解答畫面

- 顯示完整解答。
- 原始數字保持不變。
- 系統補上的答案用不同樣式呈現。
- 若無解或多解，清楚提示原因。

## 6. 技術選型討論

目前可考慮三種路線：

### 6.1 視覺模型優先

做法：

- 將圖片送給多模態視覺模型。
- 要求模型輸出 9x9 JSON grid。
- 搭配後端驗證與人工確認。

優點：

- 開發速度快。
- 對截圖、印刷字、不同版面有較高容忍度。

缺點：

- 成本較高。
- 延遲較高。
- 對格線、手寫字、模糊照片仍可能誤判。
- 需要嚴格 JSON schema 與結果驗證。

### 6.2 傳統 CV + OCR

做法：

- OpenCV 負責找棋盤、校正與切格。
- OCR 或小型分類模型負責辨識單格數字。

優點：

- 可控性高。
- 成本低。
- 較容易除錯。

缺點：

- 對拍攝角度、陰影、格線品質較敏感。
- 前處理需要調校。

### 6.3 混合式架構

做法：

- OpenCV 先把棋盤切成乾淨 cell。
- 視覺模型或 OCR 辨識每格。
- 低信心格子交給使用者確認。
- 解題器負責驗證與補救。

建議：

MVP 採用混合式架構。這樣能保留視覺模型的彈性，也能透過結構化切格降低模型誤判率。

## 7. 資料格式

### 7.1 數獨題目格式

使用 9x9 integer matrix：

- `0` 代表空格。
- `1-9` 代表已知數字。

```json
[
  [5, 3, 0, 0, 7, 0, 0, 0, 0],
  [6, 0, 0, 1, 9, 5, 0, 0, 0],
  [0, 9, 8, 0, 0, 0, 0, 6, 0],
  [8, 0, 0, 0, 6, 0, 0, 0, 3],
  [4, 0, 0, 8, 0, 3, 0, 0, 1],
  [7, 0, 0, 0, 2, 0, 0, 0, 6],
  [0, 6, 0, 0, 0, 0, 2, 8, 0],
  [0, 0, 0, 4, 1, 9, 0, 0, 5],
  [0, 0, 0, 0, 8, 0, 0, 7, 9]
]
```

### 7.2 辨識狀態

```json
{
  "recognition_status": "needs_review",
  "grid": [],
  "confidence": [],
  "issues": [
    {
      "type": "low_confidence",
      "row": 3,
      "col": 5,
      "message": "辨識信心偏低，建議人工確認"
    }
  ]
}
```

### 7.3 求解狀態

狀態值：

- `solved`：已求解。
- `invalid_puzzle`：題目違反數獨規則。
- `no_solution`：無解。
- `multiple_solutions`：多解。
- `needs_review`：辨識信心不足，建議人工確認。

## 8. 驗證規則

### 8.1 題目合法性

系統需檢查：

- 每一列不可重複出現同一數字。
- 每一欄不可重複出現同一數字。
- 每一個 3x3 宮格不可重複出現同一數字。
- 所有數值只能是 0-9。
- grid 必須是 9x9。

### 8.2 解答合法性

系統需檢查：

- 解答每格皆為 1-9。
- 解答符合 row、column、box 規則。
- 解答不得改變原始題目已給定的數字。

## 9. 錯誤處理

### 9.1 找不到棋盤

處理方式：

- 顯示偵測失敗。
- 允許重新上傳圖片。
- 後續版本可支援手動拖曳四角校正。

### 9.2 辨識結果不完整

處理方式：

- 標示低信心格子。
- 允許人工修正。
- 修正後重新驗證。

### 9.3 題目無解

處理方式：

- 顯示「目前辨識結果無解，請檢查題目數字」。
- 高亮可能衝突的 row、column、box。

### 9.4 題目多解

處理方式：

- 顯示「此題不只一組解，請確認題目是否完整」。
- 可仍顯示其中一組解，但需明確標記不是唯一解。

## 10. 品質標準

MVP 建議達成：

- 印刷體數獨截圖辨識成功率：95% 以上。
- 清楚照片的棋盤偵測成功率：90% 以上。
- 單題求解時間：100ms 內，不含視覺模型延遲。
- 使用者可在 3 步內完成「上傳、確認、看答案」。
- 所有模型輸出必須經過程式驗證，不可直接信任。

## 11. 測試計畫

### 11.1 單元測試

- grid 格式驗證。
- row、column、box 重複檢查。
- backtracking solver。
- 唯一解檢查。
- 無解與多解案例。

### 11.2 影像測試

建立測試圖片集：

- 乾淨截圖。
- 紙本照片。
- 斜拍照片。
- 低光照片。
- 有陰影照片。
- 粗格線與細格線。
- 空白格很多的題目。
- 數字接近格線的題目。

### 11.3 人工驗收

每張測試圖需記錄：

- 是否成功找到棋盤。
- 是否成功切出 81 格。
- 辨識錯誤格數。
- 是否能透過人工修正後求解。

## 12. 安全與隱私

- 圖片可能包含桌面、書本、螢幕或個人資訊。
- 若使用雲端視覺模型，需在介面上告知圖片會送到模型服務。
- 不應永久儲存使用者圖片，除非使用者明確同意。
- 日誌中不可記錄原始圖片內容。
- 可只保留匿名化的辨識結果與錯誤統計。

## 13. 開發階段建議

### Phase 1：核心解題器

- 建立 grid 資料格式。
- 完成合法性檢查。
- 完成 solver。
- 完成唯一解檢查。

### Phase 2：圖片到 grid

- 建立圖片上傳流程。
- 完成棋盤偵測與透視校正。
- 完成 81 格切割。
- 接上視覺模型或 OCR。

### Phase 3：人工確認介面

- 建立 9x9 編輯介面。
- 標示低信心格子。
- 修改後即時驗證。

### Phase 4：答案呈現

- 顯示完整解答。
- 區分原題與補答案。
- 處理無解、多解、辨識錯誤情境。

### Phase 5：準確率改善

- 建立測試圖片集。
- 統計錯誤類型。
- 針對格線、陰影、模糊、手寫字優化。

## 14. 待討論問題

1. 目標平台是 Web、手機 App、桌面工具，還是先做命令列原型？
2. 圖片來源主要是截圖、紙本照片，還是即時相機？
3. 是否接受使用雲端視覺模型，或希望全部離線？
4. 第一版是否需要支援手寫數字？
5. 答案要只顯示表格，還是要疊回原始圖片？
6. 你比較重視開發速度、辨識準確率、離線能力，還是成本？
7. 是否需要保留辨識紀錄與歷史題目？

## 15. 初步結論

建議第一版採用混合式架構：

- OpenCV 負責棋盤偵測、透視校正與切格。
- 視覺模型或 OCR 負責數字辨識。
- 使用者介面負責人工確認。
- 本地 solver 負責驗證、求解與唯一解判斷。

這樣的設計能避免完全依賴視覺模型，也能把模型錯誤限制在可修正的範圍內。第一個可交付版本應聚焦在「圖片匯入、辨識、人工確認、求解」四件事。

## 16. 已落地模型決策

第一版數字辨識採用 LeNet-like Tiny CNN，而不是原始 LeNet、LaneNet 或大型視覺模型。

實作決策：

- 數字辨識單位是校正後棋盤中的單一 cell。
- 每個 cell 會裁掉外圍格線，轉成 `32x32x1` 灰階 foreground tensor。
- 模型輸出 10 類：`empty, 1, 2, 3, 4, 5, 6, 7, 8, 9`。
- `0` 在 grid 中永遠代表空格，不代表數字 0。
- 空格判斷採用 CV+模型：先用黑色像素比例與最大連通區域判斷明顯空格，再用模型輸出機率做最終分類。
- `confidence < 0.85` 的 cell 會標記為 `low_confidence_cells`，需要人工確認。
- MNIST 只作為訓練與 TFLite pipeline 起步資料；正式印刷體準確率仍需加入合成字型與實拍 cell 測試集驗證。
- 手機本地部署以 TFLite int8 quantization 為主。

目前程式模組：

- `sudoku_vision/preprocessing.py`：cell 前處理、空格特徵、9x9 切格。
- `sudoku_vision/model.py`：Tiny CNN 架構。
- `sudoku_vision/recognizer.py`：TFLite 或注入式 classifier 推論、confidence 與 low-confidence 輸出。
- `sudoku_vision/board.py`：OpenCV 棋盤偵測與透視校正。
- `sudoku_vision/solver.py`：grid 驗證、唯一解求解。
- `scripts/train_mnist.py`：MNIST 1-9 加合成空格訓練。
- `scripts/export_tflite.py`：int8 TFLite 匯出。
- `scripts/recognize_image.py`：圖片到 grid/solver 的端到端推論腳本。

## 17. 開發流程要求

後續製作過程依循 TDD。

固定循環：

1. Red：先寫描述預期行為的失敗測試。
2. Green：只實作讓測試通過所需的最小功能。
3. Refactor：在測試保護下整理程式碼。

新增相機串流、Docker API、Flutter 介面或模型訓練功能時，都必須先定義測試與驗收條件。詳細流程記錄於 `docs/TDD_WORKFLOW.md`。

## 18. CI/CD 與容器映像

容器發布目標為 GHCR。

流程：

1. GitHub Actions 在 push 到 `main`、版本 tag 或手動觸發時執行。
2. CI 先跑 Python unit tests。
3. Docker build `test` target，於建置階段再次執行 `pytest`。
4. Docker build `runtime` target，並用 `python -m sudoku_vision.cli health` 驗證映像可啟動。
5. 非 pull request 事件登入 GHCR 並推送 image。
6. 推送完成後從 GHCR pull 回 `sha-<commit-sha>` tag，再執行 health check。

映像 tag：

- `latest`：default branch。
- `sha-<commit-sha>`：每次可發布事件。
- `v*.*.*`：版本 tag。

## 19. Windows / Linux 相機 discovery

相機 discovery 輸出固定 JSON schema，供 Flutter、API service 或 Docker health/debug 工具使用。

Linux：

- 掃描 `/dev/video*`。
- 從 `/sys/class/video4linux/<device>/name` 讀取相機名稱。
- Docker 內需使用 `--device=/dev/video0:/dev/video0` 或等效 compose device mapping。
- Backend 標記為 `v4l2`。

Windows：

- 使用 OpenCV `VideoCapture(index, CAP_DSHOW)` 探測 camera index。
- Backend 標記為 `opencv-dshow`。
- 建議在 Windows host 端 discovery 相機；若使用 Docker Desktop，優先把 host camera 轉為 RTSP/MJPEG/TCP stream 給容器讀取。

CLI：

```bash
python -m sudoku_vision.cli cameras
```

回傳範例：

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

## 20. Flutter Apple Design

Flutter 介面必須與 Apple 設計風格一致，並以 Cupertino 為主要 UI 元件系統。

要求：

- App root 使用 `CupertinoApp`。
- 每頁使用 `CupertinoPageScaffold`。
- 導覽使用 `CupertinoNavigationBar`。
- 顏色使用 `CupertinoColors` 與 iOS system colors。
- 每頁必須處理 `SafeArea`。
- 支援 Dynamic Type。
- 低信心 cell 需要顏色以外的狀態提示。
- 不使用 Material `Scaffold`、`AppBar`、FAB、SnackBar 作為主要 iOS UI。

詳細設計規範與驗收標準記錄於 `docs/FLUTTER_APPLE_DESIGN.md`。

## 21. TinyCNN 訓練結果規格

TinyCNN 的正式訓練結果以 `docs/TINY_CNN_MODEL_RESULT_SPEC.md` 為準。

需記錄：

- Accuracy。
- Model Size。
- Inference Speed。
- 訓練 dataset。
- 量測 device/runtime。
- Keras 與 TFLite int8 結果差異。

目前狀態：未量測。repo 內尚未包含 `artifacts/mnist/model.keras` 或 `artifacts/mnist/digit_classifier_int8.tflite`，因此不得填入推測數字。
