import 'dart:io';
import 'package:dotenv/dotenv.dart';

class Config {
  String server;
  String bindUser;
  String bindPassword;
  String baseDn;
  int port;
  bool useSsl;
  String adminOu;
  String lagerOu;
  List<String> computerPrefixes;

  Config({
    required this.server,
    required this.bindUser,
    required this.bindPassword,
    required this.baseDn,
    required this.port,
    required this.useSsl,
    required this.adminOu,
    required this.lagerOu,
    required this.computerPrefixes,
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

    return Config(
      server: env['AD_SERVER'] ?? '',
      bindUser: env['AD_USER'] ?? '',
      bindPassword: env['AD_PASSWORD'] ?? '',
      baseDn: env['BASE_DN'] ?? '',
      port: int.tryParse(env['AD_PORT'] ?? '389') ?? 389,
      useSsl: env['AD_SSL'] == 'true',
      adminOu: env['ADMIN_OU'] ?? '',
      lagerOu: env['LAGER_OU'] ?? '',
      computerPrefixes: prefixes,
    );
  }

  /// Speichere Updates in die .env-Datei und aktualisiere dieses Config-Objekt
  void save(Map<String, String> updates) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final envPaths = ['$exeDir\\.env', '$exeDir/.env', '.env'];
    final envPath = envPaths.firstWhere(
      (p) => File(p).existsSync(),
      orElse: () => '$exeDir${Platform.pathSeparator}.env',
    );

    // Aktuelle .env einlesen
    final envFile = File(envPath);
    final lines = envFile.existsSync() ? envFile.readAsLinesSync() : <String>[];
    final existing = <String, String>{};
    for (final line in lines) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final idx = line.indexOf('=');
      if (idx > 0) {
        existing[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
      }
    }

    // Updates anwenden (leere Werte → alten Wert behalten)
    for (final e in updates.entries) {
      if (e.value.isNotEmpty) {
        existing[e.key] = e.value;
      }
    }

    // Schreiben
    final buf = StringBuffer();
    for (final e in existing.entries) {
      buf.writeln('${e.key}=${e.value}');
    }
    envFile.writeAsStringSync(buf.toString());

    // Config-Objekt in-place aktualisieren
    server           = existing['AD_SERVER']        ?? server;
    bindUser         = existing['AD_USER']          ?? bindUser;
    bindPassword     = existing['AD_PASSWORD']      ?? bindPassword;
    baseDn           = existing['BASE_DN']          ?? baseDn;
    port             = int.tryParse(existing['AD_PORT'] ?? '') ?? port;
    useSsl           = (existing['AD_SSL'] ?? 'false') == 'true';
    adminOu          = existing['ADMIN_OU']         ?? adminOu;
    lagerOu          = existing['LAGER_OU']         ?? lagerOu;
    final pr         = existing['COMPUTER_PREFIX'] ?? '';
    computerPrefixes = pr.split(',').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
  }
}
