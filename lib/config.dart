import 'dart:convert';
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:ldap_tool/credential_store.dart';

class Config {
  String server;
  String bindUser;
  String bindPassword;
  String baseDn;
  int port;
  bool useSsl;
  bool ignoreCert;
  String adminOu;
  String lagerOu;
  List<String> computerPrefixes;

  // SMTP (optional, für Wochen-Report)
  String smtpHost;
  int smtpPort;
  bool smtpSsl;
  String smtpUser;
  String smtpPassword;
  String smtpFrom;
  String smtpTo;

  bool get smtpConfigured => smtpHost.isNotEmpty && smtpTo.isNotEmpty;

  Config({
    required this.server,
    required this.bindUser,
    required this.bindPassword,
    required this.baseDn,
    required this.port,
    required this.useSsl,
    required this.ignoreCert,
    required this.adminOu,
    required this.lagerOu,
    required this.computerPrefixes,
    this.smtpHost = '',
    this.smtpPort = 587,
    this.smtpSsl = false,
    this.smtpUser = '',
    this.smtpPassword = '',
    this.smtpFrom = '',
    this.smtpTo = '',
  });

  String get displayDomain {
    final parts = baseDn.split(',')
        .where((p) => p.trim().toUpperCase().startsWith('DC='))
        .map((p) => p.trim().substring(3))
        .toList();
    return parts.isEmpty ? baseDn : parts.join('.');
  }

  factory Config.load() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final envPaths = ['$exeDir\\.env', '$exeDir/.env', '.env'];
    final envPath = envPaths.firstWhere(
      (p) => File(p).existsSync(),
      orElse: () => throw Exception(
        '.env Datei nicht gefunden!\n'
        'Erwartet neben der ldap_tool.exe:\n  $exeDir\\.env\n\n'
        'Inhalt der .env:\n'
        '  AD_SERVER=<IP oder Hostname>\n'
        '  AD_PORT=636\n'
        '  AD_SSL=true\n'
        '  AD_USER=CN=...\n'
        '  AD_PASSWORD=...\n'
        '  BASE_DN=DC=...\n'
        '  ADMIN_OU=<Name der Admin-OU, leer = alle AD-User dürfen sich anmelden>\n'
        '  LAGER_OU=<Ziel-OU DN für deaktivierte Geräte>\n'
        '  COMPUTER_PREFIX=nb,mb',
      ),
    );

    final env = DotEnv()..load([envPath]);
    final prefixRaw = env['COMPUTER_PREFIX'] ?? '';
    final prefixes = prefixRaw
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();

    // Passwort aus Windows Credential Manager lesen
    String? bindPassword = readCredential();

    if (bindPassword == null) {
      // Migrations-Pfad: AD_PASSWORD noch in .env vorhanden
      final envPassword = env['AD_PASSWORD'];
      if (envPassword != null && envPassword.isNotEmpty) {
        final bindUser = env['AD_USER'] ?? '';
        writeCredential(bindUser, envPassword);
        _removePasswordFromEnv(envPath);
        bindPassword = envPassword;
        print('[LDAPatschifig] AD_PASSWORD aus .env in Windows Credential Manager migriert und aus .env entfernt.');
      } else {
        throw Exception(
          'AD-Passwort nicht gefunden!\n'
          'Weder im Windows Credential Manager noch in der .env.\n'
          'Bitte AD_PASSWORD einmalig in die .env eintragen — beim nächsten Start wird es automatisch migriert.',
        );
      }
    }

    return Config(
      server: env['AD_SERVER'] ?? '',
      bindUser: env['AD_USER'] ?? '',
      bindPassword: bindPassword,
      baseDn: env['BASE_DN'] ?? '',
      port: int.tryParse(env['AD_PORT'] ?? '389') ?? 389,
      useSsl: env['AD_SSL'] == 'true',
      ignoreCert: env['AD_IGNORE_CERT'] != 'false',
      adminOu: env['ADMIN_OU'] ?? '',
      lagerOu: env['LAGER_OU'] ?? '',
      computerPrefixes: prefixes,
      smtpHost: env['SMTP_HOST'] ?? '',
      smtpPort: int.tryParse(env['SMTP_PORT'] ?? '587') ?? 587,
      smtpSsl: env['SMTP_SSL'] == 'true',
      smtpUser: env['SMTP_USER'] ?? '',
      smtpPassword: env['SMTP_PASSWORD'] ?? '',
      smtpFrom: env['SMTP_FROM'] ?? '',
      smtpTo: env['SMTP_TO'] ?? '',
    );
  }

  /// Speichere Updates in die .env-Datei und aktualisiere dieses Config-Objekt.
  /// AD_PASSWORD wird in den Windows Credential Manager geschrieben, nicht in die .env.
  void save(Map<String, String> updates) {
    // AD_PASSWORD → Credential Manager statt .env
    if (updates.containsKey('AD_PASSWORD') && updates['AD_PASSWORD']!.isNotEmpty) {
      writeCredential(bindUser, updates['AD_PASSWORD']!);
      bindPassword = updates['AD_PASSWORD']!;
      updates = Map.of(updates)..remove('AD_PASSWORD');
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final envPaths = ['$exeDir\\.env', '$exeDir/.env', '.env'];
    final envPath = envPaths.firstWhere(
      (p) => File(p).existsSync(),
      orElse: () => '$exeDir${Platform.pathSeparator}.env',
    );

    // Aktuelle .env einlesen (ohne AD_PASSWORD-Zeilen)
    final envFile = File(envPath);
    final lines = envFile.existsSync()
        ? envFile.readAsStringSync(encoding: utf8).split('\n').map((l) => l.trimRight()).toList()
        : <String>[];
    final existing = <String, String>{};
    for (final line in lines) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final idx = line.indexOf('=');
      if (idx > 0) {
        final key = line.substring(0, idx).trim();
        if (key == 'AD_PASSWORD') continue; // nie in .env speichern
        existing[key] = line.substring(idx + 1).trim();
      }
    }

    // Updates anwenden (leere Werte → alten Wert behalten)
    for (final e in updates.entries) {
      if (e.value.isNotEmpty && e.key != 'AD_PASSWORD') {
        existing[e.key] = e.value;
      }
    }

    // Schreiben
    final buf = StringBuffer();
    for (final e in existing.entries) {
      buf.writeln('${e.key}=${e.value}');
    }
    envFile.writeAsStringSync(buf.toString(), encoding: utf8);

    // Config-Objekt in-place aktualisieren
    server           = existing['AD_SERVER']        ?? server;
    bindUser         = existing['AD_USER']          ?? bindUser;
    baseDn           = existing['BASE_DN']          ?? baseDn;
    port             = int.tryParse(existing['AD_PORT'] ?? '') ?? port;
    useSsl           = (existing['AD_SSL'] ?? 'false') == 'true';
    adminOu          = existing['ADMIN_OU']         ?? adminOu;
    lagerOu          = existing['LAGER_OU']         ?? lagerOu;
    final pr         = existing['COMPUTER_PREFIX'] ?? '';
    computerPrefixes = pr.split(',').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
  }

  static void _removePasswordFromEnv(String envPath) {
    final file = File(envPath);
    if (!file.existsSync()) return;
    final lines = file
        .readAsStringSync(encoding: utf8)
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => !l.startsWith('AD_PASSWORD='))
        .toList();
    file.writeAsStringSync('${lines.join('\r\n')}\r\n', encoding: utf8);
  }
}
