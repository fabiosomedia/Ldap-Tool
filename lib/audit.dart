import 'dart:convert';
import 'dart:io';

class AuditEntry {
  final DateTime timestamp;
  final String actor;
  final String action;
  final String targetDn;
  final String details;

  AuditEntry(this.actor, this.action, this.targetDn, this.details)
      : timestamp = DateTime.now();

  AuditEntry._internal(this.timestamp, this.actor, this.action, this.targetDn, this.details);

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'actor': actor,
    'action': action,
    'targetDn': targetDn,
    'details': details,
  };

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry._internal(
    DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
    j['actor'] as String? ?? '',
    j['action'] as String? ?? '',
    j['targetDn'] as String? ?? '',
    j['details'] as String? ?? '',
  );
}

final _log = <AuditEntry>[];
bool _auditLoaded = false;

final _auditFile = File(
  '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}audit.jsonl');

void _loadAuditLog() {
  if (_auditLoaded) return;
  _auditLoaded = true;
  if (!_auditFile.existsSync()) return;
  try {
    final lines = _auditFile.readAsLinesSync();
    // Load last 1000 lines (most recent)
    final toLoad = lines.length > 1000 ? lines.sublist(lines.length - 1000) : lines;
    for (final line in toLoad.reversed) {
      if (line.trim().isEmpty) continue;
      try {
        final entry = AuditEntry.fromJson(jsonDecode(line) as Map<String, dynamic>);
        _log.add(entry);
      } catch (_) {}
    }
  } catch (_) {}
}

void auditLog(String actor, String action, String targetDn, [String details = '']) {
  _loadAuditLog();
  final entry = AuditEntry(actor, action, targetDn, details);
  _log.insert(0, entry);
  if (_log.length > 1000) _log.removeLast();
  // Append to JSONL file
  try {
    _auditFile.writeAsStringSync('${jsonEncode(entry.toJson())}\n', mode: FileMode.append);
  } catch (_) {}
}

List<AuditEntry> getAuditLog() {
  _loadAuditLog();
  return List.unmodifiable(_log);
}
