import 'dart:async';

import 'package:flutter/widgets.dart' as widgets;

import 'models.dart';

final Object _captureContextKey = Object();

class CaptureContext {
  CaptureContext({
    required this.description,
    this.deviceConfig,
    this.deviceLabel,
    this.outputDirectory,
  });

  final String description;
  final ObjektsDeviceConfig? deviceConfig;
  final String? deviceLabel;
  final String? outputDirectory;
  final widgets.GlobalKey surfaceBoundaryKey = widgets.GlobalKey();
  int generatedCaptureCount = 0;
}

CaptureContext? get currentCaptureContext {
  return Zone.current[_captureContextKey] as CaptureContext?;
}

Future<T> runWithCaptureContext<T>(
    CaptureContext context, Future<T> Function() body) {
  return runZoned<Future<T>>(body, zoneValues: <Object?, Object?>{
    _captureContextKey: context,
  });
}
