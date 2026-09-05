import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:device_frame/device_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:objekts/objekts.dart' as objekts;
import 'package:path/path.dart' as p;

void main() {
  final Directory outputDirectory =
      Directory.systemTemp.createTempSync('objekts-test-');
  tearDownAll(() {
    if (outputDirectory.existsSync()) {
      outputDirectory.deleteSync(recursive: true);
    }
  });

  objekts.testWidgets(
    'captures the full surface and returns PNG metadata',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                ColoredBox(color: Colors.blue),
                Center(child: Text('Visible screenshot text')),
              ],
            ),
          ),
        ),
      );

      final objekts.ScreenshotResult result = await objekts.screenshots(
        name: 'surface',
        outputDirectory: outputDirectory.path,
      );

      expect(result.target, objekts.ObjektsScreenshotTarget.surface);
      expect(result.logicalSize, const Size(800, 600));
      expect(result.pixelSize, const Size(800, 600));
      expect(result.pixelRatio, 1);
      expect(File(result.path).readAsBytesSync().take(8).toList(), <int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'a screenshot batch writes ordered rendered states',
    (tester) async {
      await tester.pumpWidget(
        const ColoredBox(color: Colors.red),
      );

      final List<objekts.ScreenshotResult> results =
          await objekts.runScreenshotBatch(
        (objekts.ScreenshotBatch batch) async {
          await batch.capture(name: 'first');
          await tester.pumpWidget(
            const ColoredBox(color: Colors.blue),
          );
          await batch.capture(name: 'second');
        },
        outputDirectory: outputDirectory.path,
      );

      expect(results, hasLength(2));
      expect(results.map((result) => p.basename(result.path)), <String>[
        'first.png',
        'second.png',
      ]);
      for (final objekts.ScreenshotResult result in results) {
        expect(File(result.path).readAsBytesSync().take(8).toList(), <int>[
          0x89,
          0x50,
          0x4e,
          0x47,
          0x0d,
          0x0a,
          0x1a,
          0x0a,
        ]);
      }
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'a screenshot batch preserves pixels and ratio overrides',
    (tester) async {
      await tester.pumpWidget(
        const Center(
          child: SizedBox(
            key: Key('translucent-target'),
            width: 4,
            height: 3,
            child: ColoredBox(color: Color.fromARGB(128, 10, 20, 30)),
          ),
        ),
      );

      final objekts.ScreenshotResult sequential = await objekts.screenshots(
        name: 'sequential-pixels',
        finder: find.byKey(const Key('translucent-target')),
        pixelRatio: 2,
        outputDirectory: outputDirectory.path,
      );
      final List<objekts.ScreenshotResult> batched =
          await objekts.runScreenshotBatch(
        (objekts.ScreenshotBatch batch) async {
          await batch.capture(
            name: 'batched-pixels',
            finder: find.byKey(const Key('translucent-target')),
          );
          await batch.capture(
            name: 'capture-ratio-override',
            finder: find.byKey(const Key('translucent-target')),
            pixelRatio: 1,
          );
        },
        outputDirectory: outputDirectory.path,
        pixelRatio: 2,
      );

      expect(batched.first.pixelSize, const Size(8, 6));
      expect(batched.last.pixelSize, const Size(4, 3));
      expect(
        await _decodePngPixels(tester, batched.first.path),
        await _decodePngPixels(tester, sequential.path),
      );
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'a screenshot batch supports screenshots and goldens together',
    (tester) async {
      final _RecordingGoldenComparator comparator =
          _installRecordingGoldenComparator();
      final Directory goldenDirectory = Directory(
        p.join(outputDirectory.path, 'batch-goldens'),
      );
      await tester.pumpWidget(
        const ColoredBox(color: Colors.indigo),
      );

      final List<objekts.ScreenshotResult> results =
          await objekts.runScreenshotBatch(
        (objekts.ScreenshotBatch batch) async {
          await batch.capture(name: 'artifact');
          await batch.matchGolden(
            name: 'golden',
            goldenDirectory: goldenDirectory.path,
          );
        },
        outputDirectory: outputDirectory.path,
      );

      expect(
        results.map((result) => p.basename(result.path)),
        <String>['artifact.png', 'golden.png'],
      );
      expect(
        comparator.comparedGolden,
        Uri.file(
          p.join(
            goldenDirectory.path,
            'test',
            'a_screenshot_batch_supports_screenshots_and_goldens_together',
            'golden.png',
          ),
        ),
      );
      expect(comparator.comparedBytes, isNotEmpty);
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'a screenshot batch propagates golden mismatches',
    (tester) async {
      _installRecordingGoldenComparator(matches: false);
      await tester.pumpWidget(const ColoredBox(color: Colors.deepOrange));

      await expectLater(
        objekts.runScreenshotBatch(
          (batch) async {
            await batch.matchGolden(
              name: 'mismatch',
              goldenDirectory: outputDirectory.path,
            );
          },
          outputDirectory: outputDirectory.path,
        ),
        throwsA(anything),
      );
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'a screenshot batch rejects invalid pending limits',
    (tester) async {
      await expectLater(
        objekts.runScreenshotBatch(
          (batch) async {},
          maxPendingCaptures: 0,
        ),
        throwsArgumentError,
      );
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'a screenshot batch rejects nesting',
    (tester) async {
      await expectLater(
        objekts.runScreenshotBatch((outer) async {
          await objekts.runScreenshotBatch((inner) async {});
        }),
        throwsStateError,
      );
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'a screenshot batch rejects captures after closing',
    (tester) async {
      late objekts.ScreenshotBatch closedBatch;
      await objekts.runScreenshotBatch((batch) async {
        closedBatch = batch;
      });

      await expectLater(
        closedBatch.capture(name: 'late'),
        throwsStateError,
      );
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'a screenshot batch reserves duplicate names before writes finish',
    (tester) async {
      await tester.pumpWidget(const ColoredBox(color: Colors.teal));

      await expectLater(
        objekts.runScreenshotBatch(
          (batch) async {
            await batch.capture(name: 'duplicate');
            await batch.capture(name: 'duplicate');
          },
          outputDirectory: outputDirectory.path,
        ),
        throwsA(isA<objekts.ObjektsCaptureException>()),
      );
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'a screenshot batch applies backpressure with one pending capture',
    (tester) async {
      await tester.pumpWidget(const ColoredBox(color: Colors.lime));

      final List<objekts.ScreenshotResult> results =
          await objekts.runScreenshotBatch(
        (batch) async {
          await batch.capture(name: 'one');
          await batch.capture(name: 'two');
          await batch.capture(name: 'three');
        },
        maxPendingCaptures: 1,
        outputDirectory: outputDirectory.path,
      );

      expect(
        results.map((result) => p.basename(result.path)),
        <String>['one.png', 'two.png', 'three.png'],
      );
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'a screenshot batch makes the last overwrite deterministic',
    (tester) async {
      await tester.pumpWidget(const ColoredBox(color: Colors.red));

      final List<objekts.ScreenshotResult> results =
          await objekts.runScreenshotBatch(
        (batch) async {
          await batch.capture(name: 'overwritten', overwrite: true);
          await tester.pumpWidget(const ColoredBox(color: Colors.blue));
          await batch.capture(name: 'overwritten', overwrite: true);
        },
        outputDirectory: outputDirectory.path,
      );
      final objekts.ScreenshotResult expected = await objekts.screenshots(
        name: 'expected-overwrite',
        outputDirectory: outputDirectory.path,
      );

      expect(results.first.path, results.last.path);
      expect(
        await _decodePngPixels(tester, results.last.path),
        await _decodePngPixels(tester, expected.path),
      );
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'a failed screenshot batch drains captures and preserves the body error',
    (tester) async {
      await tester.pumpWidget(const ColoredBox(color: Colors.amber));

      await expectLater(
        objekts.runScreenshotBatch(
          (batch) async {
            await batch.capture(name: 'before-failure');
            throw StateError('body failed');
          },
          outputDirectory: outputDirectory.path,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'body failed',
          ),
        ),
      );
      expect(
        File(
          p.join(
            outputDirectory.path,
            'test',
            'a_failed_screenshot_batch_drains_captures_and_preserves_the_body_error',
            'before-failure.png',
          ),
        ).existsSync(),
        isTrue,
      );
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'a screenshot batch reports output failures',
    (tester) async {
      await tester.pumpWidget(const ColoredBox(color: Colors.cyan));
      final File invalidDirectory = File(
        p.join(outputDirectory.path, 'not-a-directory'),
      )..writeAsStringSync('file');

      await expectLater(
        objekts.runScreenshotBatch(
          (batch) async {
            await batch.capture(name: 'cannot-write');
          },
          outputDirectory: invalidDirectory.path,
        ),
        throwsA(isA<objekts.ObjektsCaptureException>()),
      );
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'captures one Finder match with padding',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                key: Key('target'),
                width: 40,
                height: 30,
                child: ColoredBox(color: Colors.red),
              ),
            ),
          ),
        ),
      );

      final objekts.ScreenshotResult result = await objekts.screenshots(
        name: 'target.png',
        finder: find.byKey(const Key('target')),
        padding: 5,
        outputDirectory: outputDirectory.path,
      );

      expect(result.target, objekts.ObjektsScreenshotTarget.finder);
      expect(result.logicalSize, const Size(50, 40));
      expect(p.basename(result.path), 'target.png');
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'requires exactly one Finder match',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Text('duplicate')),
      );

      await expectLater(
        objekts.screenshots(
          finder: find.text('missing'),
          outputDirectory: outputDirectory.path,
        ),
        throwsA(isA<objekts.ObjektsCaptureException>()),
      );
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'sanitizes names and rejects explicit duplicates',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Text('content')));

      final objekts.ScreenshotResult result = await objekts.screenshots(
        name: '../unsafe/name.png',
        outputDirectory: outputDirectory.path,
      );
      expect(p.basename(result.path), 'unsafe_name.png');

      await expectLater(
        objekts.screenshots(
          name: '../unsafe/name.png',
          outputDirectory: outputDirectory.path,
        ),
        throwsA(isA<objekts.ObjektsCaptureException>()),
      );
    },
    outputDirectory: outputDirectory.path,
  );

  test('rejects an empty device list', () {
    expect(
      () => objekts.testWidgetsForDevices(
        'invalid',
        (tester, config) async {},
        devices: const <objekts.ObjektsDeviceConfig>[],
      ),
      throwsArgumentError,
    );
  });

  final ValueVariant<String> visualVariants = ValueVariant<String>(
    <String>{'light mode', 'light/mode'},
  );
  final List<String> variantArtifactPaths = <String>[];
  final objekts.ObjektsDeviceConfig variantDevice = objekts.ObjektsDeviceConfig(
    device: DeviceInfo.genericPhone(
      platform: TargetPlatform.android,
      id: 'variant-phone',
      name: 'Variant phone',
      screenSize: const Size(80, 120),
      pixelRatio: 1,
    ),
  );

  objekts.testWidgetsForDevices(
    'captures device and visual variants without collisions',
    (tester, config) async {
      await tester.pumpWidget(
        objekts.deviceFrame(
          config: config,
          child: ColoredBox(
            color: visualVariants.currentValue == 'light mode'
                ? Colors.white
                : Colors.black,
          ),
        ),
      );
      final List<objekts.ScreenshotResult> results =
          await objekts.runScreenshotBatch(
        (objekts.ScreenshotBatch batch) async {
          await batch.capture(name: 'state');
        },
        outputDirectory: outputDirectory.path,
      );
      variantArtifactPaths.add(results.single.path);
    },
    devices: <objekts.ObjektsDeviceConfig>[variantDevice],
    variant: visualVariants,
    outputDirectory: outputDirectory.path,
  );

  test('uses device and variant labels in artifact paths', () {
    expect(
      variantArtifactPaths
          .map((path) => p.relative(path, from: outputDirectory.path))
          .toList(),
      <String>[
        p.join(
          'test',
          'captures_device_and_visual_variants_without_collisions',
          'Variant-phone-portrait',
          'light_mode',
          'state.png',
        ),
        p.join(
          'test',
          'captures_device_and_visual_variants_without_collisions',
          'Variant-phone-portrait',
          'light_mode-2',
          'state.png',
        ),
      ],
    );
  });

  final List<objekts.ObjektsDeviceConfig> devices =
      <objekts.ObjektsDeviceConfig>[
    objekts.ObjektsDeviceConfig(
      device: DeviceInfo.genericPhone(
        platform: TargetPlatform.android,
        id: 'small',
        name: 'Small phone',
        screenSize: const Size(100, 200),
        pixelRatio: 2,
      ),
    ),
    objekts.ObjektsDeviceConfig(
      device: DeviceInfo.genericPhone(
        platform: TargetPlatform.android,
        id: 'large',
        name: 'Large phone',
        screenSize: const Size(200, 400),
        pixelRatio: 3,
      ),
      orientation: Orientation.landscape,
      isFrameVisible: false,
    ),
  ];
  final List<String> executionOrder = <String>[];

  objekts.testWidgetsForDevices(
    'runs device configurations in list order',
    (tester, config) async {
      final int expectedIndex = devices.indexOf(config);
      expect(executionOrder, hasLength(expectedIndex));
      executionOrder.add(config.deviceName);
      await tester.pumpWidget(
        objekts.deviceFrame(
          config: config,
          child: const MaterialApp(
            home: Scaffold(body: ColoredBox(color: Colors.green)),
          ),
        ),
      );
      final objekts.ScreenshotResult result = await objekts.screenshots(
        name: 'device',
        outputDirectory: outputDirectory.path,
      );
      expect(result.deviceIdentifier, config.deviceIdentifier);
      expect(result.orientation, config.orientation);
      expect(result.logicalSize, config.surfaceSize);
      expect(result.pixelSize, config.surfaceSize * config.device.pixelRatio);
    },
    devices: devices,
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'matches a deterministic golden file',
    (tester) async {
      await tester.pumpWidget(
        const ColoredBox(color: Colors.blue),
      );

      final objekts.ScreenshotResult result = await objekts.matchesGolden(
        name: 'surface',
        outputDirectory: outputDirectory.path,
      );
      final List<objekts.ScreenshotResult> batched =
          await objekts.runScreenshotBatch(
        (batch) async {
          await batch.matchGolden(name: 'surface');
        },
        outputDirectory: outputDirectory.path,
      );

      expect(result.target, objekts.ObjektsScreenshotTarget.surface);
      expect(result.logicalSize, const Size(800, 600));
      expect(result.pixelSize, const Size(800, 600));
      expect(batched.single.logicalSize, result.logicalSize);
      expect(batched.single.pixelSize, result.pixelSize);
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'matches a Finder target in a custom golden directory',
    (tester) async {
      final _RecordingGoldenComparator comparator =
          _installRecordingGoldenComparator();
      final Directory goldenDirectory = Directory(
        p.join(outputDirectory.path, 'custom-goldens'),
      );

      await tester.pumpWidget(
        const Center(
          child: SizedBox(
            key: Key('golden-target'),
            width: 40,
            height: 30,
            child: ColoredBox(color: Colors.red),
          ),
        ),
      );

      final objekts.ScreenshotResult result = await objekts.matchesGolden(
        name: 'focused',
        finder: find.byKey(const Key('golden-target')),
        goldenDirectory: goldenDirectory.path,
        outputDirectory: outputDirectory.path,
      );

      expect(result.target, objekts.ObjektsScreenshotTarget.finder);
      expect(result.logicalSize, const Size(40, 30));
      expect(
          comparator.comparedGolden,
          Uri.file(p.join(
            goldenDirectory.path,
            'test',
            'matches_a_Finder_target_in_a_custom_golden_directory',
            'focused.png',
          )));
      expect(comparator.comparedBytes, isNotNull);
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'a screenshot batch updates golden baselines in update mode',
    (tester) async {
      final _RecordingGoldenComparator comparator =
          _installRecordingGoldenComparator();
      final bool previousUpdateMode = autoUpdateGoldenFiles;
      autoUpdateGoldenFiles = true;
      await tester.pumpWidget(const ColoredBox(color: Colors.pink));

      try {
        await objekts.runScreenshotBatch(
          (batch) async {
            await batch.matchGolden(
              name: 'updated',
              goldenDirectory: outputDirectory.path,
            );
          },
          outputDirectory: outputDirectory.path,
        );
      } finally {
        autoUpdateGoldenFiles = previousUpdateMode;
      }

      expect(comparator.updatedGolden, isNotNull);
      expect(comparator.updatedBytes, isNotEmpty);
    },
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgetsForDevices(
    'includes device context in a golden path',
    (tester, config) async {
      final _RecordingGoldenComparator comparator =
          _installRecordingGoldenComparator();
      final Directory goldenDirectory = Directory(
        p.join(outputDirectory.path, 'device-goldens'),
      );

      await tester.pumpWidget(
        objekts.deviceFrame(
          config: config,
          child: const ColoredBox(color: Colors.purple),
        ),
      );

      await objekts.matchesGolden(
        name: 'device',
        goldenDirectory: goldenDirectory.path,
        outputDirectory: outputDirectory.path,
      );

      expect(
          comparator.comparedGolden,
          Uri.file(p.join(
            goldenDirectory.path,
            'test',
            'includes_device_context_in_a_golden_path',
            'Golden-phone-portrait',
            'device.png',
          )));
    },
    devices: <objekts.ObjektsDeviceConfig>[
      objekts.ObjektsDeviceConfig(
        device: DeviceInfo.genericPhone(
          platform: TargetPlatform.android,
          id: 'golden-phone',
          name: 'Golden phone',
          screenSize: const Size(100, 200),
          pixelRatio: 1,
        ),
      ),
    ],
    outputDirectory: outputDirectory.path,
  );

  objekts.testWidgets(
    'propagates golden comparison failures',
    (tester) async {
      _installRecordingGoldenComparator(matches: false);
      await tester.pumpWidget(
        const ColoredBox(color: Colors.orange),
      );

      bool didThrow = false;
      try {
        await objekts.matchesGolden(
          name: 'mismatch',
          goldenDirectory: outputDirectory.path,
          outputDirectory: outputDirectory.path,
        );
      } catch (_) {
        didThrow = true;
      }
      expect(didThrow, isTrue);
    },
    outputDirectory: outputDirectory.path,
  );
}

_RecordingGoldenComparator _installRecordingGoldenComparator({
  bool matches = true,
}) {
  final _RecordingGoldenComparator comparator = _RecordingGoldenComparator(
    matches: matches,
  );
  final GoldenFileComparator previousComparator = goldenFileComparator;
  final bool previousUpdateMode = autoUpdateGoldenFiles;
  goldenFileComparator = comparator;
  addTearDown(() {
    expect(autoUpdateGoldenFiles, previousUpdateMode);
    goldenFileComparator = previousComparator;
  });
  return comparator;
}

class _RecordingGoldenComparator extends GoldenFileComparator {
  _RecordingGoldenComparator({required this.matches});

  final bool matches;
  Uri? comparedGolden;
  Uint8List? comparedBytes;
  Uri? updatedGolden;
  Uint8List? updatedBytes;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    comparedBytes = imageBytes;
    comparedGolden = golden;
    return matches;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    updatedGolden = golden;
    updatedBytes = imageBytes;
  }
}

Future<Uint8List> _decodePngPixels(
  WidgetTester tester,
  String path,
) async {
  final Uint8List? pixels = await tester.runAsync<Uint8List>(() async {
    final ui.Codec codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
    );
    try {
      final ui.FrameInfo frame = await codec.getNextFrame();
      try {
        final ByteData? byteData = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        return byteData!.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  });
  return pixels!;
}
