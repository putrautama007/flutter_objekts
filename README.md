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
      ref: v0.1.2
```

## AI agent screenshot skill

Use the [screenshot skill](skills/flutter-objekts-screenshots/SKILL.md) to help
your AI agent set up screenshots while keeping ordinary tests fast.

From your Flutter app's directory, run this command and select your agent
(requires Node.js 22.20+, npm, and Git):

```bash
npx skills add putrautama007/flutter_objekts --skill flutter-objekts-screenshots
```

Then ask your agent:

```text
Use flutter-objekts-screenshots to set up screenshots for this app while
keeping ordinary unit and widget tests fast.
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

## Capture many screens faster

Use `runScreenshotBatch` when one widget test captures several screens. Each
`batch.capture` call freezes the current rendered frame, then lets lossless PNG
encoding and file output continue in bounded background workers while the test
navigates to the next state:

```dart
final results = await objekts.runScreenshotBatch(
  (batch) async {
    await batch.capture(name: 'home');

    await tester.tap(find.byKey(const Key('activity-tab')));
    await tester.pump();
    await batch.capture(name: 'activity');

    await tester.tap(find.byKey(const Key('settings-tab')));
    await tester.pump();
    await batch.capture(name: 'settings');
  },
);

print(results.map((result) => result.path));
```

The returned results preserve capture order, and all files are ready when
`runScreenshotBatch` completes. Two captures may be pending by default. Set
`maxPendingCaptures` to match the memory and CPU available on the test worker.
A batch-level `pixelRatio` supplies a default that individual captures can
override.

The existing `screenshots()` function remains useful when the file must be
available immediately after one capture.

## Golden file testing

Use `matchesGolden` to compare the captured surface or one Finder-selected
widget with a checked-in PNG:

```dart
objekts.testWidgets(
  'renders home',
  (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Hello')),
      ),
    );

    await objekts.matchesGolden(name: 'home');
  },
);
```

Golden files are stored under `goldens/test/<test-description>/` by default.
Device-configured tests add their device label to the path. Pass
`goldenDirectory` to use a different baseline root. Golden comparisons use
Flutter's exact pixel comparator, including its standard failure diff output.

Create or update baselines with:

```bash
flutter test --update-goldens
```

Golden comparisons can share the faster pipeline with normal artifacts:

```dart
await objekts.runScreenshotBatch((batch) async {
  await batch.capture(name: 'review-artifact');
  await batch.matchGolden(name: 'review-baseline');
});
```

All PNG work finishes first, then golden comparisons run in declaration order
using Flutter's configured comparator.

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

The test in `example/test/screenshot_test.dart` captures four example states
in portrait and landscape configurations.
Artifacts are written to `example/build/objekts/screenshots`.

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

## Device and visual variant matrices

The standard Flutter `TestVariant` parameter composes with device variants.
For example, this registers a device × theme matrix while keeping every case
as an independently reported widget test:

```dart
final themes = ValueVariant<ThemeMode>(
  <ThemeMode>{ThemeMode.light, ThemeMode.dark},
);

objekts.testWidgetsForDevices(
  'renders the catalog matrix',
  (tester, config) async {
    await tester.pumpWidget(
      objekts.deviceFrame(
        config: config,
        child: MaterialApp(
          themeMode: themes.currentValue,
          home: const CatalogScreen(),
        ),
      ),
    );

    await objekts.runScreenshotBatch((batch) async {
      await batch.capture(name: 'catalog');
    });
  },
  devices: devices,
  variant: themes,
);
```

Artifacts are isolated under
`<test>/<device>/<variant>/<capture>.png`. Tests without a Flutter variant keep
the existing directory layout.

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
python3 -m unittest discover -s tool -p 'test_*.py'
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test

cd example
flutter pub get
flutter analyze
flutter test

# Explicit performance gate (not part of the normal test suite)
flutter test benchmark/screenshot_batch_benchmark_test.dart
```

HTML reports, screenshot indexes, web file output, and pub.dev publication are
intentionally outside the v1 scope.
