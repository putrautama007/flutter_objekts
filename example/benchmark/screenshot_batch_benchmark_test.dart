import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:device_frame/device_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:objekts/objekts.dart' as objekts;
import 'package:objekts_example/main.dart';

const int _sampleCount = 5;
final List<Duration> _sequentialSamples = <Duration>[];
final List<Duration> _batchSamples = <Duration>[];

void main() {
  setUpAll(objekts.loadAppFonts);

  final List<objekts.ObjektsDeviceConfig> devices =
      <objekts.ObjektsDeviceConfig>[
    objekts.ObjektsDeviceConfig(
      device: Devices.ios.iPhone13,
      orientation: Orientation.portrait,
    ),
    objekts.ObjektsDeviceConfig(
      device: Devices.android.smallTablet,
      orientation: Orientation.landscape,
    ),
  ];
  final Directory outputDirectory = Directory(
    '${Directory.current.path}/build/objekts/benchmark',
  );

  objekts.testWidgetsForDevices(
    'benchmarks sequential and batched screenshots',
    (tester, config) async {
      await _runSequential(
        tester,
        config,
        outputDirectory.path,
        warmUp: true,
      );
      await _runBatch(
        tester,
        config,
        outputDirectory.path,
        warmUp: true,
      );
      final _BenchmarkRun sequentialVerification = await _runSequential(
        tester,
        config,
        outputDirectory.path,
      );
      final _BenchmarkRun batchVerification =
          await _runBatch(tester, config, outputDirectory.path);
      await _expectIdenticalPixels(
        tester,
        sequentialVerification.results,
        batchVerification.results,
      );

      for (int sample = 0; sample < _sampleCount; sample += 1) {
        if (sample.isEven) {
          final _BenchmarkRun sequential =
              await _runSequential(tester, config, outputDirectory.path);
          final _BenchmarkRun batch =
              await _runBatch(tester, config, outputDirectory.path);
          _sequentialSamples.add(sequential.elapsed);
          _batchSamples.add(batch.elapsed);
        } else {
          final _BenchmarkRun batch =
              await _runBatch(tester, config, outputDirectory.path);
          final _BenchmarkRun sequential =
              await _runSequential(tester, config, outputDirectory.path);
          _batchSamples.add(batch.elapsed);
          _sequentialSamples.add(sequential.elapsed);
        }
      }
    },
    devices: devices,
    outputDirectory: outputDirectory.path,
  );

  test('batched screenshots reduce median capture time by at least 30%', () {
    expect(_sequentialSamples, isNotEmpty);
    expect(_batchSamples, isNotEmpty);
    final Duration sequentialMedian = _median(_sequentialSamples);
    final Duration batchMedian = _median(_batchSamples);
    final double improvement =
        1 - (batchMedian.inMicroseconds / sequentialMedian.inMicroseconds);

    debugPrint('Sequential median: ${sequentialMedian.inMilliseconds} ms');
    debugPrint('Batch median: ${batchMedian.inMilliseconds} ms');
    debugPrint('Improvement: ${(improvement * 100).toStringAsFixed(1)}%');
    expect(
        batchMedian.inMicroseconds,
        lessThanOrEqualTo(
          (sequentialMedian.inMicroseconds * 0.70).round(),
        ));
  });
}

Future<_BenchmarkRun> _runSequential(
  WidgetTester tester,
  objekts.ObjektsDeviceConfig config,
  String outputDirectory, {
  bool warmUp = false,
}) async {
  await _pumpApp(tester, config);
  final Stopwatch stopwatch = Stopwatch()..start();
  final List<objekts.ScreenshotResult> results = <objekts.ScreenshotResult>[
    await objekts.screenshots(
      name: warmUp ? 'sequential-warm-home' : 'sequential-home',
      overwrite: true,
      outputDirectory: outputDirectory,
    ),
  ];
  results.addAll(await _navigateAndCapture(
    tester,
    (name) => objekts.screenshots(
      name: warmUp ? 'sequential-warm-$name' : 'sequential-$name',
      overwrite: true,
      outputDirectory: outputDirectory,
    ),
  ));
  stopwatch.stop();
  return _BenchmarkRun(elapsed: stopwatch.elapsed, results: results);
}

Future<_BenchmarkRun> _runBatch(
  WidgetTester tester,
  objekts.ObjektsDeviceConfig config,
  String outputDirectory, {
  bool warmUp = false,
}) async {
  await _pumpApp(tester, config);
  final Stopwatch stopwatch = Stopwatch()..start();
  final List<objekts.ScreenshotResult> results =
      await objekts.runScreenshotBatch(
    (batch) async {
      await batch.capture(
        name: warmUp ? 'batch-warm-home' : 'batch-home',
        overwrite: true,
      );
      await _navigateAndCapture(
        tester,
        (name) => batch.capture(
          name: warmUp ? 'batch-warm-$name' : 'batch-$name',
          overwrite: true,
        ),
      );
    },
    outputDirectory: outputDirectory,
  );
  stopwatch.stop();
  return _BenchmarkRun(elapsed: stopwatch.elapsed, results: results);
}

Future<void> _pumpApp(
  WidgetTester tester,
  objekts.ObjektsDeviceConfig config,
) async {
  await tester.pumpWidget(
    objekts.deviceFrame(
      config: config,
      child: ExampleApp(key: UniqueKey()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<List<T>> _navigateAndCapture<T>(
  WidgetTester tester,
  Future<T> Function(String name) capture,
) async {
  final List<T> results = <T>[];
  await tester.tap(find.byKey(const Key('activity-tab')));
  await tester.pumpAndSettle();
  results.add(await capture('activity'));
  await tester.tap(find.byKey(const Key('settings-tab')));
  await tester.pumpAndSettle();
  results.add(await capture('settings'));
  await tester.tap(find.byKey(const Key('overview-tab')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('increment-button')));
  await tester.pumpAndSettle();
  results.add(await capture('incremented'));
  return results;
}

Future<void> _expectIdenticalPixels(
  WidgetTester tester,
  List<objekts.ScreenshotResult> sequential,
  List<objekts.ScreenshotResult> batched,
) async {
  expect(batched, hasLength(sequential.length));
  for (int index = 0; index < sequential.length; index += 1) {
    final Uint8List actual = await _decodePixels(tester, batched[index].path);
    final Uint8List expected =
        await _decodePixels(tester, sequential[index].path);
    final int mismatch = _firstMismatch(expected, actual);
    if (mismatch != -1) {
      final int pixelOffset = (mismatch ~/ 4) * 4;
      final int width = sequential[index].pixelSize.width.toInt();
      final int pixelIndex = pixelOffset ~/ 4;
      fail(
        'Decoded pixels differ for capture $index at '
        '(${pixelIndex % width}, ${pixelIndex ~/ width}): '
        'sequential=${expected.sublist(pixelOffset, pixelOffset + 4)}, '
        'batch=${actual.sublist(pixelOffset, pixelOffset + 4)}.',
      );
    }
  }
}

int _firstMismatch(Uint8List expected, Uint8List actual) {
  if (expected.length != actual.length) {
    return 0;
  }
  for (int index = 0; index < expected.length; index += 1) {
    if (expected[index] != actual[index]) {
      return index;
    }
  }
  return -1;
}

Future<Uint8List> _decodePixels(WidgetTester tester, String path) async {
  final Uint8List? pixels = await tester.runAsync<Uint8List>(() async {
    final ui.Codec codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
    );
    try {
      final ui.FrameInfo frame = await codec.getNextFrame();
      try {
        final ByteData data = (await frame.image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        ))!;
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  });
  return pixels!;
}

Duration _median(List<Duration> values) {
  final List<int> sorted =
      values.map((duration) => duration.inMicroseconds).toList()..sort();
  final int middle = sorted.length ~/ 2;
  final int microseconds = sorted.length.isOdd
      ? sorted[middle]
      : ((sorted[middle - 1] + sorted[middle]) / 2).round();
  return Duration(microseconds: math.max(1, microseconds));
}

class _BenchmarkRun {
  const _BenchmarkRun({required this.elapsed, required this.results});

  final Duration elapsed;
  final List<objekts.ScreenshotResult> results;
}
