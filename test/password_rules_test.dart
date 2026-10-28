import 'package:campus_bites/services/password_rules.dart';
import 'package:flutter_test/flutter_test.dart';

const _problem = 'Use a password between 8 and 128 characters.';

void main() {
  test('19 emojis are 19 characters, not 76 bytes', () {
    expect(passwordProblem('😀' * 19), isNull);
  });

  test('two emojis are too short even though they are 8 bytes', () {
    expect(passwordProblem('😀😀'), _problem);
  });

  test('7 letters are rejected and 8 are accepted', () {
    expect(passwordProblem('a' * 7), _problem);
    expect(passwordProblem('a' * 8), isNull);
  });

  test('128 characters are accepted and 129 are rejected', () {
    expect(passwordProblem('a' * 128), isNull);
    expect(passwordProblem('a' * 129), _problem);
  });

  test('accents count as one character', () {
    expect(passwordProblem('contraseña1'), isNull);
  });
}
