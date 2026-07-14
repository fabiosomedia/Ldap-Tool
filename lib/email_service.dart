import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'auth.dart';
import 'config.dart';
import 'ldap_client.dart';

Future<void> sendWeeklyReport(Config config) async {
  if (!config.smtpConfigured) {
    print('[Wochen-Report] SMTP nicht konfiguriert – übersprungen.');
    return;
  }

  // Service-Session mit Bind-Account
  final session = SessionData('system', config.bindUser, config.bindPassword);
  final client = LdapClient(config, session);

  List<Map<String, dynamic>> locked = [];
  List<Map<String, dynamic>> expiring = [];

  try {
    locked = await client.getLockedUsers();
  } catch (e) {
    print('[Wochen-Report] Gesperrte User laden fehlgeschlagen: $e');
  }
  try {
    expiring = await client.getUsersExpiringPasswords();
  } catch (e) {
    print('[Wochen-Report] Ablaufende Passwörter laden fehlgeschlagen: $e');
  }

  final domain = config.displayDomain;
  final now = DateTime.now();
  final dateStr = '${now.day}.${now.month}.${now.year}';

  final html = _buildHtml(domain, dateStr, locked, expiring);

  final smtpServer = SmtpServer(
    config.smtpHost,
    port: config.smtpPort,
    ssl: config.smtpSsl,
    username: config.smtpUser.isNotEmpty ? config.smtpUser : null,
    password: config.smtpPassword.isNotEmpty ? config.smtpPassword : null,
    ignoreBadCertificate: true,
  );

  final from = config.smtpFrom.isNotEmpty ? config.smtpFrom : 'userdesk@$domain';
  final message = Message()
    ..from = Address(from, 'UserDesk')
    ..recipients.addAll(config.smtpTo.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty))
    ..subject = 'UserDesk Wochen-Report – $dateStr'
    ..html = html;

  try {
    await send(message, smtpServer);
    print('[Wochen-Report] E-Mail gesendet an ${config.smtpTo}');
  } catch (e) {
    print('[Wochen-Report] Senden fehlgeschlagen: $e');
  }
}

String _buildHtml(String domain, String date,
    List<Map<String, dynamic>> locked, List<Map<String, dynamic>> expiring) {
  final lockedRows = locked.isEmpty
      ? '<tr><td colspan="3" style="color:#6b7280;font-style:italic;padding:.6rem .8rem;">Keine gesperrten Benutzer</td></tr>'
      : locked.map((u) {
          final cn = _esc(u['cn'] ?? '–');
          final sam = _esc(u['sAMAccountName'] ?? '–');
          final dept = _esc(u['department'] ?? '–');
          return '<tr><td>$cn</td><td>$sam</td><td>$dept</td></tr>';
        }).join('\n');

  final expiringRows = expiring.isEmpty
      ? '<tr><td colspan="4" style="color:#6b7280;font-style:italic;padding:.6rem .8rem;">Keine ablaufenden Passwörter</td></tr>'
      : expiring.map((u) {
          final cn = _esc(u['cn'] ?? '–');
          final sam = _esc(u['sAMAccountName'] ?? '–');
          final dept = _esc(u['department'] ?? '–');
          final days = u['_daysLeft']?.toString() ?? '?';
          final color = int.tryParse(days) != null && int.parse(days) <= 3
              ? '#dc2626' : '#d97706';
          return '<tr><td>$cn</td><td>$sam</td><td>$dept</td>'
              '<td style="color:$color;font-weight:600;">$days Tage</td></tr>';
        }).join('\n');

  return '''<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family:Inter,Arial,sans-serif;background:#f9fafb;margin:0;padding:2rem;">
<div style="max-width:680px;margin:0 auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 1px 4px rgba(0,0,0,.1);">
  <div style="background:#2563eb;padding:1.5rem 2rem;">
    <div style="font:700 20px sans-serif;color:#fff;">UserDesk</div>
    <div style="font:400 13px sans-serif;color:#bfdbfe;margin-top:.25rem;">Wochen-Report – $date · $domain</div>
  </div>
  <div style="padding:1.5rem 2rem;">

    <h2 style="font-size:15px;font-weight:700;color:#1e293b;margin:0 0 .75rem;">
      🔒 Gesperrte Benutzer (${locked.length})
    </h2>
    <table style="width:100%;border-collapse:collapse;font-size:13px;margin-bottom:2rem;">
      <thead>
        <tr style="background:#f1f5f9;color:#64748b;font-size:11px;text-transform:uppercase;letter-spacing:.05em;">
          <th style="text-align:left;padding:.5rem .8rem;">Name</th>
          <th style="text-align:left;padding:.5rem .8rem;">Benutzername</th>
          <th style="text-align:left;padding:.5rem .8rem;">Abteilung</th>
        </tr>
      </thead>
      <tbody style="color:#374151;">
        $lockedRows
      </tbody>
    </table>

    <h2 style="font-size:15px;font-weight:700;color:#1e293b;margin:0 0 .75rem;">
      ⏳ Passwort läuft ab – diese Woche (${expiring.length})
    </h2>
    <table style="width:100%;border-collapse:collapse;font-size:13px;margin-bottom:1.5rem;">
      <thead>
        <tr style="background:#f1f5f9;color:#64748b;font-size:11px;text-transform:uppercase;letter-spacing:.05em;">
          <th style="text-align:left;padding:.5rem .8rem;">Name</th>
          <th style="text-align:left;padding:.5rem .8rem;">Benutzername</th>
          <th style="text-align:left;padding:.5rem .8rem;">Abteilung</th>
          <th style="text-align:left;padding:.5rem .8rem;">Verbleibend</th>
        </tr>
      </thead>
      <tbody style="color:#374151;">
        $expiringRows
      </tbody>
    </table>

  </div>
  <div style="background:#f8fafc;border-top:1px solid #e2e8f0;padding:1rem 2rem;font:400 12px sans-serif;color:#94a3b8;">
    UserDesk · Automatisch generiert · Benutzerverwaltung $domain
  </div>
</div>
</body>
</html>''';
}

String _esc(dynamic v) => v.toString()
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
