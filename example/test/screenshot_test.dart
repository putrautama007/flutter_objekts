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

      final home = await objekts.screenshots(
        name: 'home',
        overwrite: true,
      );
      expect(home.logicalSize, config.surfaceSize);
      expect(
        home.pixelSize,
        config.surfaceSize * config.device.pixelRatio,
      );

      await tester.tap(find.byKey(const Key('activity-tab')));
      await tester.pump();
      final activity = await objekts.screenshots(
        name: 'activity',
        overwrite: true,
      );
      expect(activity.logicalSize, config.surfaceSize);
      expect(find.text('Home screenshot captured'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings-tab')));
      await tester.pump();
      final settings = await objekts.screenshots(
        name: 'settings',
        overwrite: true,
      );
      expect(settings.logicalSize, config.surfaceSize);
      expect(find.text('Include device frame'), findsOneWidget);

      await tester.tap(find.byKey(const Key('overview-tab')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('increment-button')));
      await tester.pump();
      await objekts.screenshots(name: 'incremented', overwrite: true);

      expect(find.text('Counter: 1'), findsOneWidget);
    },
    captureOnFailure: true,
  );
}
