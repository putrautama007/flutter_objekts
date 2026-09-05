import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart' as flutter_test;
import 'package:image/image.dart' as image;

import 'capture.dart';
import 'context.dart';
import 'golden.dart';
import 'models.dart';
import 'paths.dart';

final Object _activeBatchKey = Object();

/// A scoped, bounded queue for screenshot and golden capture work.
abstract interface class ScreenshotBatch {
  /// Captures the current surface or one Finder-selected widget.
  ///
  /// Await this method before changing the rendered widget state.
  Future<void> capture({
    String? name,
    flutter_test.Finder? finder,
    double? pixelRatio,
    double padding = 0,
    bool overwrite = false,
    bool settle = false,
    Duration settleTimeout = const Duration(seconds: 5),
  });

  /// Captures and later compares the image with a golden PNG.
  ///
  /// Await this method before changing the rendered widget state.
  Future<void> matchGolden({
    required String name,
    flutter_test.Finder? finder,
    String? goldenDirectory,
    double? pixelRatio,
    double padding = 0,
    bool settle = false,
    Duration settleTimeout = const Duration(seconds: 5),
  });
}

/// Runs screenshot work while PNG encoding and file output proceed in parallel.
///
/// All returned files are ready to read and remain in capture declaration
/// order when this future completes.
Future<List<ScreenshotResult>> runScreenshotBatch(
  Future<void> Function(ScreenshotBatch batch) body, {
  int maxPendingCaptures = 2,
  String? outputDirectory,
  double? pixelRatio,
}) async {
  if (maxPendingCaptures <= 0) {
    throw ArgumentError.value(
      maxPendingCaptures,
      'maxPendingCaptures',
      'Must be greater than zero.',
    );
  }
  if (Zone.current[_activeBatchKey] != null) {
    throw StateError('Screenshot batches cannot be nested.');
  }
  final flutter_test.TestWidgetsFlutterBinding binding =
      flutter_test.TestWidgetsFlutterBinding.ensureInitialized();
  if (!binding.inTest) {
    throw ObjektsCaptureException(
      'runScreenshotBatch() must be called from an active Flutter widget test.',
    );
  }

  final _ScreenshotBatch batch = _ScreenshotBatch(
    binding: binding,
    maxPendingCaptures: maxPendingCaptures,
    outputDirectory: outputDirectory,
    pixelRatio: pixelRatio,
  );
  Object? bodyError;
  StackTrace? bodyStackTrace;
  try {
    await runZoned<Future<void>>(
      () => body(batch),
      zoneValues: <Object?, Object?>{_activeBatchKey: batch},
    );
  } on Object catch (error, stackTrace) {
    bodyError = error;
    bodyStackTrace = stackTrace;
  }

  Object? finishError;
  StackTrace? finishStackTrace;
  List<ScreenshotResult> results = const <ScreenshotResult>[];
  try {
    results = await batch.close(compareGoldens: bodyError == null);
  } on Object catch (error, stackTrace) {
    finishError = error;
    finishStackTrace = stackTrace;
  }

  if (bodyError != null) {
    if (finishError != null) {
      print(
        'Objekts finished the failed screenshot batch with another error: '
        '$finishError\n$finishStackTrace',
      );
    }
    Error.throwWithStackTrace(bodyError, bodyStackTrace!);
  }
  if (finishError != null) {
    Error.throwWithStackTrace(finishError, finishStackTrace!);
  }
  return results;
}

class _ScreenshotBatch implements ScreenshotBatch {
  _ScreenshotBatch({
    required this.binding,
    required this.maxPendingCaptures,
    required this.outputDirectory,
    required this.pixelRatio,
  }) : _encoderPool = _PngEncoderPool(maxPendingCaptures);

  final flutter_test.TestWidgetsFlutterBinding binding;
  final int maxPendingCaptures;
  final String? outputDirectory;
  final double? pixelRatio;
  final _PngEncoderPool _encoderPool;
  final Set<String> _reservedPaths = <String>{};
  final Queue<_BatchEntry> _pending = Queue<_BatchEntry>();
  final List<_BatchEntry> _entries = <_BatchEntry>[];
  final Map<String, Future<_FinalizationOutcome>> _lastWriteByPath =
      <String, Future<_FinalizationOutcome>>{};
  bool _isOpen = true;

  @override
  Future<void> capture({
    String? name,
    flutter_test.Finder? finder,
    double? pixelRatio,
    double padding = 0,
    bool overwrite = false,
    bool settle = false,
    Duration settleTimeout = const Duration(seconds: 5),
  }) {
    return _enqueue(
      name: name,
      finder: finder,
      pixelRatio: pixelRatio,
      padding: padding,
      overwrite: overwrite,
      settle: settle,
      settleTimeout: settleTimeout,
    );
  }

  @override
  Future<void> matchGolden({
    required String name,
    flutter_test.Finder? finder,
    String? goldenDirectory,
    double? pixelRatio,
    double padding = 0,
    bool settle = false,
    Duration settleTimeout = const Duration(seconds: 5),
  }) {
    return _enqueue(
      name: name,
      finder: finder,
      pixelRatio: pixelRatio,
      padding: padding,
      overwrite: true,
      settle: settle,
      settleTimeout: settleTimeout,
      goldenPath: resolveGoldenFilePath(
        context: currentCaptureContext,
        name: name,
        goldenDirectory: goldenDirectory,
      ),
    );
  }

  Future<void> _enqueue({
    required String? name,
    required flutter_test.Finder? finder,
    required double? pixelRatio,
    required double padding,
    required bool overwrite,
    required bool settle,
    required Duration settleTimeout,
    String? goldenPath,
  }) async {
    _ensureOpen();
    if (_pending.length >= maxPendingCaptures) {
      await _completeOldest();
    }
    _ensureOpen();

    final CapturedFrame frame = await captureFrame(
      name: name,
      finder: finder,
      outputDirectory: outputDirectory,
      pixelRatio: pixelRatio ?? this.pixelRatio,
      padding: padding,
      overwrite: overwrite,
      settle: settle,
      settleTimeout: settleTimeout,
      allowAutomaticCollision: false,
      reservedPaths: _reservedPaths,
    );
    final _BatchEntry entry = _BatchEntry(
      name: name ?? frame.result.path,
      frame: frame,
      goldenPath: goldenPath,
    );
    _entries.add(entry);
    _pending.add(entry);

    final bool? scheduled = await binding.runAsync<bool>(() async {
      final Future<_FinalizationOutcome>? previousWrite =
          _lastWriteByPath[frame.result.path];
      entry.finalization = _finalize(
        entry.frame,
        previousWrite: previousWrite,
      );
      _lastWriteByPath[frame.result.path] = entry.finalization!;
      return true;
    });
    final Object? asyncException = binding.takeException();
    if (asyncException != null || scheduled != true) {
      if (entry.finalization == null) {
        frame.image.dispose();
        _pending.remove(entry);
        _entries.remove(entry);
      }
      throw ObjektsCaptureException(
        'Unable to schedule screenshot "$name" for encoding.',
        cause: asyncException,
      );
    }
  }

  Future<_FinalizationOutcome> _finalize(
    CapturedFrame frame, {
    Future<_FinalizationOutcome>? previousWrite,
  }) async {
    try {
      final ByteData? byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (byteData == null) {
        throw ObjektsCaptureException(
          'Flutter could not read screenshot pixels.',
        );
      }
      final Uint8List rawPixels = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final Uint8List png = await _encoderPool.encode(
        rawPixels,
        frame.image.width,
        frame.image.height,
      );
      if (previousWrite != null) {
        await previousWrite;
      }
      await File(frame.result.path).writeAsBytes(png, flush: false);
      return _FinalizationOutcome.success(frame.result);
    } on Object catch (error, stackTrace) {
      return _FinalizationOutcome.failure(error, stackTrace);
    } finally {
      frame.image.dispose();
    }
  }

  Future<void> _completeOldest() async {
    final _BatchEntry entry = _pending.removeFirst();
    final Future<_FinalizationOutcome>? finalization = entry.finalization;
    if (finalization == null) {
      throw StateError('Screenshot finalization was not scheduled.');
    }
    final _FinalizationOutcome? outcome =
        await binding.runAsync<_FinalizationOutcome>(() => finalization);
    final Object? asyncException = binding.takeException();
    if (asyncException != null) {
      entry.outcome = _FinalizationOutcome.failure(
        asyncException,
        StackTrace.current,
      );
    } else {
      entry.outcome = outcome ??
          _FinalizationOutcome.failure(
            StateError('Screenshot finalization returned no result.'),
            StackTrace.current,
          );
    }
  }

  Future<List<ScreenshotResult>> close({
    required bool compareGoldens,
  }) async {
    _isOpen = false;
    while (_pending.isNotEmpty) {
      await _completeOldest();
    }
    await _encoderPool.close();

    for (final _BatchEntry entry in _entries) {
      final _FinalizationOutcome outcome = entry.outcome!;
      if (outcome.error != null) {
        throw ObjektsCaptureException(
          'Unable to finalize screenshot "${entry.name}".',
          cause: outcome.error,
          stackTrace: outcome.stackTrace,
        );
      }
    }

    if (compareGoldens) {
      for (final _BatchEntry entry in _entries) {
        if (entry.goldenPath != null) {
          await compareScreenshotWithGolden(
            entry.outcome!.result!,
            entry.goldenPath!,
          );
        }
      }
    }
    return List<ScreenshotResult>.unmodifiable(
      _entries.map((entry) => entry.outcome!.result!),
    );
  }

  void _ensureOpen() {
    if (!_isOpen) {
      throw StateError('This screenshot batch has already closed.');
    }
  }
}

class _BatchEntry {
  _BatchEntry({
    required this.name,
    required this.frame,
    required this.goldenPath,
  });

  final String name;
  final CapturedFrame frame;
  final String? goldenPath;
  Future<_FinalizationOutcome>? finalization;
  _FinalizationOutcome? outcome;
}

class _FinalizationOutcome {
  const _FinalizationOutcome._({
    this.result,
    this.error,
    this.stackTrace,
  });

  factory _FinalizationOutcome.success(ScreenshotResult result) {
    return _FinalizationOutcome._(result: result);
  }

  factory _FinalizationOutcome.failure(Object error, StackTrace stackTrace) {
    return _FinalizationOutcome._(error: error, stackTrace: stackTrace);
  }

  final ScreenshotResult? result;
  final Object? error;
  final StackTrace? stackTrace;
}

class _PngEncoderPool {
  _PngEncoderPool(this.maximumWorkers);

  final int maximumWorkers;
  final Queue<_PngEncodeJob> _jobs = Queue<_PngEncodeJob>();
  int _activeWorkers = 0;
  Completer<void>? _drained;
  bool _isClosed = false;

  Future<Uint8List> encode(Uint8List pixels, int width, int height) {
    if (_isClosed) {
      throw StateError('The PNG encoder pool has closed.');
    }
    final _PngEncodeJob job = _PngEncodeJob(
      pixels: TransferableTypedData.fromList(<TypedData>[pixels]),
      width: width,
      height: height,
    );
    _jobs.add(job);
    _dispatch();
    return job.completer.future;
  }

  void _dispatch() {
    while (_activeWorkers < maximumWorkers && _jobs.isNotEmpty) {
      final _PngEncodeJob job = _jobs.removeFirst();
      _activeWorkers += 1;
      _run(job);
    }
  }

  Future<void> _run(_PngEncodeJob job) async {
    try {
      final TransferableTypedData pixels = job.pixels;
      final int width = job.width;
      final int height = job.height;
      final TransferableTypedData encoded =
          await Isolate.run<TransferableTypedData>(
        () => _encodePng(pixels, width, height),
        debugName: 'objekts-png',
      );
      job.completer.complete(encoded.materialize().asUint8List());
    } on Object catch (error, stackTrace) {
      job.completer.completeError(
        ObjektsCaptureException(
          'PNG worker failed.',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    } finally {
      _activeWorkers -= 1;
      _dispatch();
      if (_isClosed && _jobs.isEmpty && _activeWorkers == 0) {
        _drained?.complete();
      }
    }
  }

  Future<void> close() async {
    _isClosed = true;
    if (_jobs.isEmpty && _activeWorkers == 0) {
      return;
    }
    _drained ??= Completer<void>();
    await _drained!.future;
  }
}

class _PngEncodeJob {
  _PngEncodeJob({
    required this.pixels,
    required this.width,
    required this.height,
  });

  final TransferableTypedData pixels;
  final int width;
  final int height;
  final Completer<Uint8List> completer = Completer<Uint8List>();
}

TransferableTypedData _encodePng(
  TransferableTypedData pixels,
  int width,
  int height,
) {
  final Uint8List rgba = pixels.materialize().asUint8List();
  final image.Image screenshot = image.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    order: image.ChannelOrder.rgba,
  );
  final Uint8List encoded = image.PngEncoder(
    level: 1,
    filter: image.PngFilter.sub,
  ).encode(screenshot);
  return TransferableTypedData.fromList(<TypedData>[
    _withFlutterColorMetadata(encoded),
  ]);
}

Uint8List _withFlutterColorMetadata(Uint8List png) {
  // Flutter's engine PNG encoder emits 8-bit significance and standard-sRGB
  // chunks. Preserve them so decoding a batched PNG follows the exact same
  // color path as a PNG produced by ui.ImageByteFormat.png.
  const int afterHeader = 33;
  const List<int> metadata = <int>[
    0x00, 0x00, 0x00, 0x04, // sBIT data length
    0x73, 0x42, 0x49, 0x54, // sBIT
    0x08, 0x08, 0x08, 0x08,
    0x7c, 0x08, 0x64, 0x88, // CRC
    0x00, 0x00, 0x00, 0x01, // sRGB data length
    0x73, 0x52, 0x47, 0x42, // sRGB
    0x00, // perceptual rendering intent
    0xae, 0xce, 0x1c, 0xe9, // CRC
  ];
  final Uint8List result = Uint8List(png.length + metadata.length);
  result.setRange(0, afterHeader, png);
  result.setRange(afterHeader, afterHeader + metadata.length, metadata);
  result.setRange(
      afterHeader + metadata.length, result.length, png, afterHeader);
  return result;
}
