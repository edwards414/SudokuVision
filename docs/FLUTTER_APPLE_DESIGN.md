# Flutter Apple Design

本專案 Flutter 介面必須以 Apple Human Interface Guidelines 為主要設計依據，並使用 Flutter Cupertino 元件建立接近 iOS 原生的體驗。

參考依據：

- Apple Human Interface Guidelines：hierarchy、consistency、accessibility、typography、color。
- Flutter Cupertino widgets：`CupertinoApp`、`CupertinoPageScaffold`、`CupertinoNavigationBar` 等 iOS-style widgets。

## 1. App Shell

Flutter app 根節點使用：

```dart
CupertinoApp(
  debugShowCheckedModeBanner: false,
  theme: CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: CupertinoColors.activeBlue,
  ),
  home: CameraReviewPage(),
)
```

頁面骨架使用 `CupertinoPageScaffold`，不要使用 `MaterialApp`、`Scaffold`、`AppBar` 作為主要 iOS UI。

```dart
CupertinoPageScaffold(
  navigationBar: CupertinoNavigationBar(
    middle: Text('Sudoku Vision'),
  ),
  child: SafeArea(
    child: CameraReviewView(),
  ),
)
```

允許在底層使用非視覺性的 Flutter 基礎 widget，例如 `CustomPaint`、`LayoutBuilder`、`Stack`、`GridView`，但視覺控制元件優先使用 Cupertino。

## 2. Navigation

導覽規則：

- 頂部導覽使用 `CupertinoNavigationBar`。
- 返回使用 iOS 標準 back behavior。
- 彈出確認使用 `CupertinoAlertDialog`。
- 底部操作可使用 `CupertinoTabScaffold` 或 iOS-style bottom action bar。
- 暫不使用 Android Material drawer、floating action button 或 snackbar。

建議頁面：

1. Camera：同一個相機視窗中顯示 live preview、即時辨識結果與答案。
2. Review：9x9 辨識表格、低信心 cell 修正。
3. Solution：完整答案與原題/補答案區分。
4. Settings：相機來源、模型狀態、API endpoint。

## 3. Visual Style

整體風格：

- 背景使用 `CupertinoColors.systemGroupedBackground`。
- 區塊背景使用 `CupertinoColors.secondarySystemGroupedBackground`。
- 主要動作用 `CupertinoColors.activeBlue`。
- 錯誤與衝突用 `CupertinoColors.systemRed`。
- 警告與低信心用 `CupertinoColors.systemOrange`。
- 成功或已解題狀態用 `CupertinoColors.systemGreen`。

避免：

- Material Design visual language。
- 大量裝飾性漸層。
- 卡片堆卡片。
- 非 iOS 風格的 FAB、SnackBar、BottomSheet。
- 過度品牌化的單色主題。

## 4. Typography

文字使用 Apple 系統字體概念，Flutter 中不硬指定自訂字型，讓 iOS 使用系統字體。

要求：

- 支援 Dynamic Type。
- 不用 viewport width 動態縮放字體。
- 表格與按鈕文字不可溢出。
- 重要數字與狀態需在最大 accessibility text size 下仍可讀。
- 低信心 cell 不只靠顏色傳達，也要有圖示或明確狀態。

Flutter 實作建議：

```dart
final textStyle = CupertinoTheme.of(context).textTheme.textStyle;
```

## 5. Layout

所有主要頁面必須使用 `SafeArea`。

相機預覽：

- 以畫面主要區域呈現，不放在裝飾性卡片中。
- 棋盤偵測框疊在 preview 上。
- 狀態列使用 iOS-style compact status row。
- 即時辨識時，Camera 頁需在同一個相機視窗內顯示辨識 grid 與 solver 答案，不自動跳轉到其他分頁。
- Camera 頁可使用 segmented control 在「辨識結果」與「答案」間切換。

9x9 review grid：

- 使用固定比例正方形。
- 每個 cell 尺寸穩定，不因 hover、選取、錯誤狀態改變 layout。
- 原始題目數字與使用者修改數字要有區分。
- 低信心 cell 使用 `systemOrange` border 或背景提示。
- 衝突 cell 使用 `systemRed` 提示。

Solution：

- 原題數字維持較高權重。
- 系統補答案使用不同但克制的樣式。
- 無解、多解、invalid puzzle 使用 `CupertinoAlertDialog` 或 inline iOS-style message。

## 6. Controls

使用 Cupertino 控制元件：

- Button：`CupertinoButton`
- Switch：`CupertinoSwitch`
- Segmented control：`CupertinoSlidingSegmentedControl`
- Text input：`CupertinoTextField`
- Picker：`CupertinoPicker`
- Dialog：`CupertinoAlertDialog`
- Navigation：`CupertinoNavigationBar`
- Icons：`CupertinoIcons`

數字編輯器建議：

- 點選 cell 後顯示 iOS-style number pad。
- 提供 `1-9` 與 clear。
- clear 用 icon 或簡短文字，避免冗長說明。
- 修改後即時重新 validation。

## 7. Accessibility

最低要求：

- 支援 Dynamic Type。
- 觸控目標維持足夠尺寸。
- 不只用顏色表示錯誤或低信心。
- 每個 cell 應有 semantic label，例如 `Row 3 Column 5, low confidence, predicted 7`。
- 相機畫面需要有非視覺狀態文字，例如 `Board detected`、`Move closer`。
- VoiceOver 使用者可完成 review 與 correction flow。

## 8. Flutter 與後端資料對接

Flutter UI 接收後端 JSON：

```json
{
  "grid": [[0, 0, 0, 0, 0, 0, 0, 0, 0]],
  "confidence": [[1.0, 0.92, 0.88, 1.0, 1.0, 0.74, 1.0, 1.0, 1.0]],
  "low_confidence_cells": [
    { "row": 0, "col": 5, "predicted": 7, "confidence": 0.74 }
  ],
  "status": "needs_review"
}
```

UI 狀態映射：

- `needs_review`：Camera 視窗顯示 review grid，聚焦低信心 cell。
- `solved`：Camera 視窗顯示答案，Solution page 可保留作為完整檢視。
- `invalid_puzzle`：標示衝突 row、column、box。
- `no_solution`：提示檢查辨識結果。
- `multiple_solutions`：提示題目不完整。

## 9. Acceptance Criteria

Flutter UI 實作完成需符合：

- Root app 使用 `CupertinoApp`。
- 每頁使用 `CupertinoPageScaffold`。
- 導覽使用 `CupertinoNavigationBar`。
- 主要互動控制元件使用 Cupertino variants。
- 所有頁面使用 `SafeArea`。
- 支援 Dynamic Type。
- 低信心 cell 有非純色彩提示。
- Camera 頁同一個相機視窗內可看見即時辨識結果與答案。
- Widget tests 覆蓋 camera、review、solution 三個主要狀態。
- 不混入 Material scaffold、app bar、FAB、snackbar 作為主要 UI。
