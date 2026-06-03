import 'dart:io';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../network/api_client.dart';
import '../../../core/storage/secure_storage_service.dart';

/// Global background message handler (must be a top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📩 FCM Background message: ${message.messageId}');
}

/// Centralized service for Firebase Cloud Messaging (FCM) integration.
/// - Gets/refreshes the device token
/// - Sends the token to the backend
/// - Handles foreground, background, and terminated notifications
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    'shrimpbite_high_importance',
    'Shrimpbite Notifications',
    description: 'Important notifications for orders, OTPs, and updates',
    importance: Importance.max,
  );

  /// Stream to allow other parts of the app (like MainPage) to listen for specific FCM events
  static final StreamController<RemoteMessage> onMessageReceived =
      StreamController<RemoteMessage>.broadcast();

  // ── Initialise (call once from main.dart after Firebase.initializeApp) ────

  static Future<void> init() async {
    // Register the background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Create Android notification channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    // Init local notifications plugin
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // will request via FCM below
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Request permission
    await FCMService().requestPermission();

    // Handle foreground messages — show as local notification
    FirebaseMessaging.onMessage.listen((message) {
      onMessageReceived.add(message);
      FCMService()._showLocalNotification(message);
    });
  }

  // ── Permission ─────────────────────────────────────────────────────────────

  Future<void> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint(
        '🔔 FCM Permission: ${settings.authorizationStatus.name.toUpperCase()}');
  }

  // ── Token ──────────────────────────────────────────────────────────────────

  /// Gets the current FCM token. Returns null if not available.
  Future<String?> getToken() async {
    try {
      if (Platform.isIOS) {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken == null) return null;
      }

      // Try up to 3 times to mitigate SERVICE_NOT_AVAILABLE errors
      for (int i = 0; i < 3; i++) {
        try {
          final token = await _messaging.getToken();
          if (token != null) {
            debugPrint('📱 FCM Token: $token');
            return token;
          }
        } catch (e) {
          final errStr = e.toString();
          if (errStr.contains('SERVICE_NOT_AVAILABLE') && i < 2) {
            debugPrint(
                '🔄 FCM Service not available, retrying (${i + 1}/3)...');
            await Future.delayed(Duration(seconds: 1 * (i + 1)));
            continue;
          }
          rethrow;
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ FCM getToken error: $e');
      return null;
    }
  }

  // ── Send token to backend ─────────────────────────────────────────────────

  /// Call this after login/register to register the device token with the server.
  static Future<void> sendTokenToBackend() async {
    try {
      final token = await FCMService().getToken();
      if (token == null) return;

      // Use the existing API client's token
      final storage = SecureStorageService();
      final authToken = await storage.getAccessToken();
      if (authToken == null) return;

      final client = ApiClient();
      await client.post(
        '${ApiClient.baseUrl}/update-fcm-token',
        data: {'fcmToken': token},
        requiresAuth: true,
      );
      debugPrint('✅ FCM Token sent to backend');
    } catch (e) {
      debugPrint('⚠️ Failed to send FCM token to backend: $e');
      // Non-blocking — no rethrow
    }
  }

  /// Sets up a listener to refresh the token when Firebase rotates it.
  static void listenToTokenRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      debugPrint('🔄 FCM token refreshed — sending to backend');
      sendTokenToBackend(); // fire and forget
    });
  }

  // ── Show foreground local notification ────────────────────────────────────

  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    final data = message.data;
    final String title = notification.title ?? 'Shrimpbite';
    final String body = notification.body ?? '';

    _localNotifications.show(
      notification.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: data['type'],
    );

    debugPrint('🔔 FCM Foreground notification shown: $title — $body');
  }
}
