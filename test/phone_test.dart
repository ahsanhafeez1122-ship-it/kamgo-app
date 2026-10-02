import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/core/utils/phone.dart';

void main() {
  test('normalises common Pakistani formats', () {
    for (final input in [
      '03001234567',
      '3001234567',
      '923001234567',
      '+92 300 1234567',
      '0092-300-1234567',
    ]) {
      expect(normalizePkPhone(input), '+923001234567', reason: input);
    }
  });

  test('rejects landlines and wrong lengths', () {
    expect(normalizePkPhone('0423571234'), isNull);
    expect(normalizePkPhone('030012345'), isNull);
    expect(normalizePkPhone(''), isNull);
  });

  test('formats for display', () {
    expect(formatPkPhone('+923001234567'), '0300 1234567');
  });
}
