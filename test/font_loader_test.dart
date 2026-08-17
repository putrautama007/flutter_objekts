import 'package:flutter_test/flutter_test.dart';
import 'package:objekts/objekts.dart' as objekts;

void main() {
  test('loads application fonts idempotently', () async {
    await objekts.loadAppFonts();
    await objekts.loadAppFonts();
  });
}
