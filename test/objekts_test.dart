import 'dart:io';

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
}
