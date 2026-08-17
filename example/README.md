# objekts example app

This standalone Flutter app demonstrates the `objekts` screenshot test package.
It includes Android and iOS host projects under `android/` and `ios/`.

## Run the app

```bash
flutter pub get
flutter run
```

Use `flutter devices` to select a connected Android device or iOS simulator.

## Run the screenshot test

```bash
flutter test
```

The test captures portrait and landscape device variants. PNG artifacts are
written to `build/objekts/screenshots`.

The full device frame is included because the test uses `isFrameVisible: true`
and captures without a `Finder`:

```dart
await objekts.screenshots(name: 'home');
```

Focused captures using `finder:` intentionally crop the image to the selected
widget.
