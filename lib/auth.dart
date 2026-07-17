import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dartdap/dartdap.dart';
import 'config.dart';

// ── Suchverlauf ───────────────────────────────────────────────────────────────

final _history = <String, List<String>>{};

void addSearchHistory(String token, String query) {
  if (query.trim().isEmpty) return;
  final list = _history.putIfAbsent(token, () => []);
  list.remove(query); // Duplikat entfernen
  list.insert(0, query);
  if (list.length > 10) list.removeLast();
}

List<String> getSearchHistory(String? token) =>
    token == null ? [] : List.unmodifiable(_history[token] ?? []);

// ── User-Notizen ──────────────────────────────────────────────────────────────

final _notesFile = File(
  '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}notes.json');

Map<String, Map<String, dynamic>> _notes = {};
bool _notesLoaded = false;

void _ensureNotesLoaded() {
  if (_notesLoaded) return;
  _notesLoaded = true;
  if (!_notesFile.existsSync()) return;
  try {
    final raw = jsonDecode(_notesFile.readAsStringSync(encoding: utf8)) as Map<String, dynamic>;
    _notes = raw.map((k, v) => MapEntry(k, (v as Map<String, dynamic>)));
  } catch (_) {}
}

void _persistNotes() {
  try {
    _notesFile.writeAsStringSync(jsonEncode(_notes), encoding: utf8);
  } catch (_) {}
}

Map<String, dynamic>? getUserNote(String dn) {
  _ensureNotesLoaded();
  return _notes[dn.toLowerCase()];
}

void setUserNote(String dn, String text, String actor) {
  _ensureNotesLoaded();
  final key = dn.toLowerCase();
  if (text.trim().isEmpty) {
    _notes.remove(key);
  } else {
    _notes[key] = {
      'text': text,
      'updatedAt': DateTime.now().toIso8601String(),
      'updatedBy': actor,
    };
  }
  _persistNotes();
}

// ── Favorites ────────────────────────────────────────────────────────────────

class Favorite {
  final String dn;
  final String name;
  Favorite(this.dn, this.name);
  Map<String, dynamic> toJson() => {'dn': dn, 'name': name};
  factory Favorite.fromJson(Map<String, dynamic> j) =>
      Favorite(j['dn'] as String, j['name'] as String);
}

class SessionData {
  final String username;
  final String dn;
  final String password;
  SessionData(this.username, this.dn, this.password);
}

// ── Rollen ────────────────────────────────────────────────────────────────────

enum UserRole { admin, operator, readonly }

final _rolesFile = File(
  '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}roles.json');
final _roles = <String, UserRole>{};
bool _rolesLoaded = false;

UserRole getRole(String username) {
  if (!_rolesLoaded) {
    _rolesLoaded = true;
    if (_rolesFile.existsSync()) {
      try {
        final map = jsonDecode(_rolesFile.readAsStringSync(encoding: utf8)) as Map<String, dynamic>;
        for (final e in map.entries) {
          _roles[e.key.toLowerCase()] = switch (e.value) {
            'operator' => UserRole.operator,
            'readonly' => UserRole.readonly,
            _ => UserRole.admin,
          };
        }
      } catch (_) {}
    }
  }
  if (username.toLowerCase().contains('admin')) return UserRole.admin;
  return _roles[username.toLowerCase()] ?? UserRole.readonly;
}

void saveRoles(Map<String, UserRole> roles) {
  final map = roles.map((k, v) => MapEntry(k, v.name));
  _rolesFile.writeAsStringSync(jsonEncode(map), encoding: utf8);
  _roles
    ..clear()
    ..addAll(roles);
}

Map<String, UserRole> getAllRoles() {
  getRole('__init__'); // ensure loaded
  return Map.unmodifiable(_roles);
}

final _sessions    = <String, SessionData>{};
final _settings    = <String, Map<String, bool>>{};
final _favorites   = <String, List<Favorite>>{};
final _rng = Random.secure();

// ── Login Rate-Limiting ───────────────────────────────────────────────────────

final _loginFailures = <String, (int, DateTime)>{};
const _maxAttempts = 5;
const _lockoutMinutes = 15;

bool isLoginBlocked(String username) {
  final e = _loginFailures[username.toLowerCase()];
  if (e == null) return false;
  if (DateTime.now().difference(e.$2).inMinutes >= _lockoutMinutes) {
    _loginFailures.remove(username.toLowerCase());
    return false;
  }
  return e.$1 >= _maxAttempts;
}

void recordLoginFailure(String username) {
  final key = username.toLowerCase();
  final e = _loginFailures[key];
  if (e == null || DateTime.now().difference(e.$2).inMinutes >= _lockoutMinutes) {
    _loginFailures[key] = (1, DateTime.now());
  } else {
    _loginFailures[key] = (e.$1 + 1, e.$2);
  }
}

void clearLoginFailures(String username) =>
    _loginFailures.remove(username.toLowerCase());

// ── CSRF ──────────────────────────────────────────────────────────────────────

final _csrf = <String, String>{};

String getCsrfToken(String? token) {
  if (token == null) return '';
  return _csrf.putIfAbsent(token, () =>
    List.generate(16, (_) => _rng.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0')).join());
}

bool validateCsrf(String? token, String? csrfValue) {
  if (token == null || csrfValue == null || csrfValue.isEmpty) return false;
  return _csrf[token] == csrfValue;
}

// ── Session-Inaktivitäts-Timeout ──────────────────────────────────────────────

final _lastActivity = <String, DateTime>{};

// Sessions werden in dieser Datei neben der .exe gespeichert
final _sessionsFile = File(
  '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}sessions.json');

bool _loaded = false;

void _ensureLoaded() {
  if (_loaded) return;
  _loaded = true;
  if (!_sessionsFile.existsSync()) return;
  try {
    final raw = jsonDecode(_sessionsFile.readAsStringSync(encoding: utf8)) as Map<String, dynamic>;
    for (final e in raw.entries) {
      final d = e.value as Map<String, dynamic>;
      _sessions[e.key] = SessionData(
        d['username'] as String,
        d['dn'] as String,
        d['password'] as String,
      );
    }
  } catch (_) {}
}

// Sessions werden bewusst nicht auf Disk persistiert (Passwörter im Klartext wäre Sicherheitsrisiko).
// Neustart der App erfordert erneutes Login — akzeptabel für internes Tool.

class GroupClipboard {
  final String sourceUsername;
  final String sourceDn;
  final List<String> groupDns;
  GroupClipboard(this.sourceUsername, this.sourceDn, this.groupDns);
}

final _clipboards = <String, GroupClipboard>{};

void setClipboard(String token, GroupClipboard clipboard) =>
    _clipboards[token] = clipboard;

GroupClipboard? getClipboard(String? token) =>
    token == null ? null : _clipboards[token];

void clearClipboard(String token) => _clipboards.remove(token);

String createSession(SessionData data) {
  final token = List.generate(32, (_) => _rng.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  _sessions[token] = data;
  _lastActivity[token] = DateTime.now();
  return token;
}

SessionData? getSession(String? token) {
  if (token == null) return null;
  final data = _sessions[token];
  if (data == null) return null;
  // Session-Inaktivitäts-Timeout: 60 Minuten
  final last = _lastActivity[token];
  if (last != null && DateTime.now().difference(last).inMinutes >= 60) {
    destroySession(token);
    return null;
  }
  _lastActivity[token] = DateTime.now();
  return data;
}

void destroySession(String token) {
  _sessions.remove(token);
  _settings.remove(token);
  _favorites.remove(token);
  _csrf.remove(token);
  _lastActivity.remove(token);
}

List<Favorite> getFavorites(String? token) =>
    token == null ? [] : List.unmodifiable(_favorites[token] ?? []);

void toggleFavorite(String token, String dn, String name) {
  final list = _favorites.putIfAbsent(token, () => []);
  final idx = list.indexWhere((f) => f.dn == dn);
  if (idx >= 0) {
    list.removeAt(idx);
  } else {
    list.add(Favorite(dn, name));
  }
}

bool getSessionSetting(String? token, String key, {bool defaultValue = false}) =>
    token == null ? defaultValue : (_settings[token]?[key] ?? defaultValue);

void toggleSessionSetting(String token, String key) {
  _settings.putIfAbsent(token, () => {})[key] =
      !(_settings[token]?[key] ?? false);
}

Map<String, bool> getSessionSettings(String? token) =>
    token == null ? {} : Map.unmodifiable(_settings[token] ?? {});

String? extractToken(String? cookieHeader) {
  if (cookieHeader == null) return null;
  for (final part in cookieHeader.split(';')) {
    final kv = part.trim().split('=');
    if (kv.length == 2 && kv[0].trim() == 'session') return kv[1].trim();
  }
  return null;
}

// Gibt bei Fehler eine Fehlermeldung zurück, bei Erfolg null + befüllt sessionData
Future<(String?, SessionData?)> tryLogin(Config config, String username, String password) async {
  String bindDn;
  try {
    final searcher = LdapConnection(
      host: config.server,
      ssl: config.useSsl,
      port: config.port,
      bindDN: DN(config.bindUser),
      password: config.bindPassword,
      badCertificateHandler: (cert) => config.ignoreCert,
    );
    await searcher.open();
    await searcher.bind();

    final result = await searcher.search(
      DN(config.baseDn),
      Filter.or([
        Filter.equals('sAMAccountName', username),
        Filter.equals('mail', username),
        Filter.equals('userPrincipalName', username),
      ]),
      ['distinguishedName'],
    );

    String? dn;
    await for (final entry in result.stream) {
      final candidate = entry.dn.toString();
      if (candidate.isNotEmpty && dn == null) dn = candidate;
    }
    await searcher.close();

    if (dn == null) return ('Benutzer nicht gefunden.', null);
    if (config.adminOu.isNotEmpty && !dn.toUpperCase().contains(config.adminOu.toUpperCase())) {
      return ('Kein Zugriff. Nur Administratoren dürfen sich anmelden.', null);
    }
    bindDn = dn;
  } catch (e) {
    return ('LDAP-Fehler: $e', null);
  }

  // Mit User-Credentials binden
  try {
    final userConn = LdapConnection(
      host: config.server,
      ssl: config.useSsl,
      port: config.port,
      bindDN: DN(bindDn),
      password: password,
      badCertificateHandler: (cert) => config.ignoreCert,
    );
    await userConn.open();
    await userConn.bind();
    await userConn.close();
  } catch (e) {
    return ('Falsches Passwort.', null);
  }

  return (null, SessionData(username, bindDn, password));
}
