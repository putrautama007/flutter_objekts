# objekts

`objekts` captures the rendered output of Flutter widget tests as PNG files. It
supports full test-surface screenshots, focused `Finder` screenshots, failure
artifacts, and ordered multi-device runs.

This is a test utility package, not a native Flutter plugin. It currently runs
on VM-based `flutter test` targets.

## Install from GitHub

Add the repository as a development dependency:

```yaml
dev_dependencies:
  objekts:
    git:
      url: https://github.com/putrautama007/flutter_objekts.git
      ref: v0.1.0
```

## Capture a screenshot

```dart
import 'package:flutter/material.dart';
import 'package:objekts/objekts.dart' as objekts;

objekts.testWidgets(
  'renders home',
  (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Hello')),
      ),
    );

    final result = await objekts.screenshots(name: 'home');
    print(result.path);
  },
);
```

Screenshots are written under `build/objekts/screenshots` by default. A custom
directory can be passed with `outputDirectory`. Explicit duplicate filenames
fail unless `overwrite: true` is used.

## Render text in screenshots

Flutter widget tests use a block-style fallback font unless application fonts
are loaded first. Add a `test/flutter_test_config.dart` file to the project
that runs the screenshot tests:

```dart
import 'dart:async';

import 'package:objekts/objekts.dart' as objekts;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await objekts.loadAppFonts();
  await testMain();
}
```

`loadAppFonts()` loads the bundled Roboto font and fonts registered in the
application or its package dependencies through `pubspec.yaml`. It is safe to
call more than once.

## Example app

The repository includes a standalone Flutter app and screenshot test under
`example/`. Run it from the example directory:

```bash
cd example
flutter pub get
flutter test
flutter run
```

The test in `example/test/screenshot_test.dart` captures the app in portrait
and landscape configurations. Artifacts are written to
`example/build/objekts/screenshots`.

The example also contains standard Android and iOS host projects under
`example/android` and `example/ios`.

## Device-framed screenshots

`device_frame` controls the simulated device, orientation, safe areas, and
pixel ratio. Pass the same immutable configuration to the test wrapper and
the widget wrapper:

```dart
import 'package:device_frame/device_frame.dart';
import 'package:objekts/objekts.dart' as objekts;

final phone = objekts.ObjektsDeviceConfig(
  device: Devices.ios.iPhone13,
  orientation: Orientation.portrait,
);

objekts.testWidgets(
  'renders home on a phone',
  (tester) async {
    await tester.pumpWidget(
      objekts.deviceFrame(
        config: phone,
        child: const MyApp(),
      ),
    );

    await objekts.screenshots(name: 'home');
  },
  deviceConfig: phone,
  captureOnFailure: true,
);
```

The test surface uses the oriented frame size when the bezel is visible and
the oriented screen size when it is hidden. Device captures use the device
pixel ratio unless a per-capture `pixelRatio` is supplied. Leave
`isFrameVisible` as `true` to include the complete device frame; set it to
`false` only when a screen-only artifact is desired.

## Multiple devices

`testWidgetsForDevices` registers one isolated test variant per configuration.
The variants run in the order supplied, and each callback receives its active
configuration:

```dart
final devices = <objekts.ObjektsDeviceConfig>[
  phone,
  objekts.ObjektsDeviceConfig(
    device: Devices.android.smallTablet,
    orientation: Orientation.landscape,
    isFrameVisible: false,
  ),
];

objekts.testWidgetsForDevices(
  'renders home responsively',
  (tester, config) async {
    await tester.pumpWidget(
      objekts.deviceFrame(
        config: config,
        child: const MyApp(),
      ),
    );
    await objekts.screenshots(name: 'home');
  },
  devices: devices,
  captureOnFailure: true,
);
```

Each device gets its own artifact directory and failure screenshot. Duplicate
device labels receive deterministic numeric suffixes.

## Focused screenshots

Pass a `Finder` to crop the image to exactly one renderable widget. Optional
uniform padding can be added around the target:

```dart
await objekts.screenshots(
  finder: find.byKey(const Key('profile-card')),
  name: 'profile-card',
  padding: 12,
);
```

The Finder must match exactly one widget. Captures use the current rendered
frame; settling is opt-in with `settle: true` and a bounded `settleTimeout`.

## Default artifact layout

```text
build/objekts/screenshots/
  test/renders-home/
    iphone-13-portrait/ home.png
    small-landscape/ home.png
```

When the test runner does not expose source-file metadata, the sanitized test
description is used as the stable test directory.

## Development

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test

cd example
flutter pub get
flutter analyze
flutter test
```

HTML reports, screenshot indexes, golden comparisons, web file output, and
pub.dev publication are intentionally outside the v1 scope.
