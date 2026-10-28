/// Checks a new password against the backend rule: 8 to 128 characters.
///
/// It counts characters the same way as the backend (Unicode code points,
/// `password.runes`), so an emoji counts as one character, not as its 4 bytes.
/// The backend also normalizes and hashes the password; the app sends it as typed.
/// Returns null when the password is fine, or the message to show.
String? passwordProblem(String password) {
  final characters = password.runes.length;
  if (characters < 8 || characters > 128) {
    return 'Use a password between 8 and 128 characters.';
  }
  return null;
}
