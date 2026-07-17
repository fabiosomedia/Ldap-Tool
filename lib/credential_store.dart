import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

const _target = 'LDAPatschifig/AD_Bind';
const _targetLegacy = 'Lapi/AD_Bind';

/// Liest das AD-Bind-Passwort aus dem Windows Credential Manager.
/// Gibt null zurück wenn kein Eintrag gefunden.
String? readCredential() {
  return using((arena) {
    // Erst unter neuem Namen suchen, dann unter altem (Migration)
    for (final name in [_target, _targetLegacy]) {
      final targetPtr = name.toNativeUtf16(allocator: arena);
      final ppCred = arena<Pointer<CREDENTIAL>>();
      if (CredRead(targetPtr, CRED_TYPE_GENERIC, 0, ppCred) == FALSE) continue;

      final pCred = ppCred.value;
      final size = pCred.ref.CredentialBlobSize;
      if (size == 0) { CredFree(pCred); continue; }

      final bytes = Uint8List.fromList(
        pCred.ref.CredentialBlob.cast<Uint8>().asTypedList(size),
      );
      CredFree(pCred);
      final password = utf8.decode(bytes);
      // Falls unter altem Namen gefunden → unter neuem Namen migrieren
      if (name == _targetLegacy) {
        try { writeCredential('', password); } catch (_) {}
      }
      return password;
    }
    return null;
  });
}

/// Speichert das AD-Bind-Passwort im Windows Credential Manager.
/// [username] wird als Benutzername-Label angezeigt (z.B. CN=admin_brf,...).
void writeCredential(String username, String password) {
  using((arena) {
    final targetPtr = _target.toNativeUtf16(allocator: arena);
    final userPtr = username.toNativeUtf16(allocator: arena);
    final blobBytes = utf8.encode(password);
    final blobPtr = arena<Uint8>(blobBytes.length);
    for (var i = 0; i < blobBytes.length; i++) blobPtr[i] = blobBytes[i];

    final pCred = arena<CREDENTIAL>();
    pCred.ref.Type = CRED_TYPE_GENERIC;
    pCred.ref.TargetName = targetPtr;
    pCred.ref.UserName = userPtr;
    pCred.ref.CredentialBlobSize = blobBytes.length;
    pCred.ref.CredentialBlob = blobPtr.cast();
    pCred.ref.Persist = CRED_PERSIST_LOCAL_MACHINE;

    if (CredWrite(pCred, 0) == FALSE) {
      throw Exception(
        'Credential Manager: Speichern fehlgeschlagen (Error ${GetLastError()})',
      );
    }
  });
}

/// Löscht den Credential Manager Eintrag.
void deleteCredential() {
  using((arena) {
    final targetPtr = _target.toNativeUtf16(allocator: arena);
    CredDelete(targetPtr, CRED_TYPE_GENERIC, 0);
  });
}
