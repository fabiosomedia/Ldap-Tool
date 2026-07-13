import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartdap/dartdap.dart';
import 'package:dotenv/dotenv.dart';

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

  final result = await conn.search(
    DN(env['BASE_DN'] ?? ''),
    Filter.or([
      Filter.substring('cn', '*Colucello*'),
      Filter.substring('cn', '*Mauro*'),
      Filter.substring('sAMAccountName', '*mauro*'),
    ]),
    ['cn', 'sAMAccountName', 'thumbnailPhoto', 'jpegPhoto'],
  );

  var count = 0;
  await for (final entry in result.stream) {
    final dn = entry.dn.toString();
    count++;
    print('\nEntry $count DN: "$dn"');
    print('  Attributes: ${entry.attributes.keys.toList()}');

    for (final attr in entry.attributes.values) {
      if (attr.name == 'thumbnailPhoto' || attr.name == 'jpegPhoto') {
        print('  ${attr.name}: ${attr.values.length} Wert(e)');
        if (attr.values.isNotEmpty) {
          final val = attr.values.first;
          print('    Typ: ${val.runtimeType}');
          try {
            final bytes = (val as dynamic).valueBytes() as Uint8List;
            print('    Bytes: ${bytes.length}');
            print('    Erste 4 Bytes: ${bytes.take(4).toList()} (JPEG erwartet: [255, 216, 255, ...])');
            // Speichere Testbild
            File('test_photo.jpg').writeAsBytesSync(bytes);
            print('    → test_photo.jpg gespeichert');
          } catch (e) {
            print('    valueBytes Fehler: $e');
            // Versuch encodedBytes
            try {
              final enc = (val as dynamic).encodedBytes as Uint8List;
              print('    encodedBytes Länge: ${enc.length}');
            } catch (e2) {
              print('    encodedBytes Fehler: $e2');
            }
          }
        }
      } else {
        print('  ${attr.name}: ${attr.values.isNotEmpty ? attr.values.first : "(leer)"}');
      }
    }
  }

  print('\nTotal entries: $count');
  await conn.close();
}
