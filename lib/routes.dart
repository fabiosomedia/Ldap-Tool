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

// Passwort-KomplexitÃ¤t prÃ¼fen (server-seitig)
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
};
SessionData? _session(Request req) => getSession(extractToken(req.headers['cookie']));

// â”€â”€ Auth â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Response handleLoginPage(Request req) =>
    Response.ok(renderLogin(null), headers: _html);

Future<Response> handleLoginPost(Request req, Config config) async {
  final params = Uri.splitQueryString(await req.readAsString());
  // Login braucht keinen CSRF-Check (Session existiert noch nicht)
  final (error, data) = await tryLogin(config, params['username'] ?? '', params['password'] ?? '');
  if (error != null || data == null) {
    return Response.ok(renderLogin(error ?? 'Unbekannter Fehler.'), headers: _html);
  }
  return Response.found('/', headers: {
    'set-cookie': 'session=${createSession(data)}; HttpOnly; Path=/; SameSite=Lax; Max-Age=86400',
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
  return Response.ok(renderIndex(session?.username ?? '', searchHistory: history), headers: _html);
}

Future<Response> handleDashboard(Request req, Config config) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final csrfToken = getCsrfToken(token);
  try {
    final stats = await LdapClient(config, session).getDashboardStats();
    final favs = getFavorites(token);
    return Response.ok(renderDashboard(session.username, stats, getAuditLog().take(6).toList(), favorites: favs, csrfToken: csrfToken), headers: _html);
  } catch (e) {
    return Response.ok(renderDashboard(session.username, {}, [], favorites: [], csrfToken: csrfToken), headers: _html);
  }
}

// â”€â”€ Suche â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleSearch(Request req, Config config) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final q = req.url.queryParameters['q'] ?? '';
  if (q.isNotEmpty && token != null) {
    addSearchHistory(token, q);
  }
  try {
    final results = await LdapClient(config, session).searchUsers(q);
    final history = getSearchHistory(token);
    if (q.isEmpty && results.isEmpty) return Response.ok(renderIndex(session.username, searchHistory: history), headers: _html);
    return Response.ok(renderResults(session.username, q, results, searchHistory: history), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Suche fehlgeschlagen: $e'), headers: _html);
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
    if (user == null) return Response.ok(renderError(session.username, 'User nicht gefunden.'), headers: _html);
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
    return Response.ok(renderUserDetail(session.username, user, back,
        clipboard: clipboard, maxPwdAgeDays: maxPwdAgeDays,
        isOwnUser: isOwnUser, readOnlySelf: readOnlySelf, isFavorite: isFav,
        note: userNote), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'User laden fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Bearbeiten â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleModify(Request req, Config config) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
  final dn = params['dn'] ?? '';
  final attribute = params['attribute'] ?? '';
  final value = params['value'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty || attribute.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  if (dn.toLowerCase() == session.dn.toLowerCase() && getSessionSetting(token, 'readonly_self')) {
    return Response.ok(renderError(session.username, 'Nur-Lesen aktiv: eigener Account kann nicht bearbeitet werden.'), headers: _html);
  }
  try {
    await LdapClient(config, session).modifyUser(dn, attribute, value);
    auditLog(session.username, 'Attribut geÃ¤ndert: $attribute = $value', dn);
    final redirect = back.isNotEmpty
        ? '/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}'
        : '/';
    return Response.found(redirect);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Ã„nderung fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Foto â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handlePhotoUpload(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  final dn = params['dn'] ?? '';
  final b64 = params['photo_b64'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty || b64.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    final bytes = Uint8List.fromList(base64Decode(b64));
    await LdapClient(config, session).updatePhoto(dn, bytes);
    auditLog(session.username, 'Foto hochgeladen', dn);
    return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return Response.ok(renderError(session.username, 'Foto-Upload fehlgeschlagen: $e'), headers: _html);
  }
}

Future<Response> handlePhotoDelete(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  final dn = params['dn'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  try {
    await LdapClient(config, session).deletePhoto(dn);
    auditLog(session.username, 'Foto gelÃ¶scht', dn);
    return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return Response.ok(renderError(session.username, 'LÃ¶schen fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Schnellansichten â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleLockedUsers(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getLockedUsers();
    return Response.ok(renderQuickUsers(session.username, 'Gesperrte Benutzer',
        'Benutzer mit aktivierter Kontosperre', users, extraCol: 'Entsperren'), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

Future<Response> handleDisabledUsers(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getDisabledUsers();
    return Response.ok(renderQuickUsers(session.username, 'Deaktivierte Benutzer',
        'Benutzer mit deaktiviertem Konto', users, extraCol: 'Aktivieren'), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

Future<Response> handlePwExpiring(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getUsersExpiringPasswords();
    return Response.ok(renderQuickUsers(session.username, 'Passwort lÃ¤uft bald ab',
        'Passwort lÃ¤uft in den nÃ¤chsten 14 Tagen ab', users, extraCol: 'Tage'), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

// â”€â”€ Gruppen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleGroups(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final q = req.url.queryParameters['q'] ?? '';
  try {
    final client = LdapClient(config, session);
    final groups = await client.searchGroups(q);
    final ous = await client.getOUs();
    return Response.ok(renderGroups(session.username, q, groups, ous), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Gruppen laden fehlgeschlagen: $e'), headers: _html);
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
    return Response.ok(renderGroupMembers(session.username, groupName, groupDn, members), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Mitglieder laden fehlgeschlagen: $e'), headers: _html);
  }
}

Future<Response> handleGroupAdd(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
  final userDn = params['user_dn'] ?? '';
  final groupName = params['group_name'] ?? '';
  final back = params['back'] ?? '';
  if (userDn.isEmpty || groupName.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    final groups = await LdapClient(config, session).findGroupByName(groupName);
    if (groups.isEmpty) {
      return Response.ok(renderError(session.username, 'Gruppe "$groupName" nicht gefunden.'), headers: _html);
    }
    if (groups.length == 1) {
      await LdapClient(config, session).addUserToGroup(userDn, groups.first['dn']);
      auditLog(session.username, 'Gruppe hinzugefÃ¼gt: $groupName', userDn);
      return Response.found('/user?dn=${Uri.encodeComponent(userDn)}&q=${Uri.encodeComponent(back)}');
    }
    return Response.ok(renderGroupPicker(session.username, userDn, back, groups, 'HinzufÃ¼gen'), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Gruppe hinzufÃ¼gen fehlgeschlagen: $e'), headers: _html);
  }
}

Future<Response> handleGroupAddConfirm(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
  final userDn = params['user_dn'] ?? '';
  final groupDn = params['group_dn'] ?? '';
  final back = params['back'] ?? '';
  if (userDn.isEmpty || groupDn.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    await LdapClient(config, session).addUserToGroup(userDn, groupDn);
    auditLog(session.username, 'Gruppe hinzugefÃ¼gt', userDn, groupDn);
    return Response.found('/user?dn=${Uri.encodeComponent(userDn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return Response.ok(renderError(session.username, 'HinzufÃ¼gen fehlgeschlagen: $e'), headers: _html);
  }
}

Future<Response> handleGroupRemove(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
  final userDn = params['user_dn'] ?? '';
  final groupDn = params['group_dn'] ?? '';
  final back = params['back'] ?? '';
  if (userDn.isEmpty || groupDn.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    await LdapClient(config, session).removeUserFromGroup(userDn, groupDn);
    auditLog(session.username, 'Gruppe entfernt', userDn, groupDn);
    return Response.found('/user?dn=${Uri.encodeComponent(userDn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return Response.ok(renderError(session.username, 'Entfernen fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Gruppen Copy/Paste â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleGroupsCopy(Request req, Config config) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
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
    return Response.ok(renderError(session.username, 'Kopieren fehlgeschlagen: $e'), headers: _html);
  }
}

Future<Response> handleGroupsPaste(Request req, Config config) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
  final userDn = params['user_dn'] ?? '';
  final back = params['back'] ?? '';
  if (userDn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  final clipboard = getClipboard(token);
  if (clipboard == null) return Response.ok(renderError(session.username, 'Kein Gruppen-Clipboard vorhanden.'), headers: _html);

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
    return Response.ok(renderError(session.username,
        '${clipboard.groupDns.length - errors.length} von ${clipboard.groupDns.length} Gruppen Ã¼bernommen. Fehler bei: ${errors.join(', ')}'), headers: _html);
  }
  auditLog(session.username, 'Gruppen eingefÃ¼gt (${clipboard.groupDns.length})', userDn, 'von ${clipboard.sourceUsername}');
  return Response.found('/user?dn=${Uri.encodeComponent(userDn)}&q=${Uri.encodeComponent(back)}');
}

// â”€â”€ Bulk â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleBulkGroupAdd(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
  final userDns = (params['user_dns'] ?? '').split('\n').where((s) => s.isNotEmpty).toList();
  final groupName = params['group_name'] ?? '';
  final back = params['back'] ?? '';
  if (userDns.isEmpty || groupName.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    final client = LdapClient(config, session);
    final groups = await client.findGroupByName(groupName);
    if (groups.isEmpty) {
      return Response.ok(renderError(session.username, 'Gruppe "$groupName" nicht gefunden.'), headers: _html);
    }
    final groupDn = groups.first['dn'] as String;
    await client.addUsersToGroup(userDns, groupDn);
    auditLog(session.username, 'Bulk-Gruppe hinzugefÃ¼gt: $groupName', '', '${userDns.length} User');
    return Response.found('/search?q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return Response.ok(renderError(session.username, 'Bulk-Aktion fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Passwort & Account â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handlePasswordReset(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
  final dn = params['dn'] ?? '';
  final password = params['password'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty || password.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  // Server-seitige Passwort-KomplexitÃ¤t prÃ¼fen
  if (!_isPasswordStrong(password)) {
    return Response.ok(renderError(session.username,
        'Passwort zu schwach. Mindestanforderungen: mind. 8 Zeichen, Gross- und Kleinbuchstaben, Zahl.'), headers: _html);
  }
  try {
    await LdapClient(config, session).resetPassword(dn, password);
    auditLog(session.username, 'Passwort zurÃ¼ckgesetzt', dn);
    return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}&msg=pw_ok');
  } catch (e) {
    return Response.ok(renderError(session.username, 'Passwort-Reset fehlgeschlagen: $e'), headers: _html);
  }
}

Future<Response> handleAccountToggle(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
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
    return Response.ok(renderError(session.username, 'Account-Ã„nderung fehlgeschlagen: $e'), headers: _html);
  }
}

Future<Response> handleAccountUnlock(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
  final dn = params['dn'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  try {
    await LdapClient(config, session).unlockAccount(dn);
    auditLog(session.username, 'Account entsperrt', dn);
    return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return Response.ok(renderError(session.username, 'Entsperren fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Export â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleExportSearch(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final q = req.url.queryParameters['q'] ?? '';
  if (q.isEmpty) return Response.badRequest(body: 'Kein Suchbegriff');
  try {
    final users = await LdapClient(config, session).searchUsers(q);
    final csv = _toCsv(users);
    return Response.ok(csv, headers: {
      'content-type': 'text/csv; charset=utf-8',
      'content-disposition': 'attachment; filename="export_$q.csv"',
    });
  } catch (e) {
    return Response.ok(renderError(session.username, 'Export fehlgeschlagen: $e'), headers: _html);
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
    return Response.ok(renderError(session.username, 'Export fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Einstellungen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Response handleSettingsPage(Request req) {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final settings = getSessionSettings(token);
  return Response.ok(renderSettings(session.username, settings), headers: _html);
}

Future<Response> handleSettingsPost(Request req) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
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
    return Response.ok(renderOuBrowser(session.username, ous), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'OU-Browser fehlgeschlagen: $e'), headers: _html);
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
    return Response.ok(renderOuUsers(session.username, ouDn, users, subtree: subtree), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'OU-User laden fehlgeschlagen: $e'), headers: _html);
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
    if (user == null) return Response.ok(renderError(session.username, 'User nicht gefunden.'), headers: _html);
    final ous = await client.getOUs();
    return Response.ok(renderMoveForm(session.username, user, ous, back), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

Future<Response> handleMoveUserPost(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
  final dn = params['dn'] ?? '';
  final targetOu = params['target_ou'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty || targetOu.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    await LdapClient(config, session).moveUser(dn, targetOu);
    final rdn = dn.substring(0, dn.indexOf(','));
    final newDn = '$rdn,$targetOu';
    auditLog(session.username, 'User verschoben', newDn, 'nach: $targetOu');
    return Response.found('/user?dn=${Uri.encodeComponent(newDn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return Response.ok(renderError(session.username, 'Verschieben fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Feature 6: Gruppen erstellen + lÃ¶schen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleCreateGroup(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
  final name = params['name'] ?? '';
  final ouDn = params['ou_dn'] ?? '';
  final description = params['description'] ?? '';
  if (name.isEmpty || ouDn.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    final newDn = await LdapClient(config, session).createGroup(name, ouDn, description: description.isNotEmpty ? description : null);
    auditLog(session.username, 'Gruppe erstellt', newDn);
    return Response.found('/groups');
  } catch (e) {
    return Response.ok(renderError(session.username, 'Gruppe erstellen fehlgeschlagen: $e'), headers: _html);
  }
}

Future<Response> handleDeleteGroup(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) != UserRole.admin) return Response.ok(renderError(session.username, 'Nur Admins dÃ¼rfen Gruppen lÃ¶schen.'), headers: _html);
  final groupDn = params['group_dn'] ?? '';
  if (groupDn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  try {
    await LdapClient(config, session).deleteGroup(groupDn);
    auditLog(session.username, 'Gruppe gelÃ¶scht', groupDn);
    return Response.found('/groups');
  } catch (e) {
    return Response.ok(renderError(session.username, 'Gruppe lÃ¶schen fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Feature 7: Bulk-Aktionen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleBulkUnlock(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
  final userDns = (params['user_dns'] ?? '').split('\n').where((s) => s.isNotEmpty).toList();
  final back = params['back'] ?? '';
  if (userDns.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    await LdapClient(config, session).bulkUnlock(userDns);
    auditLog(session.username, 'Bulk-Entsperren', '', '${userDns.length} User');
    return Response.found('/search?q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return Response.ok(renderError(session.username, 'Bulk-Entsperren fehlgeschlagen: $e'), headers: _html);
  }
}

Future<Response> handleBulkDisable(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
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
    return Response.ok(renderError(session.username, 'Bulk-Aktion fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Audit Log â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Response handleAuditLog(Request req) {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  return Response.ok(renderAuditLog(session.username, getAuditLog()), headers: _html);
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
    if (user == null) return Response.ok(renderError(session.username, 'User nicht gefunden.'), headers: _html);
    return Response.ok(renderCloneForm(session.username, user, back), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

Future<Response> handleClonePost(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) != UserRole.admin) return Response.ok(renderError(session.username, 'Nur Admins dÃ¼rfen User erstellen.'), headers: _html);
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
    return Response.ok(renderError(session.username, 'Pflichtfelder fehlen.'), headers: _html);
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
    return Response.ok(renderError(session.username, 'User erstellen fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Account-Optionen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handlePasswordMustChange(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
  final dn = params['dn'] ?? '';
  final back = params['back'] ?? '';
  if (dn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  try {
    await LdapClient(config, session).setPasswordMustChange(dn);
    auditLog(session.username, 'Passwort-Pflicht bei Anmeldung gesetzt', dn);
    return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

Future<Response> handlePwdNeverExpires(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
  final dn = params['dn'] ?? '';
  final uac = int.tryParse(params['uac'] ?? '0') ?? 0;
  final enable = params['enable'] == '1';
  final back = params['back'] ?? '';
  if (dn.isEmpty) return Response.badRequest(body: 'Fehlender DN');
  try {
    await LdapClient(config, session).setPwdNeverExpires(dn, uac, enable);
    auditLog(session.username, enable ? 'Passwort lÃ¤uft nie ab: ein' : 'Passwort lÃ¤uft nie ab: aus', dn);
    return Response.found('/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}');
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

Future<Response> handleAccountExpiry(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
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
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

// â”€â”€ Inaktive User â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleInactiveUsers(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getInactiveUsers();
    return Response.ok(renderInactiveUsers(session.username, users), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

// â”€â”€ Service-Accounts â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleServiceAccounts(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getServiceAccounts();
    return Response.ok(renderServiceAccounts(session.username, users), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

// â”€â”€ Accounts ohne E-Mail â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleUsersNoEmail(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getUsersWithoutEmail();
    return Response.ok(renderUsersNoEmail(session.username, users), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

// â”€â”€ Passwort-Policy â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handlePasswordPolicy(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final policy = await LdapClient(config, session).getPasswordPolicy();
    return Response.ok(renderPasswordPolicy(session.username, policy), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

// â”€â”€ User-Vergleich â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleUserCompare(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final dnA = req.url.queryParameters['a'] ?? '';
  final dnB = req.url.queryParameters['b'] ?? '';
  if (dnA.isEmpty) return Response.found('/');
  try {
    final client = LdapClient(config, session);
    final userA = await client.getUserDetails(dnA);
    if (userA == null) return Response.ok(renderError(session.username, 'User A nicht gefunden.'), headers: _html);
    if (dnB.isEmpty) {
      return Response.ok(renderUserCompareForm(session.username, userA), headers: _html);
    }
    final userB = await client.getUserDetails(dnB);
    if (userB == null) return Response.ok(renderError(session.username, 'User B nicht gefunden.'), headers: _html);
    return Response.ok(renderUserCompare(session.username, userA, userB), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Vergleich fehlgeschlagen: $e'), headers: _html);
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
    return Response.ok(renderEffectiveGroups(session.username, user, dn, groups), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

// â”€â”€ CSV Bulk-Update â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleBulkCsvForm(Request req) {
  final session = _session(req);
  if (session == null) return Future.value(Response.found('/login'));
  return Future.value(Response.ok(renderBulkCsvForm(session.username), headers: _html));
}

Future<Response> handleBulkCsvPost(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  if (_role(req) != UserRole.admin) return Response.ok(renderError(session.username, 'Nur Admins dÃ¼rfen Bulk-CSV-Updates durchfÃ¼hren.'), headers: _html);
  final csvData = params['csv'] ?? '';
  if (csvData.trim().isEmpty) {
    return Response.ok(renderBulkCsvForm(session.username, error: 'Keine Daten eingegeben.'), headers: _html);
  }
  try {
    final lines = csvData.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 2) {
      return Response.ok(renderBulkCsvForm(session.username, error: 'Mindestens Header + 1 Datenzeile nÃ¶tig.'), headers: _html);
    }
    final headers = lines[0].split(',').map((h) => h.trim()).toList();
    final rows = lines.skip(1).map((l) => l.split(',').toList()).toList();
    final results = await LdapClient(config, session).bulkUpdateFromCsv(headers, rows);
    final ok = results.where((r) => r['success'] == true).length;
    auditLog(session.username, 'CSV Bulk-Update: $ok/${results.length} erfolgreich', '', '');
    return Response.ok(renderBulkCsvResult(session.username, headers, results), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'CSV-Verarbeitung fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Computer-Browser â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleComputers(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final computers = await LdapClient(config, session).getComputers();
    return Response.ok(renderComputers(session.username, computers), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

Future<Response> handleComputerMoveLager(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  final dn = params['dn'] ?? '';
  final targetOu = params['target_ou'] ?? '';
  if (dn.isEmpty || targetOu.isEmpty) return Response.badRequest(body: 'Fehlende Parameter');
  try {
    await LdapClient(config, session).moveUser(dn, targetOu);
    final rdn = dn.substring(0, dn.indexOf(','));
    auditLog(session.username, 'Computer ins Lager verschoben', '$rdn,$targetOu', 'von: $dn');
    return Response.found('/computers');
  } catch (e) {
    return Response.ok(renderError(session.username, 'Verschieben fehlgeschlagen: $e'), headers: _html);
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
    return Response.ok(renderAdvancedSearch(session.username, ous, params, results), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Suche fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Favoriten â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleFavoriteToggle(Request req) async {
  final token = extractToken(req.headers['cookie']);
  final session = getSession(token);
  if (session == null || token == null) return Response.found('/login');
  final params = Uri.splitQueryString(await req.readAsString());
  final dn = params['dn'] ?? '';
  final name = params['name'] ?? dn;
  final back = params['back'] ?? '';
  if (dn.isNotEmpty) {
    toggleFavorite(token, dn, name);
  }
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
  if (dn.isEmpty) {
    return Response.ok(renderOrgChartForm(session.username), headers: _html);
  }
  try {
    final client = LdapClient(config, session);
    final user = await client.getOrgChartUser(dn);
    if (user == null) return Response.ok(renderError(session.username, 'User nicht gefunden.'), headers: _html);

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

    return Response.ok(renderOrgChart(session.username, user, managers, reports), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Org-Chart laden fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Feature 2: Telefonverzeichnis â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleDirectory(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getPhoneDirectory();
    return Response.ok(renderDirectory(session.username, users), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Verzeichnis laden fehlgeschlagen: $e'), headers: _html);
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
    return Response.ok(renderError(session.username, 'Export fehlgeschlagen: $e'), headers: _html);
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
    return Response.ok(renderDeptStats(session.username, sorted.take(20).toList()), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Statistik laden fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Feature 4: Bulk PW-Reset â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleBulkPwResetForm(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getActiveUsers();
    return Response.ok(renderBulkPwResetForm(session.username, users), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
  }
}

Future<Response> handleBulkPwResetPost(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  final body = await req.readAsString();
  final params = Uri.splitQueryString(body);
  if (_role(req) == UserRole.readonly) return Response.ok(renderError(session.username, 'Keine Berechtigung (readonly).'), headers: _html);
  // dns[] aus dem Body extrahieren
  final dns = <String>[];
  for (final part in body.split('&')) {
    if (part.startsWith('dns%5B%5D=') || part.startsWith('dns[]=')) {
      final val = Uri.decodeQueryComponent(part.contains('%5B%5D=')
          ? part.substring('dns%5B%5D='.length)
          : part.substring('dns[]='.length));
      if (val.isNotEmpty) dns.add(val);
    }
  }
  // Fallback: auch aus params['dns[]'] versuchen
  if (dns.isEmpty) {
    final raw = params['dns[]'] ?? params['dns'];
    if (raw != null && raw.isNotEmpty) dns.add(raw);
  }
  if (dns.isEmpty) return Response.ok(renderError(session.username, 'Keine User ausgewÃ¤hlt.'), headers: _html);
  try {
    final result = await LdapClient(config, session).bulkPwdReset(dns);
    final success = (result['success'] as List).cast<String>();
    final errors = (result['errors'] as Map).cast<String, String>();
    for (final dn in success) {
      auditLog(session.username, 'Bulk PW-Reset: Passwort-Pflicht bei Anmeldung gesetzt', dn);
    }
    return Response.ok(renderBulkPwResetResult(session.username, success, errors), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Bulk PW-Reset fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Feature 5: Ablaufende Accounts â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<Response> handleExpiringAccounts(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  try {
    final users = await LdapClient(config, session).getExpiringAccounts();
    return Response.ok(renderExpiringAccounts(session.username, users), headers: _html);
  } catch (e) {
    return Response.ok(renderError(session.username, 'Fehler: $e'), headers: _html);
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
    return Response.ok(renderError(session.username, 'Export fehlgeschlagen: $e'), headers: _html);
  }
}

// â”€â”€ Config UI â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Response handleConfigPage(Request req, Config config) {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  if (_role(req) != UserRole.admin) {
    return Response.ok(renderError(session.username, 'Nur Admins dÃ¼rfen die Konfiguration Ã¤ndern.'), headers: _html);
  }
  final saved = req.url.queryParameters['saved'] == '1';
  return Response.ok(renderConfigPage(session.username, config, saved: saved, csrfToken: _csrfFor(req)), headers: _html);
}

Future<Response> handleConfigPost(Request req, Config config) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  if (_role(req) != UserRole.admin) {
    return Response.ok(renderError(session.username, 'Nur Admins dÃ¼rfen die Konfiguration Ã¤ndern.'), headers: _html);
  }
  final params = Uri.splitQueryString(await req.readAsString());
  final updates = <String, String>{};
  if ((params['AD_SERVER'] ?? '').isNotEmpty)   updates['AD_SERVER']   = params['AD_SERVER']!;
  if ((params['AD_PORT'] ?? '').isNotEmpty)     updates['AD_PORT']     = params['AD_PORT']!;
  if ((params['AD_SSL'] ?? '').isNotEmpty)      updates['AD_SSL']      = params['AD_SSL']!;
  if ((params['AD_USER'] ?? '').isNotEmpty)     updates['AD_USER']     = params['AD_USER']!;
  if ((params['AD_PASSWORD'] ?? '').isNotEmpty) updates['AD_PASSWORD'] = params['AD_PASSWORD']!;
  if ((params['BASE_DN'] ?? '').isNotEmpty)     updates['BASE_DN']     = params['BASE_DN']!;
  config.save(updates);
  auditLog(session.username, 'Konfiguration geÃ¤ndert', '');
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
  } catch (e) {
    return Response(503, body: '{"status":"error","ldap":"${e.toString().replaceAll('"', '\\"')}"}',
        headers: {'content-type': 'application/json'});
  }
}

// â”€â”€ Rollen-Verwaltung â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Response handleRolesPage(Request req) {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  if (_role(req) != UserRole.admin) {
    return Response.ok(renderError(session.username, 'Nur Admins dÃ¼rfen Rollen verwalten.'), headers: _html);
  }
  final roles = getAllRoles();
  return Response.ok(renderRolesPage(session.username, roles, csrfToken: _csrfFor(req)), headers: _html);
}

Future<Response> handleRolesPost(Request req) async {
  final session = _session(req);
  if (session == null) return Response.found('/login');
  if (_role(req) != UserRole.admin) {
    return Response.ok(renderError(session.username, 'Nur Admins dÃ¼rfen Rollen verwalten.'), headers: _html);
  }
  final params = Uri.splitQueryString(await req.readAsString());
  // Parse user=role pairs
  final newRoles = <String, UserRole>{};
  for (final e in params.entries) {
    if (e.key == '_csrf') continue;
    newRoles[e.key] = switch (e.value) {
      'operator' => UserRole.operator,
      'readonly'  => UserRole.readonly,
      _ => UserRole.admin,
    };
  }
  saveRoles(newRoles);
  auditLog(session.username, 'Rollen gespeichert', '', '${newRoles.length} EintrÃ¤ge');
  return Response.found('/admin/roles');
}

