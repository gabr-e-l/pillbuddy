// lib/services/caregiver_intake_cache.dart
//
// Singleton cache that tracks the last-seen intake status for every
// (patientUid, medId, date) tuple — persisted to SharedPreferences so
// it survives the app being killed and cold-started.
//
// WHY THIS EXISTS
// ───────────────
// The original instance-level _lastIntakes map on _PatientCardState reset
// to {} whenever Flutter disposed the widget (navigation away, app restart).
// Every cold start caused a flood of "duplicate" notifications because all
// current intakes looked new again.
//
// Using a singleton backed by SharedPreferences means:
//   • In-memory: survives navigation / widget rebuilds (same process).
//   • On-disk: survives app being killed and reopened.
//   • Keyed by date: naturally expires at midnight — next-day intakes
//     are always genuinely new.
//   • Cleared on sign-out: a fresh login starts with a clean slate.

import 'package:shared_preferences/shared_preferences.dart';

class CaregiverIntakeCache {
  CaregiverIntakeCache._();
  static final CaregiverIntakeCache instance = CaregiverIntakeCache._();

  static const _prefix = 'cic_'; // caregiver intake cache key prefix

  // In-memory layer — avoids hitting SharedPreferences on every stream tick.
  final Map<String, String> _mem = {};

  // Whether we have loaded persisted data from disk for this session.
  bool _loaded = false;

  /// Must be called once early in the app lifecycle (e.g. after init() in
  /// NotificationService or in main()). Safe to call multiple times.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final today = _todayStr();
    // Load only today's entries; anything older is stale and can be ignored.
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      // Key format: cic_<patientUid>|<medId>|<date>
      final inner = key.substring(_prefix.length);
      if (!inner.endsWith('|$today')) continue;
      final value = prefs.getString(key);
      if (value != null) _mem[inner] = value;
    }
    // Prune stale keys from prefs (keep storage tidy).
    await _pruneOldEntries(prefs, today);
  }

  /// Returns true if this (patient, med, date, status) combination has NOT
  /// been seen before — i.e., the status changed and a notification should
  /// fire. Automatically updates both the in-memory map and SharedPreferences.
  Future<bool> shouldNotify({
    required String patientUid,
    required String medId,
    required String date,
    required String status,
  }) async {
    await load(); // no-op if already loaded
    final inner = '$patientUid|$medId|$date';
    if (_mem[inner] == status) return false;
    _mem[inner] = status;
    // Persist asynchronously — we don't need to await to return the result.
    _persist(inner, status);
    return true;
  }

  /// Call this on sign-out so a fresh login starts with a clean slate.
  Future<void> clear() async {
    _mem.clear();
    _loaded = false;
    final prefs = await SharedPreferences.getInstance();
    final toRemove = prefs.getKeys()
        .where((k) => k.startsWith(_prefix))
        .toList();
    for (final k in toRemove) {
      await prefs.remove(k);
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _persist(String inner, String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$inner', status);
  }

  Future<void> _pruneOldEntries(SharedPreferences prefs, String today) async {
    final stale = prefs.getKeys().where((k) {
      if (!k.startsWith(_prefix)) return false;
      final inner = k.substring(_prefix.length);
      // inner ends with |<date>; keep only today's
      return !inner.endsWith('|$today');
    }).toList();
    for (final k in stale) {
      await prefs.remove(k);
    }
  }
}