import 'dart:ui' as ui;

import 'package:device_frame/device_frame.dart';
import 'package:flutter/widgets.dart' as widgets;

/// The source area used for a screenshot.
enum ObjektsScreenshotTarget {
  /// The entire active Flutter test surface.
  surface,

  /// The paint bounds of one widget selected by a Finder.
  finder,
}

/// A device and orientation used to configure a widget test.
class ObjektsDeviceConfig {
  /// Creates a device configuration.
  const ObjektsDeviceConfig({
    required this.device,
    this.orientation = widgets.Orientation.portrait,
    this.isFrameVisible = true,
  });

  /// The device specification supplied by `device_frame`.
  final DeviceInfo device;

  /// The orientation simulated by the device frame.
  final widgets.Orientation orientation;

  /// Whether the physical device bezel is rendered.
  final bool isFrameVisible;

  /// A stable identifier suitable for metadata and diagnostics.
  String get deviceIdentifier => device.identifier.toString();

  /// The display name supplied by `device_frame`.
  String get deviceName => device.name;

  /// The logical size required by the test surface for this configuration.
  ui.Size get surfaceSize {
    final ui.Size baseSize =
        isFrameVisible ? device.frameSize : device.screenSize;
    final bool wantsLandscape = orientation == widgets.Orientation.landscape;
    final bool isLandscape = baseSize.width > baseSize.height;
    if (wantsLandscape == isLandscape) {
      return baseSize;
    }
    return ui.Size(baseSize.height, baseSize.width);
  }

  @override
  bool operator ==(Object other) {
    return other is ObjektsDeviceConfig &&
        other.deviceIdentifier == deviceIdentifier &&
        other.orientation == orientation &&
        other.isFrameVisible == isFrameVisible;
  }

  @override
  int get hashCode =>
      Object.hash(deviceIdentifier, orientation, isFrameVisible);
}

/// Metadata returned after a PNG screenshot has been written.
class ScreenshotResult {
  /// Creates screenshot metadata.
  const ScreenshotResult({
    required this.path,
    required this.target,
    required this.logicalSize,
    required this.pixelSize,
    required this.pixelRatio,
    this.deviceIdentifier,
    this.orientation,
  });

  /// Absolute path to the generated PNG file.
  final String path;

  /// The capture source.
  final ObjektsScreenshotTarget target;

  /// The captured bounds in logical Flutter units.
  final ui.Size logicalSize;

  /// The encoded PNG dimensions in physical pixels.
  final ui.Size pixelSize;

  /// The pixel ratio used for image encoding.
  final double pixelRatio;

  /// The active device identifier, if a device configuration was used.
  final String? deviceIdentifier;

  /// The active orientation, if a device configuration was used.
  final widgets.Orientation? orientation;

  @override
  String toString() {
    return 'ScreenshotResult(path: $path, target: $target, '
        'logicalSize: $logicalSize, pixelSize: $pixelSize, '
        'pixelRatio: $pixelRatio)';
  }
}

/// An error raised when an explicit screenshot cannot be produced.
class ObjektsCaptureException implements Exception {
  /// Creates a capture error with an actionable message.
  ObjektsCaptureException(this.message, {this.cause, this.stackTrace});

  /// A human-readable description of the failure.
  final String message;

  /// The original error, when one exists.
  final Object? cause;

  /// The original stack trace, when one exists.
  final StackTrace? stackTrace;

  @override
  String toString() {
    if (cause == null) {
      return 'ObjektsCaptureException: $message';
    }
    return 'ObjektsCaptureException: $message ($cause)';
  }
}
