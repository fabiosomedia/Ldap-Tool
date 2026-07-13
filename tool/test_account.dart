import 'dart:convert';
import 'dart:typed_data';
import 'package:asn1lib/asn1lib.dart';
import 'package:dartdap/dartdap.dart';
import 'package:dotenv/dotenv.dart';

DN safeDn(String dn) =>
    DN.fromOctetString(ASN1OctetString(Uint8List.fromList(utf8.encode(dn))));

Uint8List encodePassword(String password) {
  final quoted = '"$password"';
  final builder = BytesBuilder();
  for (final unit in quoted.codeUnits) {
    builder.addByte(unit & 0xFF);
    builder.addByte((unit >> 8) & 0xFF);
  }
  return builder.toBytes();
}

void main() async {
  final env = DotEnv()..load(['.env']);
  final conn = LdapConnection(
    host: env['AD_SERVER'] ?? '',
    ssl: env['AD_SSL'] == 'true',
    port: int.tryParse(env['AD_PORT'] ?? '389') ?? 389,
    bindDN: DN(env['AD_USER'] ?? ''),
    password: env['AD_PASSWORD'] ?? '',
    badCertificateHandler: (cert) => true,
  );
  await conn.open();
  await conn.bind();
  print('✓ Verbunden');

  // testbrf DN suchen
  final result = await conn.search(
    DN(env['BASE_DN'] ?? ''),
    Filter.substring('sAMAccountName', '*testbrf*'),
    ['cn', 'distinguishedName', 'userAccountControl', 'lockoutTime'],
  );
  String? foundDn;
  int uac = 0;
  await for (final entry in result.stream) {
    final d = entry.dn.toString();
    if (d.isEmpty) continue;
    foundDn = d;
    for (final attr in entry.attributes.values) {
      print('  ${attr.name}: ${attr.values.isNotEmpty ? attr.values.first : "(leer)"}');
      if (attr.name == 'userAccountControl') {
        uac = int.tryParse(attr.values.first.toString()) ?? 0;
      }
    }
    break;
  }
  if (foundDn == null) { print('✗ testbrf nicht gefunden'); await conn.close(); return; }
  print('\nDN: $foundDn');
  print('UAC: $uac (disabled=${(uac & 2) != 0})');

  // Test 1: Passwort zurücksetzen
  print('\n--- Test Passwort-Reset ---');
  try {
    final bytes = encodePassword('Somedia2026.');
    await conn.modify(safeDn(foundDn), [Modification.replace('unicodePwd', [bytes])]);
    print('✓ Passwort auf "Somedia2026." gesetzt');
  } catch (e) {
    print('✗ Passwort-Reset FEHLER: $e');
  }

  // Test 2: Account deaktivieren
  print('\n--- Test Account deaktivieren ---');
  try {
    final newUac = uac | 2;
    await conn.modify(safeDn(foundDn), [Modification.replace('userAccountControl', [newUac.toString()])]);
    print('✓ Account deaktiviert (UAC=$newUac)');
  } catch (e) {
    print('✗ Deaktivieren FEHLER: $e');
  }

  // Test 3: Account wieder aktivieren
  print('\n--- Test Account aktivieren ---');
  try {
    final newUac = uac & ~2;
    await conn.modify(safeDn(foundDn), [Modification.replace('userAccountControl', [newUac.toString()])]);
    print('✓ Account aktiviert (UAC=$newUac)');
  } catch (e) {
    print('✗ Aktivieren FEHLER: $e');
  }

  await conn.close();
  print('\nFertig.');
}
