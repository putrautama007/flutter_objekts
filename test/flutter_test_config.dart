import 'dart:async';

import 'package:objekts/objekts.dart' as objekts;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await objekts.loadAppFonts();
  await testMain();
}
