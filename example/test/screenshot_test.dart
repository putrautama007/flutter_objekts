import 'package:device_frame/device_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:objekts/objekts.dart' as objekts;
import 'package:objekts_example/main.dart';

void main() {
  final phone = objekts.ObjektsDeviceConfig(
    device: Devices.ios.iPhone13,
    orientation: Orientation.portrait,
    isFrameVisible: true,
  );
  final tablet = objekts.ObjektsDeviceConfig(
    device: Devices.android.smallTablet,
    orientation: Orientation.landscape,
    isFrameVisible: true,
  );

  objekts.testWidgetsForDevices(
    'captures the example app on multiple devices',
    devices: [phone, tablet],
    (tester, config) async {
      await tester.pumpWidget(
        objekts.deviceFrame(
          config: config,
          child: const ExampleApp(),
        ),
      );

      final results = await objekts.runScreenshotBatch(
        (batch) async {
          await batch.capture(name: 'home', overwrite: true);

          await tester.tap(find.byKey(const Key('activity-tab')));
          await tester.pump();
          await batch.capture(name: 'activity', overwrite: true);
          expect(find.text('Home screenshot captured'), findsOneWidget);

          await tester.tap(find.byKey(const Key('settings-tab')));
          await tester.pump();
          await batch.capture(name: 'settings', overwrite: true);
          expect(find.text('Include device frame'), findsOneWidget);

          await tester.tap(find.byKey(const Key('overview-tab')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('increment-button')));
          await tester.pump();
          await batch.capture(name: 'incremented', overwrite: true);
          expect(find.text('Counter: 1'), findsOneWidget);
        },
      );

      final home = results.first;
      expect(home.logicalSize, config.surfaceSize);
      expect(
        home.pixelSize,
        config.surfaceSize * config.device.pixelRatio,
      );
      final activity = results[1];
      expect(activity.logicalSize, config.surfaceSize);
      final settings = results[2];
      expect(settings.logicalSize, config.surfaceSize);
      expect(results[3].logicalSize, config.surfaceSize);
    },
    captureOnFailure: true,
  );
}
