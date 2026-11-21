import 'dart:async';
import 'dart:io';

import 'package:ente_auth/events/codes_updated_event.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_events/event_bus.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Syncs TOTP/Steam codes to the Apple Watch app (iOS only).
///
/// Sync is opt-in: nothing leaves the phone until the user turns it on in
/// Settings > Security. Turning it off or logging out tells the watch to wipe
/// its copy.
class WatchSyncService {
  WatchSyncService._();
  static final instance = WatchSyncService._();

  static const _prefKey = 'watch_sync_enabled';
  static const _channel = MethodChannel('io.ente.auth/watch');
  final _logger = Logger('WatchSyncService');

  SharedPreferences? _prefs;
  Timer? _debounce;

  bool get isSupported => Platform.isIOS;

  bool get isEnabled => _prefs?.getBool(_prefKey) ?? false;

  Future<void> init() async {
    if (!isSupported) return;
    _prefs = await SharedPreferences.getInstance();
    Bus.instance.on<CodesUpdatedEvent>().listen((_) => _schedule());
    _schedule();
  }

  Future<void> setEnabled(bool value) async {
    if (!isSupported) return;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_prefKey, value);
    _debounce?.cancel();
    await sync();
  }

  /// Turns sync off and wipes the watch. Called on logout.
  Future<void> clear() async {
    if (!isSupported) return;
    _debounce?.cancel();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_prefKey, false);
    await _send(enabled: false, codes: const []);
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => sync().ignore());
  }

  Future<void> sync() async {
    if (!isSupported) return;
    final enabled = isEnabled;
    final urls = <String>[];
    if (enabled) {
      try {
        final codes = await CodeStore.instance.getAllCodes();
        for (final Code c in codes) {
          if (c.hasError || c.isTrashed) continue;
          if (c.type == Type.totp || c.type == Type.steam) {
            urls.add(c.rawData);
          }
        }
      } catch (e, s) {
        _logger.warning('Could not load codes for watch sync', e, s);
        return;
      }
    }
    await _send(enabled: enabled, codes: urls);
  }

  Future<void> _send({
    required bool enabled,
    required List<String> codes,
  }) async {
    try {
      await _channel.invokeMethod('syncCodes', {
        'enabled': enabled,
        'codes': enabled ? codes : const <String>[],
      });
    } catch (e, s) {
      _logger.warning('Watch sync failed', e, s);
    }
  }
}
