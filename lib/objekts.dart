export 'src/capture.dart' show screenshots;
export 'src/font_loader.dart' show loadAppFonts;
export 'src/golden.dart' show matchesGolden;
export 'src/models.dart';
export 'src/test_widgets.dart'
    show ObjektsDeviceWidgetTesterCallback, testWidgets, testWidgetsForDevices;

import 'package:device_frame/device_frame.dart';
import 'package:flutter/widgets.dart';

import 'src/context.dart';
import 'src/models.dart';

/// Wraps [child] in a `device_frame` device simulation.
Widget deviceFrame({
  required ObjektsDeviceConfig config,
  required Widget child,
  Key? key,
}) {
  final CaptureContext? context = currentCaptureContext;
  return Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      key: context?.surfaceBoundaryKey,
      child: DeviceFrame(
        key: key,
        device: config.device,
        isFrameVisible: config.isFrameVisible,
        orientation: config.orientation,
        screen: child,
      ),
    ),
  );
}
