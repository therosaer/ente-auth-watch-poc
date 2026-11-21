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
class WatchSyncService {
  WatchSyncService._();
  static final instance = WatchSyncService._();

  static const _prefKey = 'watch_sync_enabled';
  static const _channel = MethodChannel('io.ente.auth/watch');
  final _logger = Logger('WatchSyncService');

  SharedPreferences? _prefs;
  Timer? _debounce;

  bool get isEnabled => _prefs?.getBool(_prefKey) ?? true;

  Future<void> init() async {
    if (!Platform.isIOS) return;
    _prefs = await SharedPreferences.getInstance();
    Bus.instance.on<CodesUpdatedEvent>().listen((_) => _schedule());
    _schedule();
  }

  Future<void> setEnabled(bool value) async {
    await _prefs?.setBool(_prefKey, value);
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => sync().ignore());
  }

  Future<void> sync() async {
    try {
      final urls = <String>[];
      if (isEnabled) {
        final codes = await CodeStore.instance.getAllCodes();
        for (final Code c in codes) {
          if (c.hasError || c.isTrashed) continue;
          if (c.type == Type.totp || c.type == Type.steam) {
            urls.add(c.rawData);
          }
        }
      }
      await _channel.invokeMethod('syncCodes', urls);
    } catch (e, s) {
      _logger.warning('Watch sync failed', e, s);
    }
  }
}
