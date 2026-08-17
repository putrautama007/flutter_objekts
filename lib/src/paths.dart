import 'dart:io';

import 'package:path/path.dart' as p;

import 'context.dart';
import 'models.dart';

String sanitizePathSegment(String value, {String fallback = 'capture'}) {
  final String sanitized = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^[._]+|[._]+$'), '');
  if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
    return fallback;
  }
  return sanitized;
}

String _fileStem(String name) {
  final String trimmed = name.trim();
  final String withoutExtension = trimmed.toLowerCase().endsWith('.png')
      ? trimmed.substring(0, trimmed.length - 4)
      : trimmed;
  return sanitizePathSegment(withoutExtension);
}

String _orientationName(ObjektsDeviceConfig config) {
  return config.orientation.name;
}

String _rootDirectory(CaptureContext? context, String? outputDirectory) {
  final String? configured = outputDirectory ?? context?.outputDirectory;
  if (configured != null && p.isAbsolute(configured)) {
    return p.normalize(configured);
  }
  if (configured != null) {
    return p.normalize(p.join(Directory.current.path, configured));
  }
  return p.join(Directory.current.path, 'build', 'objekts', 'screenshots');
}

Directory artifactDirectory({
  required CaptureContext? context,
  required String? outputDirectory,
}) {
  final List<String> segments = <String>[
    _rootDirectory(context, outputDirectory),
    'test',
    sanitizePathSegment(context?.description ?? 'unscoped-test'),
  ];
  final ObjektsDeviceConfig? device = context?.deviceConfig;
  if (device != null) {
    final String label = context?.deviceLabel ??
        '${device.deviceName}-${_orientationName(device)}';
    segments.add(sanitizePathSegment(label));
  }
  return Directory(p.joinAll(segments));
}

File nextArtifactFile({
  required Directory directory,
  required String? name,
  required CaptureContext? context,
  required bool overwrite,
  required bool allowAutomaticCollision,
}) {
  final bool isExplicit = name != null;
  final String stem = name == null
      ? 'capture-${(context?.generatedCaptureCount ?? 0) + 1}'
      : _fileStem(name);
  if (name == null && context != null) {
    context.generatedCaptureCount += 1;
  }

  File candidate = File(p.join(directory.path, '$stem.png'));
  if (overwrite || !candidate.existsSync()) {
    return candidate;
  }
  if (isExplicit && !allowAutomaticCollision) {
    throw ObjektsCaptureException(
      'The screenshot already exists: ${candidate.path}. '
      'Use overwrite: true to replace it.',
    );
  }

  int suffix = 2;
  while (candidate.existsSync()) {
    candidate = File(p.join(directory.path, '$stem-$suffix.png'));
    suffix += 1;
  }
  return candidate;
}
