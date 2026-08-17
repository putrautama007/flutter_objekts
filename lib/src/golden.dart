import 'dart:io';

import 'package:flutter_test/flutter_test.dart' as flutter_test;

import 'capture.dart';
import 'context.dart';
import 'models.dart';
import 'paths.dart';

/// Captures the current Flutter test output and compares it with a golden PNG.
///
/// Golden files are stored under `goldens/` by default. Run
/// `flutter test --update-goldens` to create or update them.
Future<ScreenshotResult> matchesGolden({
  required String name,
  flutter_test.Finder? finder,
  String? goldenDirectory,
  String? outputDirectory,
  double? pixelRatio,
  double padding = 0,
  bool settle = false,
  Duration settleTimeout = const Duration(seconds: 5),
}) async {
  final ScreenshotResult result = await screenshots(
    name: name,
    finder: finder,
    outputDirectory: outputDirectory,
    pixelRatio: pixelRatio,
    padding: padding,
    settle: settle,
    settleTimeout: settleTimeout,
    overwrite: true,
  );
  final File screenshotFile = File(result.path);
  final String goldenPath = resolveGoldenFilePath(
    context: currentCaptureContext,
    name: name,
    goldenDirectory: goldenDirectory,
  );

  final flutter_test.TestWidgetsFlutterBinding binding =
      flutter_test.TestWidgetsFlutterBinding.ensureInitialized();
  await binding.runAsync<void>(() async {
    await flutter_test.expectLater(
      screenshotFile.readAsBytesSync(),
      flutter_test.matchesGoldenFile(Uri.file(goldenPath)),
    );
  });
  final Object? asyncException = binding.takeException();
  if (asyncException != null) {
    Error.throwWithStackTrace(asyncException, StackTrace.current);
  }

  return result;
}
