import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void>? _loadAppFontsFuture;

/// Loads fonts declared by the application and its package dependencies.
///
/// Flutter widget tests use a block-style fallback font by default. Loading
/// the fonts from the generated font manifest makes screenshot text render
/// with the fonts registered in the project's pubspec files.
Future<void> loadAppFonts() {
  return _loadAppFontsFuture ??= _loadFontsFromManifest();
}

Future<void> _loadFontsFromManifest() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Iterable<dynamic> fontManifest =
      await rootBundle.loadStructuredData<Iterable<dynamic>>(
    'FontManifest.json',
    (String manifest) async => jsonDecode(manifest) as Iterable<dynamic>,
  );

  final Map<String, FontLoader> loaders = <String, FontLoader>{};
  for (final dynamic definition in fontManifest) {
    if (definition is! Map<dynamic, dynamic>) {
      continue;
    }

    final String family = _derivedFontFamily(definition);
    if (family.isEmpty) {
      continue;
    }

    final dynamic fontEntries = definition['fonts'];
    if (fontEntries is! Iterable<dynamic>) {
      continue;
    }

    final FontLoader loader =
        loaders.putIfAbsent(family, () => FontLoader(family));
    for (final dynamic fontEntry in fontEntries) {
      if (fontEntry is Map<dynamic, dynamic>) {
        final dynamic asset = fontEntry['asset'];
        if (asset is String) {
          loader.addFont(rootBundle.load(asset));
        }
      }
    }
  }

  await Future.wait(
    loaders.values.map((FontLoader loader) => loader.load()),
  );
}

String _derivedFontFamily(Map<dynamic, dynamic> definition) {
  final dynamic familyValue = definition['family'];
  if (familyValue is! String || familyValue.isEmpty) {
    return '';
  }

  final String family = familyValue;
  if (_overridableFonts.contains(family)) {
    return family;
  }

  if (family.startsWith('packages/')) {
    final String familyName = family.split('/').last;
    if (_overridableFonts.contains(familyName)) {
      return familyName;
    }

    return family;
  }

  final dynamic fontEntries = definition['fonts'];
  if (fontEntries is Iterable<dynamic>) {
    for (final dynamic fontEntry in fontEntries) {
      if (fontEntry is! Map<dynamic, dynamic>) {
        continue;
      }

      final dynamic assetValue = fontEntry['asset'];
      if (assetValue is! String || !assetValue.startsWith('packages/')) {
        continue;
      }

      final List<String> assetParts = assetValue.split('/');
      if (assetParts.length > 2) {
        return 'packages/${assetParts[1]}/$family';
      }
    }
  }

  return family;
}

const Set<String> _overridableFonts = <String>{
  'Roboto',
  '.SF UI Display',
  '.SF UI Text',
  '.SF Pro Text',
  '.SF Pro Display',
};
