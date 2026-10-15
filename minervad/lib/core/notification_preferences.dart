/// Solo metadati e decisioni: mai testo o titoli delle notifiche nel registro.
const notificationSenderLimit = 256;

bool notificationSenderKey(String key) =>
    key.length <= 1025 && (key.length - 1).isEven &&
    RegExp(r'^[dn][0-9a-f]{2,1024}$').hasMatch(key);

bool _field(String name, dynamic value) {
  if (const ['enabled', 'banners', 'priority'].contains(name)) {
    return value is bool;
  }
  if (name == 'name') {
    return value is String && value.trim().isNotEmpty && value.length <= 128 &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);
  }
  if (name == 'desktop') {
    return value is String && value.length <= 128 &&
        !RegExp(r'[/\\\x00-\x20\x7f]').hasMatch(value);
  }
  return false;
}

bool _record(dynamic value) => value is Map && value.length == 5 &&
    const ['name', 'desktop', 'enabled', 'banners', 'priority'].every(value.containsKey) &&
    value.entries.every((entry) => entry.key is String && _field(entry.key, entry.value));

bool notificationPreference(String path, dynamic value) {
  if (path == 'notifications.apps') {
    return value is Map && value.length <= notificationSenderLimit &&
        value.entries.every((entry) => entry.key is String && notificationSenderKey(entry.key) && _record(entry.value));
  }
  final parts = path.split('.');
  if (parts.length < 3 || !notificationSenderKey(parts[2])) return false;
  if (parts.length == 3) return _record(value);
  return parts.length == 4 && _field(parts[3], value);
}
