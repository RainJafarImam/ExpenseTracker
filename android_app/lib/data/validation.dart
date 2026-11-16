/// Input checks. Same rules as the PC server (main.py).

class ValidationException implements Exception {
  ValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Largest amount accepted (guards against typos like an extra run of zeros).
const double kMaxAmount = 1e12;

String _pad(int n, int width) => n.toString().padLeft(width, '0');

/// Returns the date as YYYY-MM-DD, or throws if it is not a real calendar date.
String checkDate(String value, [String field = 'date']) {
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(value.trim());
  final error = ValidationException(
      "$field '$value' is not a valid date. Use YYYY-MM-DD, e.g. 2026-11-15");
  if (m == null) throw error;
  final y = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  final d = int.parse(m[3]!);
  final check = DateTime.utc(y, mo, d);
  if (check.year != y || check.month != mo || check.day != d) throw error;
  return '${_pad(y, 4)}-${_pad(mo, 2)}-${_pad(d, 2)}';
}

(String, String) checkRange(String start, String end) {
  final s = checkDate(start, 'start_date');
  final e = checkDate(end, 'end_date');
  if (s.compareTo(e) > 0) {
    throw ValidationException('start_date must not be after end_date');
  }
  return (s, e);
}

double checkAmount(double? value, [String field = 'amount']) {
  if (value == null || value.isNaN || value.isInfinite) {
    throw ValidationException('$field must be a number');
  }
  if (value <= 0) {
    throw ValidationException('$field must be a positive number');
  }
  if (value > kMaxAmount) {
    throw ValidationException('$field is too large');
  }
  return value;
}

String checkCurrency(String? code) {
  final c = (code ?? '').trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(c)) {
    throw ValidationException(
        'currency must be a 3-letter ISO code like INR, USD or EUR');
  }
  return c;
}

String checkText(String? value, String field, {bool required = false}) {
  final v = (value ?? '').trim();
  if (required && v.isEmpty) {
    throw ValidationException('$field must not be empty');
  }
  return v;
}

String checkMonth(String value) {
  final v = value.trim();
  if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(v)) {
    throw ValidationException('month must be in YYYY-MM format, e.g. 2026-11');
  }
  return v;
}
