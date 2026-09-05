---
name: flutter-objekts-screenshots
description: Set up or optimize Flutter widget-test screenshots with the objekts package, keeping image capture separate from ordinary unit and widget tests. Use for review PNGs, batched screen captures, and slow objekts screenshot workflows.
---

# Flutter Objekts Screenshots

Keep ordinary tests fast by running screenshot tests explicitly. This skill
targets VM-based `flutter test` captures, not emulator or native OS screenshots.

## Use with any coding agent

Read this file as the workflow entry point. Use the agent's available file,
terminal, and image-viewing tools; no particular agent tool names or integrations
are required. Resolve resource links relative to this skill folder, and run
Flutter commands from the consuming app's root.

Agents with native skill support can load this folder through their supported
skill mechanism. Otherwise, ask the agent to read this file directly. Keep
`assets/` and `references/` beside it when copying the skill. The optional
`agents/` directory contains host-specific discovery metadata; the workflow
and templates work independently of that metadata.

## Inspect and choose the smallest capture

1. Inspect the consuming app's `pubspec.yaml`, resolved objekts dependency,
   Flutter SDK launcher, test commands, fixtures, and `flutter_test_config.dart`
   files. Check the installed package's public exports before using batch APIs;
   if unavailable, use awaited `screenshots()` calls or propose an upgrade.
2. Identify the screen and state the user wants. Reuse local fixtures or fakes;
   control time, locale, theme, network images, and animations where relevant.
3. For review images, default to one representative phone, `pixelRatio: 1`,
   and stable state names. Preserve requested framing and existing golden
   resolution. Add device or theme variants only for the requested coverage.

## Keep capture outside ordinary tests

Put dedicated captures in a top-level `screenshot_test/` directory, beside
`test/`. Bare `flutter test` discovers `test/`; explicitly target
`screenshot_test/` for images. Keep behavioral assertions in ordinary tests
even when screenshot scenarios also exercise those interactions.

Load fonts in `screenshot_test/flutter_test_config.dart`, not in ordinary
test setup just for screenshots. Flutter chooses the closest config and does
not merge parent configs. Preserve any required shared initialization by
factoring it into a shared helper and calling it from both configs. Avoid
removing font setup that existing ordinary tests actually depend on.

Use the project's configured Flutter SDK launcher and command wrappers.
The plain commands below assume dependencies have already been resolved:

```bash
flutter test
flutter test screenshot_test/single_screenshot_test.dart
flutter test screenshot_test
```

Resolve dependencies after setup or dependency changes, rather than before
every capture. Use `--no-pub` for repeated runs only when resolution is current.
Keep screenshots as an explicit separate CI step when CI changes are requested.
Use existing artifact collection for `build/objekts/screenshots/` if available.

## Capture correctly and finish the files

- Use `screenshots()` for one image or when its file is needed immediately.
  For several related UI states, use `runScreenshotBatch` with
  `maxPendingCaptures: 2` and batch-level `pixelRatio: 1` initially.
- Await each `batch.capture()` before navigation or another capture. Keep UI
  operations sequential; the package handles encoding and file output in the
  background. Await the entire batch before reading or reporting its files.
  Results preserve capture declaration order. Batches cannot be nested.
- Pump the widget before capturing. After an interaction, pump the frames
  required by that transition and assert the intended state is ready. Prefer
  explicit animation durations or a bounded readiness loop over blind waits.
  Leave capture `settle` false; if settling is necessary, supply a finite,
  scenario-appropriate timeout. Repeating spinners must be controlled rather
  than waited out. Avoid settling both in the test and in capture.
- Pass the same `ObjektsDeviceConfig` to the test wrapper and `deviceFrame`.
  `pixelRatio: 1` lowers output pixel density; it does not change logical layout.
  For component reviews, a Finder matching exactly one renderable widget can
  reduce the captured area.
- Use distinct test descriptions and capture names. Set `overwrite: true`
  for repeatable review PNGs; give concurrent runs separate `outputDirectory`
  roots. Avoid broad cleanup of build artifacts as a rerun strategy.
- Keep `captureOnFailure` optional. The wrapper catches errors escaping its
  callback; it does not guarantee captures for framework-reported or teardown
  failures. An attempted failure capture preserves the original callback error.
- Golden comparisons are a separate assertion purpose. Preserve their
  dimensions, fonts, platform, and resolution. Update baselines only when
  requested, targeting the specific golden test:

  ```bash
  flutter test screenshot_test/catalog_golden_test.dart --update-goldens
  ```

## Reusable examples

For new setup, use these portable templates. Remove only the `.template`
suffix when copying them into the consuming app:

| Resource | Destination |
| --- | --- |
| [Font setup](assets/flutter_test_config.dart.template) | `screenshot_test/flutter_test_config.dart` |
| [Deterministic demo fixture](assets/preview_fixture.dart.template) | `screenshot_test/support/preview_fixture.dart` |
| [Single capture](assets/single_screenshot_test.dart.template) | `screenshot_test/single_screenshot_test.dart` |
| [Batched transitions](assets/batch_screenshot_test.dart.template) | `screenshot_test/batch_screenshot_test.dart` |

The examples need `flutter_test`, `objekts`, and `device_frame` as direct
development dependencies, plus Flutter and `uses-material-design: true`.
Select dependency versions compatible with the consuming app; reuse its
existing constraints. These examples use a local demo screen so they run
without app-specific services. Replace that fixture with the requested screen
and its deterministic dependencies after verifying setup.

## Verify and report

Run the smallest relevant screenshot file. Check the returned absolute paths,
PNG dimensions, expected state, readable text, and requested framing. Run it
again to confirm reruns work. If the agent cannot view images, report that
visual inspection remains unverified and provide the artifacts for review.
Verify ordinary tests neither execute the new
capture suite nor invoke its font setup. Report failures as failures, with
available artifacts; a PNG alone does not prove the test passed.

When diagnosing slowness, read [Performance troubleshooting](references/performance.md).
Report ordinary-test duration separately from screenshot duration and describe
any resolution or coverage tradeoff. Do not promise a fixed time or speedup.
