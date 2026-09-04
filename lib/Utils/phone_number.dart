/// Returns the account phone identity used by the backend, or `null` when the
/// input is unsupported. The backend remains authoritative for validation.
String? normalizePhoneNumber(String rawPhone) {
  var phone = rawPhone.replaceAll(RegExp(r'[\s()-]'), '');
  if (phone.startsWith('00')) {
    phone = '+${phone.substring(2)}';
  }

  if (RegExp(r'^5[0-9]{9}$').hasMatch(phone)) {
    phone = '+90$phone';
  } else if (RegExp(r'^05[0-9]{9}$').hasMatch(phone)) {
    phone = '+90${phone.substring(1)}';
  }

  if (phone.startsWith('+90')) {
    return RegExp(r'^\+905[0-9]{9}$').hasMatch(phone) ? phone : null;
  }
  return RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone) ? phone : null;
}

bool isValidPhoneNumber(String rawPhone) =>
    normalizePhoneNumber(rawPhone) != null;

bool samePhoneIdentity(String first, String second) {
  final normalizedFirst = normalizePhoneNumber(first);
  final normalizedSecond = normalizePhoneNumber(second);
  return normalizedFirst != null && normalizedFirst == normalizedSecond;
}
