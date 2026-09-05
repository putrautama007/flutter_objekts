import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_test/flutter_test.dart' as flutter_test;

import 'context.dart';
import 'models.dart';
import 'paths.dart';

/// An immutable rendered frame awaiting encoding and persistence.
///
/// This type is package-internal and is intentionally not exported by
/// `package:objekts/objekts.dart`.
class CapturedFrame {
  CapturedFrame({required this.image, required this.result});

  final ui.Image image;
  final ScreenshotResult result;
}

/// Captures the current Flutter test surface or one Finder-selected widget.
Future<ScreenshotResult> screenshots({
  String? name,
  flutter_test.Finder? finder,
  String? outputDirectory,
  double? pixelRatio,
  double padding = 0,
  bool overwrite = false,
  bool settle = false,
  Duration settleTimeout = const Duration(seconds: 5),
}) async {
  return captureScreenshot(
    name: name,
    finder: finder,
    outputDirectory: outputDirectory,
    pixelRatio: pixelRatio,
    padding: padding,
    overwrite: overwrite,
    settle: settle,
    settleTimeout: settleTimeout,
    allowAutomaticCollision: false,
  );
}

Future<ScreenshotResult> captureFailureScreenshot({
  String? outputDirectory,
}) {
  return captureScreenshot(
    name: 'failure',
    outputDirectory: outputDirectory,
    allowAutomaticCollision: true,
  );
}

Future<ScreenshotResult> captureScreenshot({
  String? name,
  flutter_test.Finder? finder,
  String? outputDirectory,
  double? pixelRatio,
  double padding = 0,
  bool overwrite = false,
  bool settle = false,
  Duration settleTimeout = const Duration(seconds: 5),
  required bool allowAutomaticCollision,
}) async {
  final CapturedFrame frame = await captureFrame(
    name: name,
    finder: finder,
    outputDirectory: outputDirectory,
    pixelRatio: pixelRatio,
    padding: padding,
    overwrite: overwrite,
    settle: settle,
    settleTimeout: settleTimeout,
    allowAutomaticCollision: allowAutomaticCollision,
  );
  return finalizeCapturedFrame(frame);
}

Future<CapturedFrame> captureFrame({
  String? name,
  flutter_test.Finder? finder,
  String? outputDirectory,
  double? pixelRatio,
  double padding = 0,
  bool overwrite = false,
  bool settle = false,
  Duration settleTimeout = const Duration(seconds: 5),
  required bool allowAutomaticCollision,
  Set<String>? reservedPaths,
}) async {
  final flutter_test.TestWidgetsFlutterBinding binding =
      flutter_test.TestWidgetsFlutterBinding.ensureInitialized();
  if (!binding.inTest) {
    throw ObjektsCaptureException(
      'screenshots() must be called from an active Flutter widget test.',
    );
  }
  if (padding < 0) {
    throw ObjektsCaptureException('Screenshot padding cannot be negative.');
  }
  if (settleTimeout <= Duration.zero) {
    throw ObjektsCaptureException('settleTimeout must be greater than zero.');
  }

  try {
    if (settle) {
      await _settle(binding, settleTimeout);
    }
    final RenderView renderView = binding.renderViews.single;
    final OffsetLayer? rootLayer = renderView.debugLayer as OffsetLayer?;
    if (rootLayer == null) {
      throw ObjektsCaptureException(
        'The Flutter render layer is unavailable. Pump a widget before capturing.',
      );
    }

    final ui.Size surfaceSize = renderView.size;
    if (surfaceSize.isEmpty) {
      throw ObjektsCaptureException('The Flutter test surface has no size.');
    }
    final ui.Rect surfaceBounds = ui.Offset.zero & surfaceSize;
    final ui.Rect captureBounds = _captureBounds(
      finder: finder,
      surfaceBounds: surfaceBounds,
      padding: padding,
    );
    final CaptureContext? context = currentCaptureContext;
    final double ratio =
        pixelRatio ?? context?.deviceConfig?.device.pixelRatio ?? 1.0;
    if (!ratio.isFinite || ratio <= 0) {
      throw ObjektsCaptureException(
          'pixelRatio must be a finite value greater than zero.');
    }

    final Directory directory = artifactDirectory(
      context: context,
      outputDirectory: outputDirectory,
    )..createSync(recursive: true);
    final File file = nextArtifactFile(
      directory: directory,
      name: name,
      context: context,
      overwrite: overwrite,
      allowAutomaticCollision: allowAutomaticCollision,
      reservedPaths: reservedPaths,
    );
    final String reservedPath = file.absolute.path;
    reservedPaths?.add(reservedPath);

    final ui.Image? image = await binding.runAsync<ui.Image>(() async {
      final RenderObject? boundaryObject = finder == null
          ? context?.surfaceBoundaryKey.currentContext?.findRenderObject()
          : null;
      if (boundaryObject is RenderRepaintBoundary) {
        return boundaryObject.toImage(pixelRatio: ratio);
      }
      return _captureLayerImage(
        rootLayer: rootLayer,
        bounds: captureBounds,
        pixelRatio: ratio,
        viewPixelRatio: renderView.flutterView.devicePixelRatio,
      );
    });
    final Object? asyncException = binding.takeException();
    if (asyncException != null) {
      image?.dispose();
      reservedPaths?.remove(reservedPath);
      throw ObjektsCaptureException(
        'Flutter failed while rasterizing the screenshot.',
        cause: asyncException,
      );
    }
    if (image == null) {
      reservedPaths?.remove(reservedPath);
      throw ObjektsCaptureException(
        'Flutter could not rasterize the screenshot.',
      );
    }

    return CapturedFrame(
      image: image,
      result: ScreenshotResult(
        path: reservedPath,
        target: finder == null
            ? ObjektsScreenshotTarget.surface
            : ObjektsScreenshotTarget.finder,
        logicalSize: ui.Size(captureBounds.width, captureBounds.height),
        pixelSize: ui.Size(
          (captureBounds.width * ratio).ceilToDouble(),
          (captureBounds.height * ratio).ceilToDouble(),
        ),
        pixelRatio: ratio,
        deviceIdentifier: context?.deviceConfig?.deviceIdentifier,
        orientation: context?.deviceConfig?.orientation,
      ),
    );
  } on ObjektsCaptureException {
    rethrow;
  } on Object catch (error, stackTrace) {
    throw ObjektsCaptureException(
      'Unable to write the screenshot.',
      cause: error,
      stackTrace: stackTrace,
    );
  }
}

Future<ScreenshotResult> finalizeCapturedFrame(CapturedFrame frame) async {
  final flutter_test.TestWidgetsFlutterBinding binding =
      flutter_test.TestWidgetsFlutterBinding.ensureInitialized();
  try {
    final bool? didWrite = await binding.runAsync<bool>(() async {
      final ByteData? byteData =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw ObjektsCaptureException(
          'Flutter could not encode the screenshot as PNG.',
        );
      }
      final Uint8List bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      await File(frame.result.path).writeAsBytes(bytes, flush: false);
      return true;
    });
    final Object? asyncException = binding.takeException();
    if (asyncException != null) {
      throw ObjektsCaptureException(
        'Flutter failed while encoding or writing the screenshot.',
        cause: asyncException,
      );
    }
    if (didWrite != true) {
      throw ObjektsCaptureException(
        'Flutter could not encode or write the screenshot.',
      );
    }
    return frame.result;
  } on ObjektsCaptureException {
    rethrow;
  } on Object catch (error, stackTrace) {
    throw ObjektsCaptureException(
      'Unable to write the screenshot.',
      cause: error,
      stackTrace: stackTrace,
    );
  } finally {
    frame.image.dispose();
  }
}

Future<ui.Image> _captureLayerImage({
  required OffsetLayer rootLayer,
  required ui.Rect bounds,
  required double pixelRatio,
  required double viewPixelRatio,
}) async {
  if (!viewPixelRatio.isFinite || viewPixelRatio <= 0) {
    throw ObjektsCaptureException(
      'The Flutter test view has an invalid device pixel ratio.',
    );
  }

  // The render-view layer already applies FlutterView.devicePixelRatio. The
  // requested screenshot ratio is independent of that transform, so cancel
  // the view transform before composing the scene. Without this correction,
  // screenshots are rendered at the wrong scale and their contents are
  // clipped to the top-left portion of the surface.
  final double sceneScale = pixelRatio / viewPixelRatio;
  final double translationX = -(bounds.left + rootLayer.offset.dx) * sceneScale;
  final double translationY = -(bounds.top + rootLayer.offset.dy) * sceneScale;
  final Float64List transform = Float64List.fromList(<double>[
    sceneScale,
    0,
    0,
    0,
    0,
    sceneScale,
    0,
    0,
    0,
    0,
    1,
    0,
    translationX,
    translationY,
    0,
    1,
  ]);

  final ui.SceneBuilder builder = ui.SceneBuilder()..pushTransform(transform);
  final ui.Scene scene = rootLayer.buildScene(builder);
  try {
    return await scene.toImage(
      (bounds.width * pixelRatio).ceil(),
      (bounds.height * pixelRatio).ceil(),
    );
  } finally {
    scene.dispose();
  }
}

ui.Rect _captureBounds({
  required flutter_test.Finder? finder,
  required ui.Rect surfaceBounds,
  required double padding,
}) {
  if (finder == null) {
    return surfaceBounds;
  }

  final List<widgets.Element> matches = finder.evaluate().toList();
  if (matches.length != 1) {
    throw ObjektsCaptureException(
      'A focused screenshot requires exactly one Finder match; found ${matches.length}.',
    );
  }
  final RenderObject? renderObject = matches.single.renderObject;
  if (renderObject is! RenderBox) {
    throw ObjektsCaptureException(
      'The Finder match does not have a renderable RenderBox.',
    );
  }
  if (!renderObject.hasSize) {
    throw ObjektsCaptureException('The Finder match has not been laid out.');
  }

  final ui.Rect globalBounds = MatrixUtils.transformRect(
    renderObject.getTransformTo(null),
    renderObject.paintBounds,
  ).inflate(padding);
  final ui.Rect clippedBounds = globalBounds.intersect(surfaceBounds);
  if (clippedBounds.isEmpty) {
    throw ObjektsCaptureException(
        'The Finder match has no visible bounds on the test surface.');
  }
  return clippedBounds;
}

Future<void> _settle(
  flutter_test.TestWidgetsFlutterBinding binding,
  Duration timeout,
) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (binding.hasScheduledFrame) {
    if (DateTime.now().isAfter(deadline)) {
      throw ObjektsCaptureException(
        'The widget tree did not settle within ${timeout.inMilliseconds}ms.',
      );
    }
    await binding.pump(const Duration(milliseconds: 16));
  }
}
