import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:ldap_tool/auth.dart';
import 'package:ldap_tool/config.dart';
import 'package:ldap_tool/routes.dart';
import 'package:ldap_tool/templates.dart';
import 'package:ldap_tool/email_service.dart';
import 'package:ldap_tool/ldap_client.dart';

void _startWeeklyMailer(Config config) {
  String? _lastSentDate;

  Timer.periodic(const Duration(minutes: 30), (_) async {
    final now = DateTime.now();
    // Jeden Montag zwischen 07:00 und 07:30 Uhr
    if (now.weekday != DateTime.monday) return;
    if (now.hour != 7) return;
    final todayKey = '${now.year}-${now.month}-${now.day}';
    if (_lastSentDate == todayKey) return;
    _lastSentDate = todayKey;
    print('[Wochen-Report] Starte Versand...');
    await sendWeeklyReport(config);
  });
}

Middleware authMiddleware() => (Handler inner) => (Request req) async {
  final path = req.url.path;
  if (path == 'login') return inner(req);
  if (path == 'health') return inner(req); // kein Auth für Health-Check
  if (getSession(extractToken(req.headers['cookie'])) == null) {
    return Response.found('/login');
  }
  return inner(req);
};

void main() async {
  try {
    final config = Config.load();
    configureTemplates(
      domain: config.displayDomain,
      lagerOu: config.lagerOu,
      computerPrefixes: config.computerPrefixes,
    );

    final router = Router()
      ..get('/', (Request r) => handleDashboard(r, config))
      ..get('/login', handleLoginPage)
      ..post('/login', (Request r) => handleLoginPost(r, config))
      ..get('/logout', handleLogout)
      ..get('/search', (Request r) => handleSearch(r, config))
      ..get('/user', (Request r) => handleUserDetail(r, config))
      ..post('/modify', (Request r) => handleModify(r, config))
      ..post('/photo', (Request r) => handlePhotoUpload(r, config))
      ..post('/photo/delete', (Request r) => handlePhotoDelete(r, config))
      ..get('/groups', (Request r) => handleGroups(r, config))
      ..get('/groups/members', (Request r) => handleGroupMembers(r, config))
      ..post('/group/add', (Request r) => handleGroupAdd(r, config))
      ..post('/group/add/confirm', (Request r) => handleGroupAddConfirm(r, config))
      ..post('/group/remove', (Request r) => handleGroupRemove(r, config))
      ..post('/group/create', (Request r) => handleCreateGroup(r, config))
      ..post('/group/delete', (Request r) => handleDeleteGroup(r, config))
      ..post('/groups/copy', (Request r) => handleGroupsCopy(r, config))
      ..post('/groups/paste', (Request r) => handleGroupsPaste(r, config))
      ..get('/export/search', (Request r) => handleExportSearch(r, config))
      ..get('/export/group', (Request r) => handleExportGroup(r, config))
      ..get('/export/audit', handleExportAudit)
      ..get('/export/users', (Request r) => handleExportAllUsers(r, config))
      ..post('/password/reset', (Request r) => handlePasswordReset(r, config))
      ..post('/account/toggle', (Request r) => handleAccountToggle(r, config))
      ..post('/account/unlock', (Request r) => handleAccountUnlock(r, config))
      ..post('/bulk/group/add', (Request r) => handleBulkGroupAdd(r, config))
      ..post('/bulk/unlock', (Request r) => handleBulkUnlock(r, config))
      ..post('/bulk/disable', (Request r) => handleBulkDisable(r, config))
      ..get('/ou', (Request r) => handleOuBrowser(r, config))
      ..get('/ou/users', (Request r) => handleOuUsers(r, config))
      ..get('/audit', handleAuditLog)
      ..get('/user/clone', (Request r) => handleCloneForm(r, config))
      ..post('/user/clone', (Request r) => handleClonePost(r, config))
      ..get('/user/move', (Request r) => handleMoveUserForm(r, config))
      ..post('/user/move', (Request r) => handleMoveUserPost(r, config))
      ..get('/users/locked', (Request r) => handleLockedUsers(r, config))
      ..get('/users/disabled', (Request r) => handleDisabledUsers(r, config))
      ..get('/users/pw-expiring', (Request r) => handlePwExpiring(r, config))
      ..post('/account/pwmustchange', (Request r) => handlePasswordMustChange(r, config))
      ..post('/account/pwexpiry', (Request r) => handlePwdNeverExpires(r, config))
      ..post('/account/expiry', (Request r) => handleAccountExpiry(r, config))
      ..get('/settings', handleSettingsPage)
      ..post('/settings', handleSettingsPost)
      // ── Neue Features ────────────────────────────────────────────────────────
      ..get('/users/inactive', (Request r) => handleInactiveUsers(r, config))
      ..get('/users/service', (Request r) => handleServiceAccounts(r, config))
      ..get('/users/no-email', (Request r) => handleUsersNoEmail(r, config))
      ..get('/user/compare', (Request r) => handleUserCompare(r, config))
      ..get('/user/groups-effective', (Request r) => handleEffectiveGroups(r, config))
..get('/computers', (Request r) => handleComputers(r, config))
      ..post('/computer/move-lager', (Request r) => handleComputerMoveLager(r, config))
      ..get('/search/advanced', (Request r) => handleAdvancedSearch(r, config))
      ..post('/favorite/toggle', handleFavoriteToggle)
      ..get('/orgchart', (Request r) => handleOrgChart(r, config))
      ..get('/directory', (Request r) => handleDirectory(r, config))
      ..get('/export/directory', (Request r) => handleExportDirectory(r, config))
      ..get('/stats/departments', (Request r) => handleDeptStats(r, config))
      ..get('/users/expiring-accounts', (Request r) => handleExpiringAccounts(r, config))
      ..get('/user/notes', handleGetNote)
      ..post('/user/notes', handleSetNote)
      // ── Produktions-Features ────────────────────────────────────────────────
      ..get('/config', (Request r) => handleConfigPage(r, config))
      ..post('/config', (Request r) => handleConfigPost(r, config))
      ..get('/admin/roles', handleRolesPage)
      ..post('/admin/roles', handleRolesPost)
      ..get('/health', (Request r) => handleHealth(r, config))
      ..get('/api/stats', (Request r) async {
        final session = getSession(extractToken(r.headers['cookie']));
        if (session == null) return Response(401, body: '{"error":"unauthorized"}', headers: {'content-type': 'application/json'});
        try {
          final stats = await LdapClient(config, session).getDashboardStats();
          final total = stats['total'] ?? 0;
          final disabled = stats['disabled'] ?? 0;
          final locked = stats['locked'] ?? 0;
          return Response.ok(
            '{"total":$total,"disabled":$disabled,"locked":$locked,"active":${total - disabled}}',
            headers: {'content-type': 'application/json'},
          );
        } catch (e) {
          return Response(500, body: '{"error":"$e"}', headers: {'content-type': 'application/json'});
        }
      })
      ..get('/admin/test-mail', (Request r) async {
        final session = getSession(extractToken(r.headers['cookie']));
        if (session == null) return Response.found('/login');
        if (getRole(session.username) != UserRole.admin) {
          return Response(403, body: 'Nur Admins dürfen Test-Mails senden.');
        }
        final ok = await sendWeeklyReport(config);
        return Response.found('/settings?msg=${ok ? 'testmail-ok' : 'testmail-err'}');
      });

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(authMiddleware())
        .addHandler(router.call);

    _startWeeklyMailer(config);

    final server = await io.serve(handler, '0.0.0.0', 5000);
    print('LDAP Tool läuft auf http://localhost:${server.port}');
    print('Browser öffnen: http://localhost:${server.port}');
    print('Zum Beenden: dieses Fenster schliessen.');

    // Prozess am Leben halten (läuft bis das Fenster geschlossen wird)
    await Completer<void>().future;
  } catch (e, st) {
    stderr.writeln('\n=== FEHLER beim Starten ===');
    stderr.writeln(e);
    stderr.writeln(st);
    stderr.writeln('\nDieses Fenster kann geschlossen werden.');
    // 60 Sekunden warten damit das Fenster lesbar bleibt
    await Future.delayed(Duration(seconds: 60));
  }
}
