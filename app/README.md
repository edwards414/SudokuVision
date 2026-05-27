# Sudoku Vision App

Flutter Cupertino UI for Sudoku Vision.

## Flow

- Camera tab shows the stream, detected board frame, recognition grid, and solver answer in one fixed mobile viewport without page scrolling.
- `即時辨識` polls `/recognize/capture`, draws the detected outer frame/result overlay on the preview, and commits the latest result to the inline grid.
- `拍照辨識` runs one capture/recognize request, keeps the user on the Camera tab, and leaves the returned board frame visible on the stream.
- If automatic board detection fails, the app sends the visible blue guide as `fallback_corners` so the backend can retry without returning a 502 immediately.
- Review and Solution tabs remain available for focused correction or full-screen answer viewing.

## Run

```bash
flutter pub get
flutter run -d macos
flutter test
```

The app connects to the default backend automatically:

```bash
flutter run -d macos
flutter run --dart-define=SUDOKU_API_ENDPOINT=http://192.168.1.10:8080
```

Use a LAN host IP for a physical phone; `localhost` only works when the app runs on the same machine as the container.
