import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:asn1lib/asn1lib.dart';
import 'package:dartdap/dartdap.dart';
import 'auth.dart';
import 'config.dart';

// ── Extensible Match Filter ───────────────────────────────────────────────────
// dartdap 0.11.4 hat TYPE_EXTENSIBLE_MATCH nicht implementiert.
// Wir bauen den ASN.1-Blob manuell und wrappen ihn in einen Filter.

class _ExtensibleFilter extends Filter {
  final String _attrName;
  final String _matchingRule;
  final String _value;

  _ExtensibleFilter(this._attrName, this._matchingRule, this._value)
      : super(Filter.TYPE_EXTENSIBLE_MATCH);

  @override
  ASN1Object toASN1() {
    // extensibleMatch [9] ExtensibleMatchFilter
    // ExtensibleMatchFilter ::= SEQUENCE {
    //   matchingRule [1] MatchingRuleId OPTIONAL,
    //   type         [2] AttributeDescription OPTIONAL,
    //   matchValue   [3] AssertionValue,
    //   dnAttributes [4] BOOLEAN DEFAULT FALSE
    // }
    final seq = ASN1Sequence(tag: 0xA9); // [APPLICATION 9] IMPLICIT SEQUENCE
    // [1] matchingRule
    seq.add(ASN1OctetString(_matchingRule, tag: 0x81));
    // [2] type (attribute name)
    seq.add(ASN1OctetString(_attrName, tag: 0x82));
    // [3] matchValue
    seq.add(ASN1OctetString(_value, tag: 0x83));
    // [4] dnAttributes = FALSE (omit, default)
    return seq;
  }
}

/// Erzeugt einen extensible-match Filter wie:
/// (attrName:matchingRule:=value)
Filter _extMatch(String attrName, String matchingRule, String value) =>
    _ExtensibleFilter(attrName, matchingRule, value);

// ── NOT-Filter wrapper (dartdap unterstützt Filter.not() intern) ──────────────
Filter _notFilter(Filter f) => Filter.not(f);

// DN() parst den String und scheitert bei escaped Kommas (z.B. CN=test\, Brf).
// Diese Funktion erstellt DN direkt aus Bytes ohne Parsing.
DN _safeDn(String dn) =>
    DN.fromOctetString(ASN1OctetString(Uint8List.fromList(utf8.encode(dn))));

// LDAP-Attributwerte kommen als ASN1OctetString mit UTF-8 Bytes aus AD.
// Explizite UTF-8-Dekodierung verhindert Umlaut-Probleme (öäü).
String _ldapStr(dynamic v) {
  try {
    final bytes = (v as dynamic).valueBytes() as Uint8List;
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return v.toString();
  }
}


class LdapClient {
  final Config config;
  final SessionData session;

  LdapClient(this.config, this.session);

  Future<LdapConnection> _connect() async {
    try {
      final conn = LdapConnection(
        host: config.server,
        ssl: config.useSsl,
        port: config.port,
        bindDN: DN(session.dn),
        password: session.password,
        badCertificateHandler: (cert) => config.ignoreCert,
      );
      await conn.open().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('LDAP-Verbindungs-Timeout'),
      );
      await conn.bind().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('LDAP-Bind-Timeout'),
      );
      return conn;
    } on SocketException {
      throw Exception('LDAP-Server nicht erreichbar (${config.server}:${config.port})');
    } on TimeoutException catch (e) {
      throw Exception(e.message ?? 'Verbindungs-Timeout');
    }
  }

  // Paged search — holt alle Einträge in Seiten à pageSize (umgeht AD-Limit 1000)
  Future<List<SearchEntry>> _pagedSearch(LdapConnection conn, Filter filter, List<String> attrs, {int pageSize = 500}) async {
    final all = <SearchEntry>[];
    var paged = SimplePagedResultsControl(size: pageSize);
    var done = false;
    while (!done) {
      final sr = await conn.search(DN(config.baseDn), filter, attrs, controls: [paged]);
      await for (final entry in sr.stream) {
        if (entry.dn.toString().isNotEmpty) all.add(entry);
      }
      done = true;
      for (final ctrl in sr.controls) {
        if (ctrl is SimplePagedResultsControl) {
          if (!ctrl.isEmptyCookie) {
            paged = SimplePagedResultsControl(size: pageSize, cookie: ctrl.cookie);
            done = false;
          }
        }
      }
    }
    return all;
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      final filter = query.isEmpty
          ? Filter.and([
              Filter.equals('objectClass', 'user'),
              Filter.equals('objectCategory', 'person'),
              Filter.present('sAMAccountName'),
            ])
          : Filter.or([
              Filter.substring('sAMAccountName', '*$query*'),
              Filter.substring('cn', '*$query*'),
              Filter.substring('mail', '*$query*'),
              Filter.substring('initials', '*$query*'),
              Filter.substring('description', '*$query*'),
              Filter.substring('extensionAttribute1', '*$query*'),
            ]);
      final attrs = ['cn', 'sAMAccountName', 'mail', 'department',
                     'userAccountControl', 'lockoutTime', 'distinguishedName', 'jpegPhoto', 'thumbnailPhoto',
                     'accountExpires', 'pwdLastSet', 'description', 'extensionAttribute1'];
      final entries = query.isEmpty
          ? await _pagedSearch(conn, filter, attrs)
          : await conn.search(DN(config.baseDn), filter, attrs).then((sr) => sr.stream.toList());
      for (final entry in entries) {
        final dn = entry.dn.toString();
        if (dn.isEmpty) continue;
        final map = <String, dynamic>{'dn': dn};
        for (final attr in entry.attributes.values) {
          if ((attr.name == 'jpegPhoto' || attr.name == 'thumbnailPhoto') && attr.values.isNotEmpty) {
            try {
              final bytes = (attr.values.first as dynamic).valueBytes() as Uint8List;
              final mime = _detectMime(bytes);
              map['jpegPhoto'] = 'data:$mime;base64,${base64Encode(bytes)}';
            } catch (_) {}
          } else {
            map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
          }
        }
        results.add(map);
      }
    } finally {
      await conn.close();
    }
    results.sort((a, b) =>
        (a['cn'] ?? '').toString().compareTo((b['cn'] ?? '').toString()));
    return results;
  }

  Future<Map<String, dynamic>?> getUserDetails(String dn) async {
    final conn = await _connect();
    try {
      final attrs = [
        'cn', 'givenName', 'sn', 'displayName', 'sAMAccountName',
        'mail', 'telephoneNumber', 'mobile', 'department', 'title',
        'company', 'streetAddress', 'l', 'postalCode', 'description',
        'userAccountControl', 'lockoutTime', 'memberOf', 'jpegPhoto', 'thumbnailPhoto', 'distinguishedName',
        'whenCreated', 'whenChanged', 'lastLogonTimestamp', 'pwdLastSet', 'accountExpires',
        'physicalDeliveryOfficeName', 'initials', 'extensionAttribute1',
      ];
      final result = await conn.search(
        DN(config.baseDn),
        Filter.equals('distinguishedName', dn),
        attrs,
      );
      Map<String, dynamic>? map;
      await for (final entry in result.stream) {
        if (entry.dn.toString().isEmpty) continue;
        map = {'dn': entry.dn.toString()};
        for (final attr in entry.attributes.values) {
          if ((attr.name == 'jpegPhoto' || attr.name == 'thumbnailPhoto') && attr.values.isNotEmpty) {
            try {
              final bytes = (attr.values.first as dynamic).valueBytes() as Uint8List;
              final mime = _detectMime(bytes);
              map['jpegPhoto'] = 'data:$mime;base64,${base64Encode(bytes)}';
            } catch (_) {}
          } else if (attr.name == 'memberOf') {
            map['memberOf'] = attr.values.map((v) => _ldapStr(v)).toList();
          } else {
            map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
          }
        }
        break;
      }
      return map;
    } finally {
      await conn.close();
    }
  }

  Future<void> modifyUser(String dn, String attribute, String value) async {
    final conn = await _connect();
    try {
      await conn.modify(_safeDn(dn), [Modification.replace(attribute, [value])]);
    } finally {
      await conn.close();
    }
  }

  Future<void> updatePhoto(String dn, Uint8List photoBytes) async {
    final conn = await _connect();
    try {
      await conn.modify(_safeDn(dn), [Modification.replace('thumbnailPhoto', [photoBytes])]);
    } finally {
      await conn.close();
    }
  }

  Future<void> deletePhoto(String dn) async {
    final conn = await _connect();
    try {
      await conn.modify(_safeDn(dn), [Modification.delete('thumbnailPhoto', [])]);
    } finally {
      await conn.close();
    }
  }

  Future<void> resetPassword(String dn, String newPassword) async {
    final conn = await _connect();
    try {
      final bytes = _encodePassword(newPassword);
      await conn.modify(_safeDn(dn), [Modification.replace('unicodePwd', [bytes])]);
    } finally {
      await conn.close();
    }
  }

  Future<void> setAccountDisabled(String dn, int currentUac, bool disable) async {
    final newUac = disable ? (currentUac | 2) : (currentUac & ~2);
    await modifyUser(dn, 'userAccountControl', newUac.toString());
  }

  Future<void> unlockAccount(String dn) async {
    await modifyUser(dn, 'lockoutTime', '0');
  }

  Future<int> getDomainMaxPwdAge() async {
    final conn = await _connect();
    try {
      final result = await conn.search(
        DN(config.baseDn),
        Filter.equals('objectClass', 'domainDNS'),
        ['maxPwdAge'],
      );
      await for (final entry in result.stream) {
        final attr = entry.attributes['maxPwdAge'];
        if (attr != null && attr.values.isNotEmpty) {
          final val = int.tryParse(_ldapStr(attr.values.first)) ?? 0;
          if (val < 0) return (-val / 10000000 / 86400).round();
        }
      }
    } catch (_) {
    } finally {
      await conn.close();
    }
    return 90;
  }

  Future<void> addUsersToGroup(List<String> userDns, String groupDn) async {
    final conn = await _connect();
    try {
      for (final userDn in userDns) {
        try {
          await conn.modify(_safeDn(groupDn), [Modification.add('member', [userDn])]);
        } catch (_) {}
      }
    } finally {
      await conn.close();
    }
  }

  Future<List<Map<String, dynamic>>> searchGroups(String query) async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      final filter = query.isEmpty
          ? Filter.and([
              Filter.equals('objectClass', 'group'),
              Filter.present('cn'),
            ])
          : Filter.and([
              Filter.equals('objectClass', 'group'),
              Filter.substring('cn', '*$query*'),
            ]);
      final attrs = ['cn', 'distinguishedName', 'description', 'member'];
      final searchResult = await conn.search(DN(config.baseDn), filter, attrs);
      await for (final entry in searchResult.stream) {
        final dn = entry.dn.toString();
        if (dn.isEmpty) continue;
        final map = <String, dynamic>{'dn': dn};
        for (final attr in entry.attributes.values) {
          if (attr.name == 'member') {
            map['memberCount'] = attr.values.length;
          } else {
            map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
          }
        }
        results.add(map);
      }
    } finally {
      await conn.close();
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getGroupMembers(String groupDn) async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      final groupResult = await conn.search(
        DN(config.baseDn),
        Filter.equals('distinguishedName', groupDn),
        ['member'],
      );
      final memberDns = <String>[];
      await for (final entry in groupResult.stream) {
        final attr = entry.attributes['member'];
        if (attr != null) memberDns.addAll(attr.values.map((v) => _ldapStr(v)));
      }
      for (final memberDn in memberDns) {
        try {
          final userResult = await conn.search(
            DN(config.baseDn),
            Filter.equals('distinguishedName', memberDn),
            ['cn', 'sAMAccountName', 'mail', 'telephoneNumber', 'department', 'title'],
          );
          await for (final entry in userResult.stream) {
            final dn = entry.dn.toString();
            if (dn.isEmpty) continue;
            final map = <String, dynamic>{'dn': dn};
            for (final attr in entry.attributes.values) {
              map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
            }
            results.add(map);
          }
        } catch (_) {}
      }
    } finally {
      await conn.close();
    }
    return results;
  }

  Future<void> addUserToGroup(String userDn, String groupDn) async {
    final conn = await _connect();
    try {
      await conn.modify(_safeDn(groupDn), [Modification.add('member', [userDn])]);
    } finally {
      await conn.close();
    }
  }

  Future<void> removeUserFromGroup(String userDn, String groupDn) async {
    final conn = await _connect();
    try {
      await conn.modify(_safeDn(groupDn), [Modification.delete('member', [userDn])]);
    } finally {
      await conn.close();
    }
  }

  Future<List<Map<String, dynamic>>> getOUs() async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      final filter = Filter.equals('objectClass', 'organizationalUnit');
      final attrs = ['ou', 'distinguishedName', 'description'];
      final searchResult = await conn.search(DN(config.baseDn), filter, attrs);
      await for (final entry in searchResult.stream) {
        final dn = entry.dn.toString();
        if (dn.isEmpty) continue;
        final map = <String, dynamic>{'dn': dn};
        for (final attr in entry.attributes.values) {
          map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
        }
        results.add(map);
      }
    } finally {
      await conn.close();
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getUsersInOu(String ouDn, {bool subtree = false}) async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      final filter = Filter.and([
        Filter.equals('objectClass', 'user'),
        Filter.equals('objectCategory', 'person'),
      ]);
      final attrs = ['cn', 'sAMAccountName', 'mail', 'department', 'userAccountControl', 'distinguishedName'];
      final searchResult = await conn.search(
        DN(ouDn), filter, attrs,
        scope: subtree ? SearchScope.SUB_LEVEL : SearchScope.ONE_LEVEL,
      );
      await for (final entry in searchResult.stream) {
        final dn = entry.dn.toString();
        if (dn.isEmpty) continue;
        final map = <String, dynamic>{'dn': dn};
        for (final attr in entry.attributes.values) {
          map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
        }
        results.add(map);
      }
    } finally {
      await conn.close();
    }
    return results;
  }

  Future<String> createUser({
    required String parentOuDn,
    required String givenName,
    required String sn,
    required String sAMAccountName,
    required String password,
    String? mail,
    String? department,
    String? title,
  }) async {
    final cn = '$givenName $sn';
    final domainParts = config.baseDn
        .split(',')
        .where((p) => p.toLowerCase().startsWith('dc='))
        .map((p) => p.substring(3))
        .join('.');
    final upn = '$sAMAccountName@$domainParts';
    final escapedCn = cn.replaceAll('\\', '\\\\').replaceAll(',', '\\,');
    final newDn = 'CN=$escapedCn,$parentOuDn';

    final conn = await _connect();
    try {
      final Map<String, dynamic> attrs = {
        'objectClass': ['top', 'person', 'organizationalPerson', 'user'],
        'cn': cn,
        'sAMAccountName': sAMAccountName,
        'userPrincipalName': upn,
        'givenName': givenName,
        'sn': sn,
        'displayName': cn,
        'userAccountControl': '514',
      };
      if (mail != null && mail.isNotEmpty) attrs['mail'] = mail;
      if (department != null && department.isNotEmpty) attrs['department'] = department;
      if (title != null && title.isNotEmpty) attrs['title'] = title;

      await conn.add(_safeDn(newDn), attrs);
      final pwdBytes = _encodePassword(password);
      await conn.modify(_safeDn(newDn), [Modification.replace('unicodePwd', [pwdBytes])]);
      await conn.modify(_safeDn(newDn), [Modification.replace('userAccountControl', ['512'])]);
      return newDn;
    } finally {
      await conn.close();
    }
  }

  Future<void> setPasswordMustChange(String dn) async {
    await modifyUser(dn, 'pwdLastSet', '0');
  }

  Future<void> setPwdNeverExpires(String dn, int currentUac, bool enable) async {
    const bit = 65536;
    final newUac = enable ? (currentUac | bit) : (currentUac & ~bit);
    await modifyUser(dn, 'userAccountControl', newUac.toString());
  }

  Future<void> setAccountExpiry(String dn, DateTime? expiry) async {
    final String value;
    if (expiry == null) {
      value = '9223372036854775807';
    } else {
      final unixMs = expiry.millisecondsSinceEpoch;
      final fileTime = (unixMs + 11644473600000) * 10000;
      value = fileTime.toString();
    }
    await modifyUser(dn, 'accountExpires', value);
  }

  Future<List<Map<String, dynamic>>> findGroupByName(String name) async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      final filter = Filter.and([
        Filter.equals('objectClass', 'group'),
        Filter.substring('cn', '*$name*'),
      ]);
      final searchResult = await conn.search(DN(config.baseDn), filter, ['cn', 'distinguishedName']);
      await for (final entry in searchResult.stream) {
        final dn = entry.dn.toString();
        if (dn.isEmpty) continue;
        final map = <String, dynamic>{'dn': dn};
        for (final attr in entry.attributes.values) {
          map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
        }
        results.add(map);
      }
    } finally {
      await conn.close();
    }
    return results;
  }

  // ── FEATURE 1: Dashboard Stats ───────────────────────────────────────────────

  Future<Map<String, int>> getDashboardStats() async {
    final conn = await _connect();
    var total = 0, disabled = 0, locked = 0;
    try {
      final filter = Filter.and([
        Filter.equals('objectClass', 'user'),
        Filter.equals('objectCategory', 'person'),
        Filter.present('sAMAccountName'),
      ]);
      final entries = await _pagedSearch(conn, filter, ['userAccountControl', 'lockoutTime']);
      for (final entry in entries) {
        total++;
        final uac = int.tryParse(
            entry.attributes['userAccountControl']?.values.first.toString() ?? '0') ?? 0;
        final lt = int.tryParse(
            entry.attributes['lockoutTime']?.values.first.toString() ?? '0') ?? 0;
        if ((uac & 2) != 0) disabled++;
        if (lt > 0) locked++;
      }
    } finally {
      await conn.close();
    }
    return {'total': total, 'disabled': disabled, 'locked': locked};
  }

  // ── FEATURE 2: Schnellansichten ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getLockedUsers() async {
    final all = await searchUsers('');
    final locked = all.where((u) {
      final lt = int.tryParse(u['lockoutTime']?.toString() ?? '0') ?? 0;
      return lt > 0;
    }).toList();
    return locked;
  }

  Future<List<Map<String, dynamic>>> getDisabledUsers() async {
    final all = await searchUsers('');
    final disabled = all.where((u) {
      final uac = int.tryParse(u['userAccountControl']?.toString() ?? '0') ?? 0;
      return (uac & 2) != 0;
    }).toList();
    return disabled;
  }

  Future<List<Map<String, dynamic>>> getUsersExpiringPasswords({int withinDays = 14}) async {
    final maxPwdAgeDays = await getDomainMaxPwdAge();
    final all = await searchUsers('');
    final now = DateTime.now();
    final results = <Map<String, dynamic>>[];
    for (final u in all) {
      final uac = int.tryParse(u['userAccountControl']?.toString() ?? '0') ?? 0;
      if ((uac & 2) != 0) continue; // skip disabled
      if ((uac & 65536) != 0) continue; // skip pwdNeverExpires
      final pwdLastSetStr = u['pwdLastSet']?.toString() ?? '0';
      final ft = int.tryParse(pwdLastSetStr) ?? 0;
      if (ft <= 0) continue;
      final unixMs = (ft ~/ 10000) - 11644473600000;
      if (unixMs <= 0) continue;
      final setDate = DateTime.fromMillisecondsSinceEpoch(unixMs, isUtc: true).toLocal();
      final expiry = setDate.add(Duration(days: maxPwdAgeDays));
      final daysLeft = expiry.difference(now).inDays;
      if (daysLeft >= 0 && daysLeft <= withinDays) {
        results.add({...u, '_daysLeft': daysLeft});
      }
    }
    results.sort((a, b) => (a['_daysLeft'] as int).compareTo(b['_daysLeft'] as int));
    return results;
  }

  // ── FEATURE 5: User verschieben ──────────────────────────────────────────────

  Future<void> moveUser(String userDn, String targetOuDn) async {
    final conn = await _connect();
    try {
      final rdn = _firstRdn(userDn);
      await conn.modifyDN(_safeDn(userDn), _safeDn(rdn), newSuperior: _safeDn(targetOuDn));
    } finally {
      await conn.close();
    }
  }

  // Erstes RDN-Element extrahieren, escaped Kommas (\,) überspringen
  static String _firstRdn(String dn) {
    for (int i = 0; i < dn.length; i++) {
      if (dn[i] == ',' && (i == 0 || dn[i - 1] != '\\')) return dn.substring(0, i);
    }
    return dn;
  }

  // ── FEATURE 6: Gruppen erstellen + löschen ──────────────────────────────────

  Future<String> createGroup(String name, String ouDn, {String? description}) async {
    final escapedCn = name.replaceAll('\\', '\\\\').replaceAll(',', '\\,');
    final newDn = 'CN=$escapedCn,$ouDn';
    final conn = await _connect();
    try {
      final Map<String, dynamic> attrs = {
        'objectClass': ['top', 'group'],
        'cn': name,
        'sAMAccountName': name,
        'groupType': '-2147483646',
      };
      if (description != null && description.isNotEmpty) {
        attrs['description'] = description;
      }
      await conn.add(_safeDn(newDn), attrs);
      return newDn;
    } finally {
      await conn.close();
    }
  }

  Future<void> deleteGroup(String groupDn) async {
    final conn = await _connect();
    try {
      await conn.delete(_safeDn(groupDn));
    } finally {
      await conn.close();
    }
  }

  // ── FEATURE 7: Bulk-Aktionen ─────────────────────────────────────────────────

  Future<void> bulkUnlock(List<String> dns) async {
    final conn = await _connect();
    try {
      for (final dn in dns) {
        try {
          await conn.modify(_safeDn(dn), [Modification.replace('lockoutTime', ['0'])]);
        } catch (_) {}
      }
    } finally {
      await conn.close();
    }
  }

  Future<void> bulkSetDisabled(List<String> dns, bool disable) async {
    for (final dn in dns) {
      try {
        final user = await getUserDetails(dn);
        if (user == null) continue;
        final uac = int.tryParse(user['userAccountControl']?.toString() ?? '512') ?? 512;
        await setAccountDisabled(dn, uac, disable);
      } catch (_) {}
    }
  }

  // ── Feature: Inaktive User ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getInactiveUsers({int days = 90}) async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      final cutoffMs = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
      final cutoffFt = (cutoffMs + 11644473600000) * 10000;
      final filter = Filter.and([
        Filter.equals('objectCategory', 'person'),
        Filter.equals('objectClass', 'user'),
        _notFilter(_extMatch('userAccountControl', '1.2.840.113556.1.4.803', '2')),
        Filter.lessOrEquals('lastLogonTimestamp', cutoffFt.toString()),
      ]);
      final attrs = ['cn', 'sAMAccountName', 'lastLogonTimestamp', 'distinguishedName'];
      final searchResult = await conn.search(DN(config.baseDn), filter, attrs);
      await for (final entry in searchResult.stream) {
        final dn = entry.dn.toString();
        if (dn.isEmpty) continue;
        final map = <String, dynamic>{'dn': dn};
        for (final attr in entry.attributes.values) {
          map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
        }
        results.add(map);
      }
    } finally {
      await conn.close();
    }
    results.sort((a, b) =>
        (a['lastLogonTimestamp']?.toString() ?? '0')
            .compareTo(b['lastLogonTimestamp']?.toString() ?? '0'));
    return results;
  }

  // ── Feature: Service-Accounts ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getServiceAccounts() async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      final filter = Filter.and([
        Filter.equals('objectCategory', 'person'),
        Filter.equals('objectClass', 'user'),
      ]);
      final attrs = ['cn', 'sAMAccountName', 'description', 'pwdLastSet',
                     'distinguishedName', 'userAccountControl'];
      final searchResult = await conn.search(DN(config.baseDn), filter, attrs);
      await for (final entry in searchResult.stream) {
        final dn = entry.dn.toString();
        if (dn.isEmpty) continue;
        // Nur Konten die NICHT in einer OU=Benutzer liegen
        final parts = dn.split(',').map((p) => p.trim().toLowerCase()).toList();
        const _excludedOus = {
          'ou=benutzer',
          'ou=benutzer_ohne_redirection',
          'ou=so_tu_user',
          'ou=so_tu_user_365',
          'ou=so_tu_admin_user',
        };
        if (parts.any((p) => _excludedOus.contains(p))) continue;
        final map = <String, dynamic>{'dn': dn};
        for (final attr in entry.attributes.values) {
          map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
        }
        results.add(map);
      }
    } finally {
      await conn.close();
    }
    results.sort((a, b) =>
        (a['cn'] ?? '').toString().compareTo((b['cn'] ?? '').toString()));
    return results;
  }

  // ── Feature: Accounts ohne E-Mail ────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getUsersWithoutEmail() async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      final filter = Filter.and([
        Filter.equals('objectCategory', 'person'),
        Filter.equals('objectClass', 'user'),
        _notFilter(Filter.present('mail')),
      ]);
      final attrs = ['cn', 'sAMAccountName', 'department', 'userAccountControl', 'distinguishedName'];
      final searchResult = await conn.search(DN(config.baseDn), filter, attrs);
      await for (final entry in searchResult.stream) {
        final dn = entry.dn.toString();
        if (dn.isEmpty) continue;
        final map = <String, dynamic>{'dn': dn};
        for (final attr in entry.attributes.values) {
          map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
        }
        results.add(map);
      }
    } finally {
      await conn.close();
    }
    results.sort((a, b) =>
        (a['cn'] ?? '').toString().compareTo((b['cn'] ?? '').toString()));
    return results;
  }

  // ── Feature: Passwort-Policy ─────────────────────────────────────────────────

  Future<Map<String, String>> getPasswordPolicy() async {
    final conn = await _connect();
    final result = <String, String>{};
    try {
      final searchResult = await conn.search(
        DN(config.baseDn),
        Filter.equals('objectClass', 'domainDNS'),
        ['minPwdLength', 'pwdHistoryLength', 'maxPwdAge', 'minPwdAge',
         'lockoutThreshold', 'lockoutDuration', 'lockoutObservationWindow', 'pwdProperties'],
        scope: SearchScope.ONE_LEVEL,
      );
      await for (final entry in searchResult.stream) {
        for (final attr in entry.attributes.values) {
          result[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
        }
        break;
      }
    } catch (_) {
      // Try with SUB_LEVEL if ONE_LEVEL fails
      try {
        final searchResult2 = await conn.search(
          DN(config.baseDn),
          Filter.equals('objectClass', 'domainDNS'),
          ['minPwdLength', 'pwdHistoryLength', 'maxPwdAge', 'minPwdAge',
           'lockoutThreshold', 'lockoutDuration', 'lockoutObservationWindow', 'pwdProperties'],
        );
        await for (final entry in searchResult2.stream) {
          for (final attr in entry.attributes.values) {
            result[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
          }
          break;
        }
      } catch (_) {}
    } finally {
      await conn.close();
    }
    return result;
  }

  // ── Feature: Computer-Browser ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getComputers() async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      final filter = Filter.equals('objectClass', 'computer');
      final attrs = ['cn', 'dNSHostName', 'operatingSystem', 'operatingSystemVersion',
                     'lastLogonTimestamp', 'description', 'distinguishedName'];
      final searchResult = await conn.search(DN(config.baseDn), filter, attrs);
      final prefixes = config.computerPrefixes;
      await for (final entry in searchResult.stream) {
        final dn = entry.dn.toString();
        if (dn.isEmpty) continue;
        final map = <String, dynamic>{'dn': dn};
        for (final attr in entry.attributes.values) {
          map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
        }
        if (prefixes.isNotEmpty) {
          final cn = (map['cn'] ?? '').toString().toLowerCase();
          if (!prefixes.any((p) => cn.startsWith(p))) continue;
        }
        results.add(map);
      }
    } finally {
      await conn.close();
    }
    results.sort((a, b) =>
        (a['cn'] ?? '').toString().compareTo((b['cn'] ?? '').toString()));
    return results;
  }

  // ── Feature: Verschachtelte Gruppen ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getEffectiveGroups(String userDn) async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      // Get direct memberships first
      final directResult = await conn.search(
        DN(config.baseDn),
        Filter.equals('distinguishedName', userDn),
        ['memberOf'],
      );
      final directGroups = <String>{};
      await for (final entry in directResult.stream) {
        final attr = entry.attributes['memberOf'];
        if (attr != null) {
          for (final v in attr.values) {
            directGroups.add(v.toString().toLowerCase());
          }
        }
      }

      // Get all groups (including nested) via recursive LDAP filter
      final filter = Filter.and([
        Filter.equals('objectClass', 'group'),
        _extMatch('member', '1.2.840.113556.1.4.1941', userDn),
      ]);
      final searchResult = await conn.search(
        DN(config.baseDn), filter, ['cn', 'distinguishedName'],
      );
      await for (final entry in searchResult.stream) {
        final dn = entry.dn.toString();
        if (dn.isEmpty) continue;
        final map = <String, dynamic>{'dn': dn};
        for (final attr in entry.attributes.values) {
          map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
        }
        map['isDirect'] = directGroups.contains(dn.toLowerCase());
        results.add(map);
      }
    } finally {
      await conn.close();
    }
    results.sort((a, b) =>
        (a['cn'] ?? '').toString().compareTo((b['cn'] ?? '').toString()));
    return results;
  }

  // ── Feature: CSV Bulk-Update ─────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> bulkUpdateFromCsv(
      List<String> headers, List<List<String>> rows) async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      for (final row in rows) {
        if (row.isEmpty) continue;
        final sam = row[0].trim();
        if (sam.isEmpty) continue;
        final result = <String, dynamic>{'sam': sam, 'success': false};
        try {
          // Find user DN
          final searchResult = await conn.search(
            DN(config.baseDn),
            Filter.equals('sAMAccountName', sam),
            ['distinguishedName'],
          );
          String? userDn;
          await for (final entry in searchResult.stream) {
            if (entry.dn.toString().isNotEmpty) {
              userDn = entry.dn.toString();
              break;
            }
          }
          if (userDn == null) {
            result['error'] = 'User nicht gefunden';
            results.add(result);
            continue;
          }
          // Build modifications
          final mods = <Modification>[];
          for (var i = 1; i < headers.length && i < row.length; i++) {
            final attr = headers[i].trim();
            final val = row[i].trim();
            if (attr.isNotEmpty) {
              mods.add(Modification.replace(attr, [val]));
            }
          }
          if (mods.isNotEmpty) {
            await conn.modify(_safeDn(userDn), mods);
          }
          result['success'] = true;
          result['dn'] = userDn;
          results.add(result);
        } catch (e) {
          result['error'] = e.toString();
          results.add(result);
        }
      }
    } finally {
      await conn.close();
    }
    return results;
  }

  // ── Feature: Org-Chart ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getOrgChartUser(String dn) async {
    final conn = await _connect();
    try {
      final attrs = ['cn', 'title', 'department', 'manager', 'directReports',
                     'thumbnailPhoto', 'jpegPhoto', 'userAccountControl', 'sAMAccountName'];
      final result = await conn.search(
        DN(config.baseDn),
        Filter.equals('distinguishedName', dn),
        attrs,
      );
      Map<String, dynamic>? map;
      await for (final entry in result.stream) {
        if (entry.dn.toString().isEmpty) continue;
        map = {'dn': entry.dn.toString()};
        for (final attr in entry.attributes.values) {
          if ((attr.name == 'jpegPhoto' || attr.name == 'thumbnailPhoto') && attr.values.isNotEmpty) {
            try {
              final bytes = (attr.values.first as dynamic).valueBytes() as Uint8List;
              final mime = _detectMime(bytes);
              map['jpegPhoto'] = 'data:$mime;base64,${base64Encode(bytes)}';
            } catch (_) {}
          } else if (attr.name == 'directReports') {
            map['directReports'] = attr.values.map((v) => _ldapStr(v)).toList();
          } else {
            map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
          }
        }
        break;
      }
      return map;
    } finally {
      await conn.close();
    }
  }

  Future<Map<String, dynamic>?> getOrgChartUserByDn(String dn) async {
    return getOrgChartUser(dn);
  }

  // ── Feature: Telefonverzeichnis ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPhoneDirectory() async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      final filter = Filter.and([
        Filter.equals('objectClass', 'user'),
        Filter.equals('objectCategory', 'person'),
        Filter.present('sAMAccountName'),
        Filter.or([
          Filter.present('telephoneNumber'),
          Filter.present('mobile'),
        ]),
      ]);
      final attrs = ['cn', 'sAMAccountName', 'telephoneNumber', 'mobile',
                     'department', 'mail', 'title', 'userAccountControl', 'distinguishedName'];
      final searchResult = await conn.search(DN(config.baseDn), filter, attrs);
      await for (final entry in searchResult.stream) {
        final dn = entry.dn.toString();
        if (dn.isEmpty) continue;
        final map = <String, dynamic>{'dn': dn};
        for (final attr in entry.attributes.values) {
          map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
        }
        results.add(map);
      }
    } finally {
      await conn.close();
    }
    results.sort((a, b) =>
        (a['cn'] ?? '').toString().compareTo((b['cn'] ?? '').toString()));
    return results;
  }

  // ── Feature: Ablaufende Accounts ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getExpiringAccounts({int withinDays = 30}) async {
    final all = await searchUsers('');
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: withinDays));
    final results = <Map<String, dynamic>>[];
    for (final u in all) {
      final ft = int.tryParse(u['accountExpires']?.toString() ?? '0') ?? 0;
      // 0 = never, 9223372036854775807 = never
      if (ft <= 0 || ft == 9223372036854775807) continue;
      // Konvertierung: Windows FILETIME → DateTime
      final unixMs = (ft ~/ 10000) - 11644473600000;
      if (unixMs <= 0) continue;
      final expiry = DateTime.fromMillisecondsSinceEpoch(unixMs, isUtc: true).toLocal();
      if (expiry.isBefore(now)) continue; // bereits abgelaufen
      if (expiry.isAfter(cutoff)) continue; // weiter weg als 30 Tage
      final daysLeft = expiry.difference(now).inDays;
      results.add({...u, '_expiry': expiry, '_daysLeft': daysLeft});
    }
    results.sort((a, b) => (a['_daysLeft'] as int).compareTo(b['_daysLeft'] as int));
    return results;
  }

  // ── Feature: Bulk PW-Reset ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getActiveUsers() async {
    final all = await searchUsers('');
    return all.where((u) {
      final uac = int.tryParse(u['userAccountControl']?.toString() ?? '0') ?? 0;
      return (uac & 2) == 0; // nicht deaktiviert
    }).toList();
  }

  Future<Map<String, dynamic>> bulkPwdReset(List<String> dns) async {
    final success = <String>[];
    final errors = <String, String>{};
    for (final dn in dns) {
      try {
        await modifyUser(dn, 'pwdLastSet', '0');
        success.add(dn);
      } catch (e) {
        errors[dn] = e.toString();
      }
    }
    return {'success': success, 'errors': errors};
  }

  // ── Feature: Alle User für Export ───────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAllUsersForExport() async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      final filter = Filter.and([
        Filter.equals('objectClass', 'user'),
        Filter.equals('objectCategory', 'person'),
        Filter.present('sAMAccountName'),
      ]);
      final attrs = [
        'cn', 'sAMAccountName', 'mail', 'department', 'title',
        'telephoneNumber', 'mobile', 'userAccountControl', 'lockoutTime',
        'lastLogonTimestamp', 'distinguishedName',
      ];
      final searchResult = await conn.search(DN(config.baseDn), filter, attrs);
      await for (final entry in searchResult.stream) {
        final dn = entry.dn.toString();
        if (dn.isEmpty) continue;
        final map = <String, dynamic>{'dn': dn};
        for (final attr in entry.attributes.values) {
          map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
        }
        results.add(map);
      }
    } finally {
      await conn.close();
    }
    results.sort((a, b) =>
        (a['cn'] ?? '').toString().compareTo((b['cn'] ?? '').toString()));
    return results;
  }

  // ── Feature: Erweiterte Suche ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> advancedSearch({
    String? name,
    String? department,
    String? ouDn,
    String? groupName,
    String status = 'all',
  }) async {
    final conn = await _connect();
    final results = <Map<String, dynamic>>[];
    try {
      final filters = <Filter>[
        Filter.equals('objectCategory', 'person'),
        Filter.equals('objectClass', 'user'),
      ];

      if (name != null && name.isNotEmpty) {
        filters.add(Filter.or([
          Filter.substring('cn', '*$name*'),
          Filter.substring('sAMAccountName', '*$name*'),
        ]));
      }
      if (department != null && department.isNotEmpty) {
        filters.add(Filter.substring('department', '*$department*'));
      }
      if (status == 'active') {
        filters.add(_notFilter(_extMatch('userAccountControl', '1.2.840.113556.1.4.803', '2')));
      } else if (status == 'disabled') {
        filters.add(_extMatch('userAccountControl', '1.2.840.113556.1.4.803', '2'));
      }

      final filter = filters.length == 1 ? filters.first : Filter.and(filters);
      final attrs = ['cn', 'sAMAccountName', 'mail', 'department', 'userAccountControl',
                     'lockoutTime', 'distinguishedName'];
      final searchDn = (ouDn != null && ouDn.isNotEmpty) ? DN(ouDn) : DN(config.baseDn);
      final searchResult = await conn.search(searchDn, filter, attrs,
        scope: SearchScope.SUB_LEVEL);
      await for (final entry in searchResult.stream) {
        final dn = entry.dn.toString();
        if (dn.isEmpty) continue;
        final map = <String, dynamic>{'dn': dn};
        for (final attr in entry.attributes.values) {
          map[attr.name] = attr.values.isNotEmpty ? _ldapStr(attr.values.first) : '';
        }
        results.add(map);
      }
    } finally {
      await conn.close();
    }

    // Filter locked after fetching (can't do it in LDAP filter easily)
    if (status == 'locked') {
      return results.where((u) {
        final lt = int.tryParse(u['lockoutTime']?.toString() ?? '0') ?? 0;
        return lt > 0;
      }).toList();
    }

    results.sort((a, b) =>
        (a['cn'] ?? '').toString().compareTo((b['cn'] ?? '').toString()));
    return results;
  }
}

// Passwort UTF-16LE kodieren mit umgebenden Anführungszeichen (AD-Anforderung)
Uint8List _encodePassword(String password) {
  final quoted = '"$password"';
  final builder = BytesBuilder();
  for (final unit in quoted.codeUnits) {
    builder.addByte(unit & 0xFF);
    builder.addByte((unit >> 8) & 0xFF);
  }
  return builder.toBytes();
}

String _detectMime(Uint8List bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return 'image/jpeg';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return 'image/gif';
  }
  return 'image/jpeg';
}
