import 'dart:io';
import 'dart:typed_data';

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

      expect(result.target, objekts.ObjektsScreenshotTarget.surface);
      expect(result.logicalSize, const Size(800, 600));
      expect(result.pixelSize, const Size(800, 600));
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

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    comparedBytes = imageBytes;
    comparedGolden = golden;
    return matches;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {}
}
