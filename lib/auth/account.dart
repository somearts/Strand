/// The signed-in person, as Strand needs it.
///
/// The name and email are cached on the device so the greeting is still right
/// on the first frame after a cold start, before Firebase has answered. The
/// cache is refreshed from the authenticated profile every time the session
/// changes, so it cannot drift into a stale name.
class Account {
  const Account({
    required this.uid,
    required this.name,
    required this.email,
  });

  final String uid;
  final String name;
  final String email;

  /// The part of the name a greeting should use: "Samrat", not the full legal
  /// name. Falls back to the email's local part if the provider sent no name,
  /// because a greeting with no name at all is better than one that says "User".
  String get greetingName {
    final String trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed.split(RegExp(r'\s+')).first;
    final String local = email.split('@').first.trim();
    return local.isEmpty ? '' : local;
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'uid': uid,
        'name': name,
        'email': email,
      };

  factory Account.fromMap(Map<dynamic, dynamic> map) => Account(
        uid: (map['uid'] as String?) ?? '',
        name: (map['name'] as String?) ?? '',
        email: (map['email'] as String?) ?? '',
      );
}
