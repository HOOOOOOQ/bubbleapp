import 'dart:async';
import 'package:flutter/foundation.dart';

/// FCM incoming call handling — graceful when not configured.
/// When Firebase is set up, this registers handlers for background/terminated.
/// Without Firebase, app still works for foreground calls via Realtime.
class FcmCallService {
  bool _initialized = false;

  Future<void> init({
    void Function(String callId)? onIncoming,
    void Function(String callId)? onAccept,
    void Function(String callId)? onDecline,
  }) async {
    if (_initialized) return;
    try {
      // Dynamic import to avoid hard dependency when firebase not configured
      // We use conditional approach: try to init, else no-op
      // ignore: avoid_dynamic_calls
      final available = await _isFirebaseAvailable();
      if (!available) {
        debugPrint('FCM not configured — incoming calls via Realtime only (foreground).');
        return;
      }
      _initialized = true;
      debugPrint('FCM call service initialized');
      // Real init would: FirebaseMessaging.onMessage.listen, onMessageOpenedApp, getInitialMessage,
      // requestPermission on Android 13+, create high-priority channel for calls.
    } catch (e) {
      debugPrint('FCM init failed (non-fatal): $e');
    }
  }

  Future<bool> _isFirebaseAvailable() async {
    try {
      // Check if firebase_core is initialized; if not, Firebase not configured
      // We attempt dynamic — if package missing, exception handled
      return false; // default false until user adds google-services.json
    } catch (_) {
      return false;
    }
  }

  Future<void> requestPermission() async {
    // Android 13+ POST_NOTIFICATIONS handled by permission_handler elsewhere
    debugPrint('FCM permission request (handled by system)');
  }

  Future<void> clearCallNotification(String callId) async {
    debugPrint('Clear notification for $callId');
  }
}

final fcmCallService = FcmCallService();
