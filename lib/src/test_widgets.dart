import 'dart:async';

import 'package:flutter_test/flutter_test.dart' as flutter_test;
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart'
    as leak_testing;

import 'capture.dart';
import 'context.dart';
import 'models.dart';

/// A callback used by [testWidgetsForDevices].
typedef ObjektsDeviceWidgetTesterCallback = Future<void> Function(
  flutter_test.WidgetTester tester,
  ObjektsDeviceConfig config,
);

/// A Flutter-compatible widget-test wrapper with optional screenshot capture.
void testWidgets(
  String description,
  flutter_test.WidgetTesterCallback callback, {
  bool? skip,
  flutter_test.Timeout? timeout,
  bool semanticsEnabled = true,
  flutter_test.TestVariant<Object?> variant =
      const flutter_test.DefaultTestVariant(),
  dynamic tags,
  int? retry,
  leak_testing.LeakTesting? experimentalLeakTesting,
  ObjektsDeviceConfig? deviceConfig,
  bool captureOnFailure = false,
  String? outputDirectory,
}) {
  _registerTest(
    description: description,
    artifactDescription: description,
    callback: (tester, _) => callback(tester),
    skip: skip,
    timeout: timeout,
    semanticsEnabled: semanticsEnabled,
    variant: variant,
    tags: tags,
    retry: retry,
    experimentalLeakTesting: experimentalLeakTesting,
    deviceConfig: deviceConfig,
    captureOnFailure: captureOnFailure,
    outputDirectory: outputDirectory,
  );
}

/// Registers one isolated Flutter widget test for every device configuration.
void testWidgetsForDevices(
  String description,
  ObjektsDeviceWidgetTesterCallback callback, {
  required List<ObjektsDeviceConfig> devices,
  bool? skip,
  flutter_test.Timeout? timeout,
  bool semanticsEnabled = true,
  flutter_test.TestVariant<Object?> variant =
      const flutter_test.DefaultTestVariant(),
  dynamic tags,
  int? retry,
  leak_testing.LeakTesting? experimentalLeakTesting,
  bool captureOnFailure = false,
  String? outputDirectory,
}) {
  if (devices.isEmpty) {
    throw ArgumentError.value(
        devices, 'devices', 'At least one device configuration is required.');
  }

  final Map<String, int> seenLabels = <String, int>{};
  for (final ObjektsDeviceConfig config in devices) {
    final String baseLabel = _deviceLabel(config);
    final int occurrence = (seenLabels[baseLabel] ?? 0) + 1;
    seenLabels[baseLabel] = occurrence;
    final String label = occurrence == 1 ? baseLabel : '$baseLabel-$occurrence';

    _registerTest(
      description: '$description (device: $label)',
      artifactDescription: description,
      callback: (tester, _) => callback(tester, config),
      skip: skip,
      timeout: timeout,
      semanticsEnabled: semanticsEnabled,
      variant: variant,
      tags: tags,
      retry: retry,
      experimentalLeakTesting: experimentalLeakTesting,
      deviceConfig: config,
      deviceLabel: label,
      captureOnFailure: captureOnFailure,
      outputDirectory: outputDirectory,
    );
  }
}

String _deviceLabel(ObjektsDeviceConfig config) {
  final String device =
      config.deviceName.trim().isEmpty ? 'device' : config.deviceName;
  return '${device.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')}-${config.orientation.name}';
}

void _registerTest({
  required String description,
  required String artifactDescription,
  required Future<void> Function(
          flutter_test.WidgetTester tester, ObjektsDeviceConfig? config)
      callback,
  required bool? skip,
  required flutter_test.Timeout? timeout,
  required bool semanticsEnabled,
  required flutter_test.TestVariant<Object?> variant,
  required dynamic tags,
  required int? retry,
  required leak_testing.LeakTesting? experimentalLeakTesting,
  required ObjektsDeviceConfig? deviceConfig,
  String? deviceLabel,
  required bool captureOnFailure,
  required String? outputDirectory,
}) {
  flutter_test.testWidgets(
    description,
    (tester) async {
      final flutter_test.TestWidgetsFlutterBinding binding =
          flutter_test.TestWidgetsFlutterBinding.ensureInitialized();
      final CaptureContext context = CaptureContext(
        description: artifactDescription,
        deviceConfig: deviceConfig,
        deviceLabel: deviceLabel,
        outputDirectory: outputDirectory,
      );

      await runWithCaptureContext<void>(context, () async {
        try {
          if (deviceConfig != null) {
            await binding.setSurfaceSize(deviceConfig.surfaceSize);
          }
          await callback(tester, deviceConfig);
        } catch (error, stackTrace) {
          if (captureOnFailure) {
            try {
              await captureFailureScreenshot(outputDirectory: outputDirectory);
            } on Object catch (captureError, captureStackTrace) {
              print(
                'Objekts could not capture failure screenshot for "$description": '
                '$captureError\n$captureStackTrace',
              );
            }
          }
          Error.throwWithStackTrace(error, stackTrace);
        } finally {
          if (deviceConfig != null) {
            await binding.setSurfaceSize(null);
          }
        }
      });
    },
    skip: skip,
    timeout: timeout,
    semanticsEnabled: semanticsEnabled,
    variant: variant,
    tags: tags,
    retry: retry,
    experimentalLeakTesting: experimentalLeakTesting,
  );
}
