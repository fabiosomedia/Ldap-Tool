import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartdap/dartdap.dart';
import 'package:shelf/shelf.dart';
import 'audit.dart';
import 'auth.dart';
import 'config.dart';
import 'ldap_client.dart';
import 'templates.dart';

// Hilfsfunktion: Extrahiere Token aus Cookie-Header
String? _token(Request req) => extractToken(req.headers['cookie']);

// Erstes RDN-Element aus DN extrahieren, escaped Kommas (\,) überspringen
String _firstRdn(String dn) {
  for (int i = 0; i < dn.length; i++) {
    if (dn[i] == ',' && (i == 0 || dn[i - 1] != '\\')) return dn.substring(0, i);
  }
  return dn;
}

// CSRF-Hilfsfunktionen
String _csrfFor(Request req) => getCsrfToken(_token(req));

bool _validCsrf(Request req, Map<String, String> params) =>
    validateCsrf(_token(req), params['_csrf']);

// Rollen-Hilfsfunktion
UserRole _role(Request req) {
  final s = _session(req);
  if (s == null) return UserRole.readonly;
  return getRole(s.username);
}

// Passwort-Komplexität prüfen (server-seitig)
bool _isPasswordStrong(String pwd) {
  if (pwd.length < 8) return false;
  if (!RegExp(r'[A-Z]').hasMatch(pwd)) return false;
  if (!RegExp(r'[a-z]').hasMatch(pwd)) return false;
  if (!RegExp(r'[0-9]').hasMatch(pwd)) return false;
  return true;
}

const _html = {
  'content-type': 'text/html; charset=utf-8',
  'cache-control': 'no-store',
  'x-content-type-options': 'nosniff',
  'x-frame-options': 'DENY',
  'referrer-policy': 'same-origin',
  'content-security-policy':
      "default-src 'self'; "
      "script-src 'self' 'unsafe-inline'; "
      "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
      "font-src https://fonts.gstatic.com; "
      "img-src 'self' data: blob:; "
      "object-src 'none'; "
      "base-uri 'self'; "
      "form-action 'self'",
};

Response _forbidden(String username) =>
    Response(403, body: renderError(username, 'Ungültige Anfrage (CSRF-Fehler). Bitte Seite neu laden.'), headers: _html, encoding: utf8);

const _allowedAttributes = {
  'givenName', 'sn', 'displayName', 'mail', 'telephoneNumber', 'mobile',
  'department', 'title', 'company', 'streetAddress', 'l', 'postalCode',
  'description', 'physicalDeliveryOfficeName', 'initials', 'info',
  'wWWHomePage', 'manager',
};

// Alle HTML-Responses explizit als UTF-8 Bytes senden (shelf default ist latin1)
Response _ok(String html) => Response.ok(html, headers: _html, encoding: utf8);
SessionData? _session(Request req) => getSession(extractToken(req.headers['cookie']));

// â”€â”€ Auth â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Response handleLoginPage(Request req) =>
    _ok(renderLogin(null));

Future<Response> handleLoginPost(Request req, Config config) async {
  final params = Uri.splitQueryString(await req.readAsString());
  // Unterstützt domain\username und user@domain → nur username extrahieren
  final rawUsername = params['username'] ?? '';
  final username = rawUsername.contains('\\')
      ? rawUsername.split('\\').last
      : rawUsername.contains('@')
          ? rawUsername.split('@').first
          : rawUsername;
  if (isLoginBlocked(username)) {
    return _ok(renderLogin('Account temporär gesperrt (zu viele Fehlversuche). Bitte 15 Minuten warten.'));
  }
  final (error, data) = await tryLogin(config, username, params['password'] ?? '');
  if (error != null || data == null) {
    recordLoginFailure(username);
    return _ok(renderLogin(error ?? 'Unbekannter Fehler.'));
  }
  clearLoginFailures(username);
  return Response.found('/', headers: {
    'set-cookie': 'session=${createSession(data)}; HttpOnly; Path=/; SameSite=Strict; Max-Age=86400',
  });
}

Response handleLogout(Request req) {
  final token = extractToken(req.headers['cookie']);
  if (token != null) destroySession(token);
  return Response.found('/login', headers: {
    'set-cookie': 'session=; HttpOnly; Path=/; Max-Age=0',
  });
}

// â”€â”€ Dashboard â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Response handleIndex(Request req) {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  final history = getSearchHistory(token);
  return _ok(renderIndex(session?.username ?? '', searchHistory: history));
}

Future<Response> handleDashboard(Request req, Config config) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final csrfToken = getCsrfToken(token);
  try {
    final stats = await LdapClient(config, session).getDashboardStats();
    final favs = getFavorites(token);
    return _ok(renderDashboard(session.username, stats, getAuditLog().take(6).toList(), favorites: favs, csrfToken: csrfToken));
  } catch (e) {
    return _ok(renderDashboard(session.username, {}, [], favorites: [], csrfToken: csrfToken));
  }
}

// â”€â”€ Suche â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleSearch(Request req, Config config) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final q = (req.url.queryParameters['q'] ?? '').substring(0, ((req.url.queryParameters['q'] ?? '').length).clamp(0, 100));
  if (q.isNotEmpty && token != null) {
    addSearchHistory(token, q);
  }
  final csrfToken = getCsrfToken(token);
  try {
    final results = await LdapClient(config, session).searchUsers(q);
    final history = getSearchHistory(token);
    if (q.isEmpty && results.isEmpty) return _ok(renderIndex(session.username, searchHistory: history, csrfToken: csrfToken));
    return _ok(renderResults(session.username, q, results, searchHistory: history, csrfToken: csrfToken));
  } catch (e) {
    return _ok(renderError(session.username, 'Suche fehlgeschlagen: $e'));
  }
}

// â”€â”€ User Detail â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleUserDetail(Request req, Config config) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final dn = req.url.queryParameters['dn'] ?? '';
  final back = req.url.queryParameters['q'] ?? '';
  if (dn.isEmpty) return Response.found('/');
  try {
    final client = LdapClient(config, session);
    final user = await client.getUserDetails(dn);
    if (user == null) return _ok(renderError(session.username, 'User nicht gefunden.'));
    final maxPwdAgeDays = await client.getDomainMaxPwdAge();
    final clipboard = getClipboard(token);
    if (req.url.queryParameters['msg'] != null) {
      user['_msg'] = req.url.queryParameters['msg'];
    }
    final isOwnUser = dn.toLowerCase() == session.dn.toLowerCase();
    final readOnlySelf = getSessionSetting(token, 'readonly_self');
    final favs = getFavorites(token);
    final isFav = favs.any((f) => f.dn.toLowerCase() == dn.toLowerCase());
    final userNote = getUserNote(dn);
    return _ok(renderUserDetail(session.username, user, back,
        clipboard: clipboard, maxPwdAgeDays: maxPwdAgeDays,
        isOwnUser: isOwnUser, readOnlySelf: readOnlySelf, isFavorite: isFav,
        note: userNote, csrfToken: getCsrfToken(token)));
  } catch (e) {
    return _ok(renderError(session.username, 'User laden fehlgeschlagen: $e'));
  }
}

// â”€â”€ Bearbeiten â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleModify(Request req, Config config) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  final dn = params['dn'] ?? '';
  final attribute = params['attribute'] ?? '';
  final value = params['value'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty || attribute.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  if (!_allowedAttributes.contains(attribute)) return _ok(renderError(session.username, 'Attribut "$attribute" nicht erlaubt.'));
  if (dn.toLowerCase() == session.dn.toLowerCase() && getSessionSetting(token, 'readonly_self')) {
    return _ok(renderError(session.username, 'Nur-Lesen aktiv: eigener Account kann nicht bearbeitet werden.'));
  }
  try {
    await LdapClient(config, session).modifyUser(dn, attribute, value);
    auditLog(session.username, 'Attribut geändert: $attribute = $value', dn);
    final redirect = back.isNotEmpty
        ? '/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}'
        : '/';
    return Response.found(redirect);
  } catch (e) {
    return _ok(renderError(session.username, 'Änderung fehlgeschlagen: $e'));
  }
}

// â”€â”€ Foto â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handlePhotoUpload(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  final dn = params['dn'] ?? '';
  final b64 = params['photo_b64'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty || b64.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  if (b64.length > 700000) return Response.badRequest(body: 'Foto zu gross (max. 512 KB).');
  try {
    final bytes = Uint8List.fromList(base64Decode(b64));
    await LdapClient(config, session).updatePhoto(dn, bytes);
    auditLog(session.username, 'Foto hochgeladen', dn);
    return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return _ok(renderError(session.username, 'Foto-Upload fehlgeschlagen: $e'));
  }
}

Future<Response> handlePhotoDelete(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  final dn = params['dn'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  try {
    await LdapClient(config, session).deletePhoto(dn);
    auditLog(session.username, 'Foto gelöscht', dn);
    return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return _ok(renderError(session.username, 'Löschen fehlgeschlagen: $e'));
  }
}

// â”€â”€ Schnellansichten â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleLockedUsers(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getLockedUsers();
    return _ok(renderQuickUsers(session.username, 'Gesperrte Benutzer',
        'Benutzer mit aktivierter Kontosperre', users, extraCol: 'Entsperren', csrfToken: _csrfFor(req)));
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

Future<Response> handleDisabledUsers(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getDisabledUsers();
    return _ok(renderQuickUsers(session.username, 'Deaktivierte Benutzer',
        'Benutzer mit deaktiviertem Konto', users, extraCol: 'Aktivieren', csrfToken: _csrfFor(req)));
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

Future<Response> handlePwExpiring(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getUsersExpiringPasswords();
    return _ok(renderQuickUsers(session.username, 'Passwort läuft bald ab',
        'Passwort läuft in den nächsten 14 Tagen ab', users, extraCol: 'Tage'));
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

// â”€â”€ Gruppen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleGroups(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final q = (req.url.queryParameters['q'] ?? '').substring(0, ((req.url.queryParameters['q'] ?? '').length).clamp(0, 100));
  try {
    final client = LdapClient(config, session);
    final groups = await client.searchGroups(q);
    final ous = await client.getOUs();
    return _ok(renderGroups(session.username, q, groups, ous, csrfToken: _csrfFor(req)));
  } catch (e) {
    return _ok(renderError(session.username, 'Gruppen laden fehlgeschlagen: $e'));
  }
}

Future<Response> handleGroupMembers(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final groupDn = req.url.queryParameters['dn'] ?? '';
  final groupName = req.url.queryParameters['name'] ?? groupDn;
  if (groupDn.isEmpty) return Response.found('/groups');
  try {
    final members = await LdapClient(config, session).getGroupMembers(groupDn);
    return _ok(renderGroupMembers(session.username, groupName, groupDn, members));
  } catch (e) {
    return _ok(renderError(session.username, 'Mitglieder laden fehlgeschlagen: $e'));
  }
}

Future<Response> handleGroupAdd(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final userDn = params['user_dn'] ?? '';
  final groupName = params['group_name'] ?? '';
  final back = params['back'] ?? '';
  if (userDn.isEmpty || groupName.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    final groups = await LdapClient(config, session).findGroupByName(groupName);
    if (groups.isEmpty) {
      return _ok(renderError(session.username, 'Gruppe "$groupName" nicht gefunden.'));
    }
    if (groups.length == 1) {
      await LdapClient(config, session).addUserToGroup(userDn, groups.first['dn']);
      auditLog(session.username, 'Gruppe hinzugefügt: $groupName', userDn);
      return Response.found('/user?dn=${Uri.encodeComponent(userDn)}&q=${Uri.encodeComponent(back)}');
    }
    return _ok(renderGroupPicker(session.username, userDn, back, groups, 'Hinzufügen', _csrfFor(req)));
  } catch (e) {
    return _ok(renderError(session.username, 'Gruppe hinzufügen fehlgeschlagen: $e'));
  }
}

Future<Response> handleGroupAddConfirm(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final userDn = params['user_dn'] ?? '';
  final groupDn = params['group_dn'] ?? '';
  final back = params['back'] ?? '';
  if (userDn.isEmpty || groupDn.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    await LdapClient(config, session).addUserToGroup(userDn, groupDn);
    auditLog(session.username, 'Gruppe hinzugefügt', userDn, groupDn);
    return Response.found('/user?dn=${Uri.encodeComponent(userDn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return _ok(renderError(session.username, 'Hinzufügen fehlgeschlagen: $e'));
  }
}

Future<Response> handleGroupRemove(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final userDn = params['user_dn'] ?? '';
  final groupDn = params['group_dn'] ?? '';
  final back = params['back'] ?? '';
  if (userDn.isEmpty || groupDn.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    await LdapClient(config, session).removeUserFromGroup(userDn, groupDn);
    auditLog(session.username, 'Gruppe entfernt', userDn, groupDn);
    return Response.found('/user?dn=${Uri.encodeComponent(userDn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return _ok(renderError(session.username, 'Entfernen fehlgeschlagen: $e'));
  }
}

// â”€â”€ Gruppen Copy/Paste â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleGroupsCopy(Request req, Config config) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  final userDn = params['user_dn'] ?? '';
  final userName = params['user_name'] ?? '';
  final back = params['back'] ?? '';
  if (userDn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  try {
    final user = await LdapClient(config, session).getUserDetails(userDn);
    final groups = (user?['memberOf'] as List?)?.cast<String>() ?? [];
    setClipboard(token!, GroupClipboard(userName, userDn, groups));
    return Response.found('/user?dn=${Uri.encodeComponent(userDn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return _ok(renderError(session.username, 'Kopieren fehlgeschlagen: $e'));
  }
}

Future<Response> handleGroupsPaste(Request req, Config config) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final userDn = params['user_dn'] ?? '';
  final back = params['back'] ?? '';
  if (userDn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  final clipboard = getClipboard(token);
  if (clipboard == null) return _ok(renderError(session.username, 'Kein Gruppen-Clipboard vorhanden.'));

  final client = LdapClient(config, session);
  final errors = <String>[];
  for (final groupDn in clipboard.groupDns) {
    try {
      await client.addUserToGroup(userDn, groupDn);
    } catch (e) {
      errors.add(groupDn);
    }
  }
  if (errors.isNotEmpty) {
    return _ok(renderError(session.username,
        '${clipboard.groupDns.length - errors.length} von ${clipboard.groupDns.length} Gruppen übernommen. Fehler bei: ${errors.join(', ')}'));
  }
  auditLog(session.username, 'Gruppen eingefügt (${clipboard.groupDns.length})', userDn, 'von ${clipboard.sourceUsername}');
  return Response.found('/user?dn=${Uri.encodeComponent(userDn)}&q=${Uri.encodeComponent(back)}');
}

// â”€â”€ Bulk â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleBulkGroupAdd(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final userDns = (params['user_dns'] ?? '').split('\n').where((s) => s.isNotEmpty).toList();
  final groupName = params['group_name'] ?? '';
  final back = params['back'] ?? '';
  if (userDns.isEmpty || groupName.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    final client = LdapClient(config, session);
    final groups = await client.findGroupByName(groupName);
    if (groups.isEmpty) {
      return _ok(renderError(session.username, 'Gruppe "$groupName" nicht gefunden.'));
    }
    final groupDn = groups.first['dn'] as String;
    await client.addUsersToGroup(userDns, groupDn);
    auditLog(session.username, 'Bulk-Gruppe hinzugefügt: $groupName', '', '${userDns.length} User');
    return Response.found('/search?q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return _ok(renderError(session.username, 'Bulk-Aktion fehlgeschlagen: $e'));
  }
}

// â”€â”€ Passwort & Account â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handlePasswordReset(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final dn = params['dn'] ?? '';
  final password = params['password'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty || password.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  // Server-seitige Passwort-Komplexität prüfen
  if (!_isPasswordStrong(password)) {
    return _ok(renderError(session.username,
        'Passwort zu schwach. Mindestanforderungen: mind. 8 Zeichen, Gross- und Kleinbuchstaben, Zahl.'));
  }
  try {
    await LdapClient(config, session).resetPassword(dn, password);
    auditLog(session.username, 'Passwort zurückgesetzt', dn);
    return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}&msg=pw_ok');
  } catch (e) {
    return _ok(renderError(session.username, 'Passwort-Reset fehlgeschlagen: $e'));
  }
}

Future<Response> handleAccountToggle(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final dn = params['dn'] ?? '';
  final uac = int.tryParse(params['uac'] ?? '0') ?? 0;
  final disable = params['action'] == 'disable';
  final back = params['back'] ?? '';
  if (dn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  try {
    await LdapClient(config, session).setAccountDisabled(dn, uac, disable);
    auditLog(session.username, disable ? 'Account deaktiviert' : 'Account aktiviert', dn);
    return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return _ok(renderError(session.username, 'Account-Änderung fehlgeschlagen: $e'));
  }
}

Future<Response> handleAccountUnlock(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final dn = params['dn'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  try {
    await LdapClient(config, session).unlockAccount(dn);
    auditLog(session.username, 'Account entsperrt', dn);
    return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return _ok(renderError(session.username, 'Entsperren fehlgeschlagen: $e'));
  }
}

// â”€â”€ Export â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleExportSearch(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final q = (req.url.queryParameters['q'] ?? '').substring(0, ((req.url.queryParameters['q'] ?? '').length).clamp(0, 100));
  if (q.isEmpty) return Response.badRequest(body: 'Kein Suchbegriff');
  try {
    final users = await LdapClient(config, session).searchUsers(q);
    final csv = _toCsv(users);
    return Response.ok(csv, headers: {
      'content-type': 'text/csv; charset=utf-8',
      'content-disposition': 'attachment; filename="export_$q.csv"',
    });
  } catch (e) {
    return _ok(renderError(session.username, 'Export fehlgeschlagen: $e'));
  }
}

Future<Response> handleExportGroup(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final groupDn = req.url.queryParameters['dn'] ?? '';
  final groupName = req.url.queryParameters['name'] ?? 'gruppe';
  if (groupDn.isEmpty) return Response.badRequest(body: 'Kein Gruppen-DN');
  try {
    final members = await LdapClient(config, session).getGroupMembers(groupDn);
    return Response.ok(_toCsv(members), headers: {
      'content-type': 'text/csv; charset=utf-8',
      'content-disposition': 'attachment; filename="export_$groupName.csv"',
    });
  } catch (e) {
    return _ok(renderError(session.username, 'Export fehlgeschlagen: $e'));
  }
}

// â”€â”€ Einstellungen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Response handleSettingsPage(Request req) {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final settings = getSessionSettings(token);
  final msg = req.url.queryParameters['msg'];
  return _ok(renderSettings(session.username, settings, msg: msg, csrfToken: _csrfFor(req)));
}

Future<Response> handleSettingsPost(Request req) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  final key = params['key'] ?? '';
  if (key.isNotEmpty && token != null) {
    toggleSessionSetting(token, key);
  }
  return Response.found('/settings');
}

// â”€â”€ OU Browser â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleOuBrowser(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final ous = await LdapClient(config, session).getOUs();
    return _ok(renderOuBrowser(session.username, ous));
  } catch (e) {
    return _ok(renderError(session.username, 'OU-Browser fehlgeschlagen: $e'));
  }
}

Future<Response> handleOuUsers(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final ouDn = req.url.queryParameters['dn'] ?? '';
  final subtree = req.url.queryParameters['subtree'] == '1';
  if (ouDn.isEmpty) return Response.found('/ou');
  try {
    final users = await LdapClient(config, session).getUsersInOu(ouDn, subtree: subtree);
    return _ok(renderOuUsers(session.username, ouDn, users, subtree: subtree));
  } catch (e) {
    return _ok(renderError(session.username, 'OU-User laden fehlgeschlagen: $e'));
  }
}

// â”€â”€ Feature 5: User verschieben â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleMoveUserForm(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final dn = req.url.queryParameters['dn'] ?? '';
  final back = req.url.queryParameters['q'] ?? '';
  if (dn.isEmpty) return Response.found('/');
  try {
    final client = LdapClient(config, session);
    final user = await client.getUserDetails(dn);
    if (user == null) return _ok(renderError(session.username, 'User nicht gefunden.'));
    final ous = await client.getOUs();
    return _ok(renderMoveForm(session.username, user, ous, config.baseDn, back, csrfToken: _csrfFor(req)));
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

Future<Response> handleMoveUserPost(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final dn = params['dn'] ?? '';
  final targetOu = params['target_ou'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty || targetOu.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    await LdapClient(config, session).moveUser(dn, targetOu);
    final rdn = _firstRdn(dn);
    final newDn = '$rdn,$targetOu';
    auditLog(session.username, 'User verschoben', newDn, 'nach: $targetOu');
    return Response.found('/user?dn=${Uri.encodeComponent(newDn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return _ok(renderError(session.username, 'Verschieben fehlgeschlagen: $e'));
  }
}

// â”€â”€ Feature 6: Gruppen erstellen + löschen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleCreateGroup(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final name = params['name'] ?? '';
  final ouDn = params['ou_dn'] ?? '';
  final description = params['description'] ?? '';
  if (name.isEmpty || ouDn.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    final newDn = await LdapClient(config, session).createGroup(name, ouDn, description: description.isNotEmpty ? description : null);
    auditLog(session.username, 'Gruppe erstellt', newDn);
    return Response.found('/groups');
  } catch (e) {
    return _ok(renderError(session.username, 'Gruppe erstellen fehlgeschlagen: $e'));
  }
}

Future<Response> handleDeleteGroup(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) != UserRole.admin) return _ok(renderError(session.username, 'Nur Admins dürfen Gruppen löschen.'));
  final groupDn = params['group_dn'] ?? '';
  if (groupDn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  try {
    await LdapClient(config, session).deleteGroup(groupDn);
    auditLog(session.username, 'Gruppe gelöscht', groupDn);
    return Response.found('/groups');
  } catch (e) {
    return _ok(renderError(session.username, 'Gruppe löschen fehlgeschlagen: $e'));
  }
}

// â”€â”€ Feature 7: Bulk-Aktionen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleBulkUnlock(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final userDns = (params['user_dns'] ?? '').split('\n').where((s) => s.isNotEmpty).toList();
  final back = params['back'] ?? '';
  if (userDns.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    await LdapClient(config, session).bulkUnlock(userDns);
    auditLog(session.username, 'Bulk-Entsperren', '', '${userDns.length} User');
    return Response.found('/search?q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return _ok(renderError(session.username, 'Bulk-Entsperren fehlgeschlagen: $e'));
  }
}

Future<Response> handleBulkDisable(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final userDns = (params['user_dns'] ?? '').split('\n').where((s) => s.isNotEmpty).toList();
  final action = params['action'] ?? 'disable';
  final back = params['back'] ?? '';
  if (userDns.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    final disable = action == 'disable';
    await LdapClient(config, session).bulkSetDisabled(userDns, disable);
    auditLog(session.username, disable ? 'Bulk-Deaktivieren' : 'Bulk-Aktivieren', '', '${userDns.length} User');
    return Response.found('/search?q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return _ok(renderError(session.username, 'Bulk-Aktion fehlgeschlagen: $e'));
  }
}

// â”€â”€ Audit Log â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Response handleAuditLog(Request req) {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  return _ok(renderAuditLog(session.username, getAuditLog()));
}

// â”€â”€ User kopieren â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleCloneForm(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final dn = req.url.queryParameters['dn'] ?? '';
  final back = req.url.queryParameters['q'] ?? '';
  if (dn.isEmpty) return Response.found('/');
  try {
    final user = await LdapClient(config, session).getUserDetails(dn);
    if (user == null) return _ok(renderError(session.username, 'User nicht gefunden.'));
    return _ok(renderCloneForm(session.username, user, back, csrfToken: _csrfFor(req)));
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

Future<Response> handleClonePost(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) != UserRole.admin) return _ok(renderError(session.username, 'Nur Admins dürfen User erstellen.'));
  final templateDn = params['template_dn'] ?? '';
  final parentOuDn = params['parent_ou'] ?? '';
  final givenName = params['givenName'] ?? '';
  final sn = params['sn'] ?? '';
  final sam = params['sAMAccountName'] ?? '';
  final password = params['password'] ?? '';
  final mail = params['mail'] ?? '';
  final department = params['department'] ?? '';
  final title = params['title'] ?? '';
  final mustChange = params['must_change'] == '1';
  final back = params['back'] ?? '';

  if (givenName.isEmpty || sn.isEmpty || sam.isEmpty || password.isEmpty || parentOuDn.isEmpty) {
    return _ok(renderError(session.username, 'Pflichtfelder fehlen.'));
  }

  try {
    final client = LdapClient(config, session);
    final newDn = await client.createUser(
      parentOuDn: parentOuDn,
      givenName: givenName,
      sn: sn,
      sAMAccountName: sam,
      password: password,
      mail: mail.isNotEmpty ? mail : null,
      department: department.isNotEmpty ? department : null,
      title: title.isNotEmpty ? title : null,
    );

    if (templateDn.isNotEmpty) {
      final template = await client.getUserDetails(templateDn);
      final groups = (template?['memberOf'] as List?)?.cast<String>() ?? [];
      for (final groupDn in groups) {
        try { await client.addUserToGroup(newDn, groupDn); } catch (_) {}
      }
    }

    if (mustChange) {
      try { await client.setPasswordMustChange(newDn); } catch (_) {}
    }

    auditLog(session.username, 'User erstellt (Kopie)', newDn, 'Vorlage: $templateDn');
    return Response.found('/user?dn=${Uri.encodeComponent(newDn)}&q=${Uri.encodeComponent(back)}&msg=clone_ok');
  } catch (e) {
    return _ok(renderError(session.username, 'User erstellen fehlgeschlagen: $e'));
  }
}

// â”€â”€ Account-Optionen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handlePasswordMustChange(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final dn = params['dn'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  try {
    await LdapClient(config, session).setPasswordMustChange(dn);
    auditLog(session.username, 'Passwort-Pflicht bei Anmeldung gesetzt', dn);
    return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

Future<Response> handlePwdNeverExpires(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final dn = params['dn'] ?? '';
  final uac = int.tryParse(params['uac'] ?? '0') ?? 0;
  final enable = params['enable'] == '1';
  final back = params['back'] ?? '';
  if (dn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  try {
    await LdapClient(config, session).setPwdNeverExpires(dn, uac, enable);
    auditLog(session.username, enable ? 'Passwort läuft nie ab: ein' : 'Passwort läuft nie ab: aus', dn);
    return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

Future<Response> handleAccountExpiry(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final dn = params['dn'] ?? '';
  final expiryStr = params['expiry'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  try {
    final expiry = expiryStr.isNotEmpty ? DateTime.tryParse(expiryStr) : null;
    await LdapClient(config, session).setAccountExpiry(dn, expiry);
    auditLog(session.username, 'Ablaufdatum gesetzt', dn, expiryStr.isNotEmpty ? expiryStr : 'kein Ablauf');
    return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

// â”€â”€ Inaktive User â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleInactiveUsers(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getInactiveUsers();
    return _ok(renderInactiveUsers(session.username, users));
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

// â”€â”€ Service-Accounts â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleServiceAccounts(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getServiceAccounts();
    return _ok(renderServiceAccounts(session.username, users));
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

// â”€â”€ Accounts ohne E-Mail â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleUsersNoEmail(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getUsersWithoutEmail();
    return _ok(renderUsersNoEmail(session.username, users));
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

// â”€â”€ Passwort-Policy â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handlePasswordPolicy(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final policy = await LdapClient(config, session).getPasswordPolicy();
    return _ok(renderPasswordPolicy(session.username, policy));
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

// â”€â”€ User-Vergleich â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleUserCompare(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final dnA = req.url.queryParameters['a'] ?? '';
  var dnB = req.url.queryParameters['b'] ?? '';
  if (dnA.isEmpty) return Response.found('/');
  try {
    final client = LdapClient(config, session);
    final userA = await client.getUserDetails(dnA);
    if (userA == null) return _ok(renderError(session.username, 'User A nicht gefunden.'));
    if (dnB.isEmpty) {
      return _ok(renderUserCompareForm(session.username, userA));
    }
    // Wenn kein DN (kein Komma), per Name/Benutzername suchen
    if (!dnB.contains(',')) {
      final results = await client.searchUsers(dnB);
      if (results.isEmpty) return _ok(renderError(session.username, 'Benutzer "$dnB" nicht gefunden.'));
      dnB = results.first['dn'] as String;
    }
    final userB = await client.getUserDetails(dnB);
    if (userB == null) return _ok(renderError(session.username, 'User B nicht gefunden.'));
    return _ok(renderUserCompare(session.username, userA, userB));
  } catch (e) {
    return _ok(renderError(session.username, 'Vergleich fehlgeschlagen: $e'));
  }
}

// â”€â”€ Verschachtelte Gruppen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleEffectiveGroups(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final dn = req.url.queryParameters['dn'] ?? '';
  if (dn.isEmpty) return Response.found('/');
  try {
    final client = LdapClient(config, session);
    final user = await client.getUserDetails(dn);
    final groups = await client.getEffectiveGroups(dn);
    return _ok(renderEffectiveGroups(session.username, user, dn, groups));
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

// â”€â”€ CSV Bulk-Update â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€


// â”€â”€ Computer-Browser â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleComputers(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final computers = await LdapClient(config, session).getComputers();
    return _ok(renderComputers(session.username, computers, csrfToken: _csrfFor(req)));
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

Future<Response> handleComputerMoveLager(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  if (_role(req) == UserRole.readonly) return _ok(renderError(session.username, 'Keine Berechtigung (readonly).'));
  final dn = params['dn'] ?? '';
  final targetOu = params['target_ou'] ?? '';
  if (dn.isEmpty || targetOu.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    final client = LdapClient(config, session);
    await client.moveUser(dn, targetOu);
    final rdn = dn.substring(0, dn.indexOf(','));
    final newDn = '$rdn,$targetOu';
    auditLog(session.username, 'Computer ins Lager verschoben', newDn, 'von: $dn');
    // Gerät direkt deaktivieren (UAC Bit 2 setzen)
    try {
      await client.setAccountDisabled(newDn, 4096, true);
      auditLog(session.username, 'Computer deaktiviert (Lager)', newDn, '');
    } catch (_) {}
    return Response.found('/computers');
  } catch (e) {
    return _ok(renderError(session.username, 'Verschieben fehlgeschlagen: $e'));
  }
}

// â”€â”€ Erweiterte Suche â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleAdvancedSearch(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = req.url.queryParameters;
  final hasSearch = params.isNotEmpty && (params['name'] != null || params['department'] != null ||
      params['ou'] != null || params['status'] != null);
  try {
    final client = LdapClient(config, session);
    final ous = await client.getOUs();
    List<Map<String, dynamic>>? results;
    if (hasSearch) {
      results = await client.advancedSearch(
        name: params['name'],
        department: params['department'],
        ouDn: params['ou'],
        status: params['status'] ?? 'all',
      );
    }
    return _ok(renderAdvancedSearch(session.username, ous, params, results));
  } catch (e) {
    return _ok(renderError(session.username, 'Suche fehlgeschlagen: $e'));
  }
}

// â”€â”€ Favoriten â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleFavoriteToggle(Request req) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null || token == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  final dn = params['dn'] ?? '';
  final name = params['name'] ?? dn;
  final back = params['back'] ?? '';
  final from = params['from'] ?? '';
  if (dn.isNotEmpty) {
    toggleFavorite(token, dn, name);
  }
  if (from.isNotEmpty) return Response.found(from);
  final redirect = back.isNotEmpty
      ? '/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}'
      : '/user?dn=${Uri.encodeComponent(dn)}';
  return Response.found(redirect);
}

// â”€â”€ Feature 1: Org-Chart â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleOrgChart(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final dn = req.url.queryParameters['dn'] ?? '';
  final name = req.url.queryParameters['name'] ?? '';

  if (dn.isEmpty && name.isEmpty) {
    return _ok(renderOrgChartForm(session.username));
  }

  if (dn.isEmpty && name.isNotEmpty) {
    final client = LdapClient(config, session);
    final results = await client.searchUsers(name);
    if (results.isEmpty) {
      return _ok(renderOrgChartForm(session.username, error: 'Kein Benutzer gefunden: "$name"'));
    }
    if (results.length == 1) {
      return Response.found('/orgchart?dn=${Uri.encodeComponent(results.first['dn'] as String)}');
    }
    return _ok(renderOrgChartPicker(session.username, name, results));
  }
  try {
    final client = LdapClient(config, session);
    final user = await client.getOrgChartUser(dn);
    if (user == null) return _ok(renderError(session.username, 'User nicht gefunden.'));

    // Manager laden (max 2 Ebenen hoch)
    final managers = <Map<String, dynamic>>[];
    var currentManagerDn = user['manager']?.toString() ?? '';
    for (var i = 0; i < 2 && currentManagerDn.isNotEmpty; i++) {
      final mgr = await client.getOrgChartUser(currentManagerDn);
      if (mgr == null) break;
      managers.insert(0, mgr);
      currentManagerDn = mgr['manager']?.toString() ?? '';
    }

    // Direkte Berichte laden
    final directReportDns = (user['directReports'] as List?)?.cast<String>() ?? [];
    final reports = <Map<String, dynamic>>[];
    for (final rdn in directReportDns.take(20)) {
      final r = await client.getOrgChartUser(rdn);
      if (r != null) reports.add(r);
    }

    return _ok(renderOrgChart(session.username, user, managers, reports));
  } catch (e) {
    return _ok(renderError(session.username, 'Org-Chart laden fehlgeschlagen: $e'));
  }
}

// â”€â”€ Feature 2: Telefonverzeichnis â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleDirectory(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getPhoneDirectory();
    return _ok(renderDirectory(session.username, users));
  } catch (e) {
    return _ok(renderError(session.username, 'Verzeichnis laden fehlgeschlagen: $e'));
  }
}

Future<Response> handleExportDirectory(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getPhoneDirectory();
    final buf = StringBuffer()..writeln('Name,Benutzername,Abteilung,Telefon,Mobil,E-Mail');
    for (final u in users) {
      String e(String k) => '"${(u[k] ?? '').toString().replaceAll('"', '""')}"';
      buf.writeln('${e('cn')},${e('sAMAccountName')},${e('department')},${e('telephoneNumber')},${e('mobile')},${e('mail')}');
    }
    return Response.ok(buf.toString(), headers: {
      'content-type': 'text/csv; charset=utf-8',
      'content-disposition': 'attachment; filename="telefonverzeichnis.csv"',
    });
  } catch (e) {
    return _ok(renderError(session.username, 'Export fehlgeschlagen: $e'));
  }
}

// â”€â”€ Feature 3: Abteilungs-Statistik â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleDeptStats(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final allUsers = await LdapClient(config, session).searchUsers('');
    final deptMap = <String, int>{};
    for (final u in allUsers) {
      final uac = int.tryParse(u['userAccountControl']?.toString() ?? '0') ?? 0;
      if ((uac & 2) != 0) continue; // skip disabled
      final dept = (u['department']?.toString() ?? '').trim();
      final key = dept.isEmpty ? 'Ohne Abteilung' : dept;
      deptMap[key] = (deptMap[key] ?? 0) + 1;
    }
    final sorted = deptMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _ok(renderDeptStats(session.username, sorted.take(20).toList()));
  } catch (e) {
    return _ok(renderError(session.username, 'Statistik laden fehlgeschlagen: $e'));
  }
}

// â”€â”€ Feature 4: Bulk PW-Reset â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€


// â”€â”€ Feature 5: Ablaufende Accounts â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleExpiringAccounts(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getExpiringAccounts();
    return _ok(renderExpiringAccounts(session.username, users));
  } catch (e) {
    return _ok(renderError(session.username, 'Fehler: $e'));
  }
}

// â”€â”€ Feature 8: User-Notizen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleGetNote(Request req) async {
  final session = _session(req);
  if (session == null) return Response.unauthorized(jsonEncode({'error': 'Nicht angemeldet'}),
      headers: {'content-type': 'application/json'});
  final dn = req.url.queryParameters['dn'] ?? '';
  if (dn.isEmpty) return Response.ok(jsonEncode({'text': ''}), headers: {'content-type': 'application/json'});
  final note = getUserNote(dn);
  return Response.ok(
    jsonEncode({'text': note?['text'] ?? '', 'updatedAt': note?['updatedAt'] ?? '', 'updatedBy': note?['updatedBy'] ?? ''}),
    headers: {'content-type': 'application/json'},
  );
}

Future<Response> handleSetNote(Request req) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  final dn = params['dn'] ?? '';
  final text = params['text'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  setUserNote(dn, text, session.username);
  auditLog(session.username, 'Notiz gespeichert', dn);
  return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}&msg=note_ok');
}

String _toCsv(List<Map<String, dynamic>> users) {
  final fields = ['cn', 'sAMAccountName', 'mail', 'telephoneNumber', 'department', 'title', 'dn'];
  final labels = ['Name', 'Benutzername', 'E-Mail', 'Telefon', 'Abteilung', 'Titel', 'DN'];
  final buf = StringBuffer()..writeln(labels.join(';'));
  for (final user in users) {
    buf.writeln(fields.map((f) => '"${(user[f] ?? '').toString().replaceAll('"', '""')}"').join(';'));
  }
  return buf.toString();
}

// â”€â”€ Audit-Log CSV-Export â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleExportAudit(Request req) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final entries = getAuditLog();
  final buf = StringBuffer()..writeln('Zeitstempel,Benutzer,Aktion,Ziel,Details');
  for (final e in entries) {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    buf.writeln('${esc(e.timestamp.toIso8601String())},${esc(e.actor)},${esc(e.action)},${esc(e.targetDn)},${esc(e.details)}');
  }
  return Response.ok(buf.toString(), headers: {
    'content-type': 'text/csv; charset=utf-8',
    'content-disposition': 'attachment; filename="audit.csv"',
  });
}

// â”€â”€ Alle User exportieren â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleExportAllUsers(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getAllUsersForExport();
    final fields = ['cn', 'sAMAccountName', 'mail', 'department', 'title',
                    'telephoneNumber', 'mobile', 'userAccountControl', 'lockoutTime',
                    'lastLogonTimestamp', 'distinguishedName'];
    final buf = StringBuffer()..writeln(fields.join(';'));
    for (final u in users) {
      buf.writeln(fields.map((f) => '"${(u[f] ?? '').toString().replaceAll('"', '""')}"').join(';'));
    }
    final date = DateTime.now().toIso8601String().substring(0, 10);
    return Response.ok(buf.toString(), headers: {
      'content-type': 'text/csv; charset=utf-8',
      'content-disposition': 'attachment; filename="users_$date.csv"',
    });
  } catch (e) {
    return _ok(renderError(session.username, 'Export fehlgeschlagen: $e'));
  }
}

// â”€â”€ Config UI â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Response handleConfigPage(Request req, Config config) {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  if (_role(req) != UserRole.admin) {
    return _ok(renderError(session.username, 'Nur Admins dürfen die Konfiguration ändern.'));
  }
  final saved = req.url.queryParameters['saved'] == '1';
  return _ok(renderConfigPage(session.username, config, saved: saved, csrfToken: _csrfFor(req)));
}

Future<Response> handleConfigPost(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  if (_role(req) != UserRole.admin) {
    return _ok(renderError(session.username, 'Nur Admins dürfen die Konfiguration ändern.'));
  }
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  final updates = <String, String>{};
  if ((params['AD_SERVER'] ?? '').isNotEmpty)   updates['AD_SERVER']   = params['AD_SERVER']!;
  if ((params['AD_PORT'] ?? '').isNotEmpty)     updates['AD_PORT']     = params['AD_PORT']!;
  if ((params['AD_SSL'] ?? '').isNotEmpty)      updates['AD_SSL']      = params['AD_SSL']!;
  if ((params['AD_USER'] ?? '').isNotEmpty)     updates['AD_USER']     = params['AD_USER']!;
  if ((params['AD_PASSWORD'] ?? '').isNotEmpty) updates['AD_PASSWORD'] = params['AD_PASSWORD']!;
  if ((params['BASE_DN'] ?? '').isNotEmpty)     updates['BASE_DN']     = params['BASE_DN']!;
  config.save(updates);
  auditLog(session.username, 'Konfiguration geändert', '');
  return Response.found('/config?saved=1');
}

// â”€â”€ Health-Check â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleHealth(Request req, Config config) async {
  try {
    final conn = LdapConnection(
      host: config.server,
      ssl: config.useSsl,
      port: config.port,
      bindDN: DN(config.bindUser),
      password: config.bindPassword,
      badCertificateHandler: (cert) => true,
    );
    await conn.open().timeout(const Duration(seconds: 5));
    await conn.bind().timeout(const Duration(seconds: 5));
    await conn.close();
    return Response.ok('{"status":"ok","ldap":"connected"}',
        headers: {'content-type': 'application/json'});
  } catch (_) {
    return Response(503, body: '{"status":"error","ldap":"unreachable"}',
        headers: {'content-type': 'application/json'});
  }
}

// â”€â”€ Rollen-Verwaltung â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Response handleRolesPage(Request req) {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  if (_role(req) != UserRole.admin) {
    return _ok(renderError(session.username, 'Nur Admins dürfen Rollen verwalten.'));
  }
  final roles = getAllRoles();
  return _ok(renderRolesPage(session.username, roles, csrfToken: _csrfFor(req)));
}

Future<Response> handleRolesPost(Request req) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  if (_role(req) != UserRole.admin) {
    return _ok(renderError(session.username, 'Nur Admins dürfen Rollen verwalten.'));
  }
  final params = Uri.splitQueryString(await req.readAsString());
  if (!_validCsrf(req, params)) return _forbidden(session.username);
  // Parse user=role pairs — eigener Account bleibt immer Admin
  final newRoles = <String, UserRole>{};
  for (final e in params.entries) {
    if (e.key == '_csrf') continue;
    final isOwnAccount = e.key.toLowerCase() == session.username.toLowerCase();
    newRoles[e.key] = isOwnAccount
        ? UserRole.admin
        : switch (e.value) {
            'operator' => UserRole.operator,
            'readonly'  => UserRole.readonly,
            _ => UserRole.admin,
          };
  }
  saveRoles(newRoles);
  auditLog(session.username, 'Rollen gespeichert', '', '${newRoles.length} Einträge');
  return Response.found('/admin/roles');
}

