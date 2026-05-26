# TDD 開發流程

本專案後續製作過程採用 TDD。每個功能、修正與整合點都依照 Red-Green-Refactor 推進。

## 1. 基本循環

### Red

先寫測試，確認測試會失敗。

測試必須描述預期行為，例如：

- 棋盤偵測不到時應回傳明確錯誤。
- 低信心 cell 應進入 `low_confidence_cells`。
- solver 不應接受違反數獨規則的 grid。
- Docker API 應回傳固定 JSON schema。
- Flutter 收到 `needs_review` 時應顯示可編輯表格。

### Green

只寫剛好足夠的實作讓測試通過。

避免在 Green 階段順手加入未測需求、未討論 API 或額外重構。

### Refactor

測試通過後再整理程式碼。

重構不能改變外部行為；若行為需要改變，先回到 Red 階段新增或修改測試。

## 2. 測試分層

### Core Unit Tests

目標：快速、穩定、不依賴硬體。

涵蓋：

- cell 前處理。
- empty cell CV 判斷。
- model wrapper 輸出轉換。
- confidence threshold。
- grid validation。
- unique-solution solver。

執行：

```bash
pytest
```

### Vision Integration Tests

目標：驗證圖片到 grid 的 pipeline。

涵蓋：

- 棋盤四角偵測。
- 透視校正。
- 81 格切割。
- 低信心格標記。
- 偵測失敗錯誤處理。

測試資料放置建議：

```text
fixtures/images/
  clean_printed_01.jpg
  angled_photo_01.jpg
  shadow_photo_01.jpg
  no_board_01.jpg
```

### Model Tests

目標：驗證 Tiny CNN 與 TFLite pipeline。

涵蓋：

- Keras model input/output shape。
- TFLite model input/output shape。
- int8 quantization 後仍能輸出 10 類機率。
- MNIST 起步模型可完成 smoke training。
- 印刷體 cell 測試集準確率達標後才可宣稱支援印刷體。

### API Contract Tests

目標：固定 Docker vision service 和 Flutter 的介面。

涵蓋：

- `GET /health`。
- `GET /camera/status`。
- `POST /capture`。
- `GET /result/{id}`。
- WebSocket event schema。
- 錯誤狀態：`camera_unavailable`、`board_not_found`、`needs_review`、`invalid_puzzle`、`no_solution`。

### Flutter Widget Tests

目標：確保 UI 行為跟 API 狀態一致。

涵蓋：

- 顯示 camera preview 狀態。
- 顯示辨識中狀態。
- 顯示 9x9 grid。
- 標示低信心格。
- 允許人工修正 cell。
- 顯示 solver answer。

## 3. 開發順序

每個 milestone 都先定義測試，再實作。

1. Core solver 與 grid schema。
2. Cell preprocessing 與 empty detection。
3. Tiny CNN wrapper 與 mock classifier。
4. Board detection 與 81 cell extraction。
5. TFLite export 與推論 smoke test。
6. Docker API contract。
7. Camera stream reader。
8. Flutter API client。
9. Flutter grid review UI。
10. End-to-end demo。

## 4. Done Definition

功能完成必須同時滿足：

- 有對應測試。
- 測試先失敗過，實作後通過。
- `pytest` 通過。
- API 或資料格式有變更時，文件同步更新。
- 低信心或錯誤情境有明確測試。
- 不把模型輸出直接視為可靠答案，必須經過 validation 或人工確認流程。

## 5. Commit 建議

若使用 git，每個功能建議拆成小 commit：

1. `test: add failing tests for ...`
2. `feat: implement ...`
3. `refactor: clean up ...`

若不分 commit，也至少在開發紀錄中保留 Red、Green、Refactor 的步驟。
