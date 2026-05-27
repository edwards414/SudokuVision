# Sudoku Vision App

Flutter Cupertino UI for Sudoku Vision.

## Flow

- Camera tab shows live preview, recognition grid, and solver answer in the same window.
- `即時辨識` polls `/recognize/capture`, draws the overlay on the preview, and commits the latest result to the inline grid.
- `拍照辨識` runs one capture/recognize request and keeps the user on the Camera tab.
- Review and Solution tabs remain available for focused correction or full-screen answer viewing.

## Run

```bash
flutter pub get
flutter run -d macos
flutter test
```

Configure backend and camera bridge in the Settings tab.
