/// Turns a stored name into the form a page should show.
///
/// Names are stored exactly as the account created them, which is why the
/// Firestore documents can contain "sakshi". That is a storage fact, not a
/// display style: every page, greeting, chip and sentence capitalises the
/// first letter of each word without touching the identifier or the stored
/// value.
String displayName(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.split(RegExp(r'\s+')).map((String word) {
    if (word.isEmpty) return word;
    return word
        .split('-')
        .map((String part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join('-');
  }).join(' ');
}
