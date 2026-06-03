import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../app/data/models/auth_models.dart';
import '../../app/data/services/auth_service.dart';
import '../storage/secure_storage_service.dart';
import '../api/auth_interceptor.dart';
import '../../app/data/network/api_client.dart';
import '../../app/data/services/fcm_service.dart';
import '../utils/logger.dart';

// Unified Auth Provider for the app
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(client: ref.watch(apiClientProvider));
});

final secureStorageProvider = Provider((ref) => SecureStorageService());

enum AuthStatus { initial, authenticated, unauthenticated, loading }

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? error;
  final String? successMessage;
  final String? otp;
  final String? verificationId;

  AuthState(
      {required this.status,
      this.user,
      this.error,
      this.successMessage,
      this.otp,
      this.verificationId});

  factory AuthState.initial() => AuthState(status: AuthStatus.initial);
  factory AuthState.loading() => AuthState(status: AuthStatus.loading);
  factory AuthState.authenticated(UserModel user) =>
      AuthState(status: AuthStatus.authenticated, user: user);
  factory AuthState.unauthenticated({String? error}) =>
      AuthState(status: AuthStatus.unauthenticated, error: error);

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? error,
    String? successMessage,
    String? otp,
    String? verificationId,
    bool clearVerificationId = false,
    bool clearOtp = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error ?? this.error,
      successMessage: successMessage ?? this.successMessage,
      otp: clearOtp ? null : (otp ?? this.otp),
      verificationId:
          clearVerificationId ? null : (verificationId ?? this.verificationId),
    );
  }
}

class AuthStore extends Notifier<AuthState> {
  late SecureStorageService _storage;
  StreamSubscription<String>? _logoutSubscription;

  @override
  AuthState build() {
    _storage = ref.watch(secureStorageProvider);

    // Listen for force logout events from the interceptor
    _logoutSubscription?.cancel();
    _logoutSubscription = AuthInterceptor.onForceLogoutStream.listen((reason) {
      // Don't kill the session if we are in the middle of verifying (phone verification id exists)
      if (state.verificationId != null || state.status == AuthStatus.loading) {
        AppLogger.d(
            'AuthStore: Ignoring force logout during active auth flow.');
        return;
      }
      AppLogger.w('AuthStore: Force logout triggered. Reason: $reason');
      setUnauthenticated(error: reason);
    });

    ref.onDispose(() {
      _logoutSubscription?.cancel();
    });

    return AuthState.initial();
  }

  Future<void> init() async {
    // Avoid double loading
    if (state.status == AuthStatus.loading) return;

    state = AuthState.loading();

    try {
      final String? token = await _storage.getAccessToken();
      final String? refreshToken = await _storage.getRefreshToken();
      final String? cachedUserJson = await _storage.getUser();

      if (token != null && token.isNotEmpty) {
        // OPTIMISTIC RESTORE: Use cached user if available to show Home instantly
        if (cachedUserJson != null) {
          try {
            final user = UserModel.fromJson(jsonDecode(cachedUserJson));
            state = AuthState.authenticated(user);
            AppLogger.d('AuthStore: Optimistic restore from cache successful.');
          } catch (e) {
            AppLogger.e('AuthStore: Failed to parse cached user: $e');
          }
        }

        // BACKGROUND REFRESH: Verify session and update profile data
        AppLogger.d('AuthStore: Refreshing profile in background...');
        final response = await ref.read(authServiceProvider).getProfile();

        if (response.success && response.data != null) {
          AppLogger.d('AuthStore: Profile refreshed successfully.');
          await _storage.saveUser(jsonEncode(response.data!.toJson()));
          state = AuthState.authenticated(response.data!);
        } else {
          AppLogger.e(
              'AuthStore: Background refresh failed: ${response.message}');

          // If explicitly unauthorized, clear the session
          if (response.message.contains('401') ||
              response.message.contains('Unauthorized')) {
            AppLogger.w('AuthStore: Credentials invalid. Clearing session.');
            await logout();
          }
          // Note: If it's a network error, we stay in the optimistic 'authenticated' state
        }
      } else {
        state = AuthState.unauthenticated();
      }
    } catch (e, stack) {
      AppLogger.e('AuthStore: Fatal recovery error', e, stack);
      state = AuthState.unauthenticated(error: e.toString());
    }
  }

  Future<void> _persistAuth(
      UserModel user, String access, String refresh) async {
    await _storage.saveTokens(access: access, refresh: refresh);
    await _storage.saveUser(jsonEncode(user.toJson()));
    state = AuthState.authenticated(user);
  }

  Future<void> updateUser(UserModel user) async {
    await _storage.saveUser(jsonEncode(user.toJson()));
    state = state.copyWith(user: user);
  }

  /// Calls the detection API. Returns the action ("otp" only now).
  /// Does NOT change auth state — it's a pure lookup.
  Future<CheckUserResponseModel?> checkUser(
      {required String phoneNumber}) async {
    try {
      return await ref
          .read(authServiceProvider)
          .checkUser(phoneNumber: phoneNumber);
    } catch (e) {
      debugPrint('AuthStore.checkUser error: $e');
      return null;
    }
  }

  Future<void> sendOtp(
      {required String phoneNumber, bool force = false}) async {
    // Only skip if we already have a verificationId (OTP sent)
    // or if we are actively in a loading state specifically triggered by this store's auth flow
    if (state.status == AuthStatus.loading) {
      AppLogger.d('AuthStore: Skipping sendOtp (already loading).');
      return;
    }

    if (!force && state.verificationId != null) {
      AppLogger.d(
          'AuthStore: Skipping redundant OTP request (session already active).');
      return;
    }

    state = state.copyWith(
      status: AuthStatus.loading,
      error: null,
      clearVerificationId: true,
      clearOtp: true,
    );
    try {
      // 1. Sanitize: Remove all spaces, dashes, parentheses
      String formattedPhone = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '');

      // Apple Test Account Bypass (Handle both raw and +91 prefixed)
      if (formattedPhone == '1234512345' ||
          formattedPhone == '+911234512345' ||
          formattedPhone == '1002003004' ||
          formattedPhone == '+911002003004') {
        AppLogger.i(
            'AuthStore: Bypassing Firebase Auth for test account: $formattedPhone');
        state = state.copyWith(
          status: AuthStatus.initial,
          successMessage: 'OTP sent to your phone via SMS',
          verificationId: 'bypass_verification_id',
        );
        return;
      }

      // 2. Intelligent Auto-Prefixing for India (default)
      if (formattedPhone.length == 10 && !formattedPhone.startsWith('+')) {
        formattedPhone = '+91$formattedPhone';
      } else if (formattedPhone.length == 12 &&
          formattedPhone.startsWith('91')) {
        formattedPhone = '+$formattedPhone';
      } else if (!formattedPhone.startsWith('+')) {
        // Fallback: If it still lacks +, assume +91 or warn?
        // For now, if it's missing +, we add + as a last resort if it looks like E.164 without prefix
        if (formattedPhone.length > 5) {
          formattedPhone = '+$formattedPhone';
        }
      }

      AppLogger.d(
          'AuthStore: Requesting OTP for "$formattedPhone" (Length: ${formattedPhone.length})');

      final backendResponse = await ref
          .read(authServiceProvider)
          .sendOtp(phoneNumber: formattedPhone);

      if (backendResponse.success) {
        AppLogger.i('AuthStore: OTP sent successfully via backend.');
        state = state.copyWith(
          status: AuthStatus.initial,
          successMessage: 'OTP sent to your phone via SMS',
          verificationId: 'backend_session',
          otp: backendResponse.otp,
        );
      } else {
        AppLogger.e(
            'AuthStore: Backend OTP request failed: ${backendResponse.message}');
        state = AuthState.unauthenticated(error: backendResponse.message);
      }
    } catch (e) {
      state = AuthState.unauthenticated(error: _handleAuthError(e));
    }
  }

  String _handleAuthError(dynamic e) {
    // Prefer the clean message from ApiException over its toString()
    final msg = e is ApiException ? e.message : e.toString();

    if (msg.contains('invalid-verification-code') ||
        msg.contains('invalid OTP')) {
      return 'The OTP you entered is incorrect.';
    }
    if (msg.contains('session-expired')) {
      return 'OTP has expired. Please resend code.';
    }

    // Strip Firebase/Dio error prefixes like "[firebase_auth/...]"
    return msg.replaceFirst(RegExp(r'\[.*?\] '), '');
  }

  Future<void> verifyOtp(
      {required String phoneNumber, required String otp}) async {
    if (state.status == AuthStatus.authenticated ||
        state.status == AuthStatus.loading) {
      AppLogger.d('AuthStore: Skipping verifyOtp (status: ${state.status}).');
      return;
    }

    final verificationId = state.verificationId;
    if (verificationId == null) {
      state = AuthState.unauthenticated(
          error: 'Session expired. Please request OTP again.');
      return;
    }

    // Apple Test Account Bypass
    String formattedPhone = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if ((formattedPhone == '1234512345' || formattedPhone == '1002003004') &&
        otp == '123456') {
      AppLogger.i(
          'AuthStore: Bypassing Firebase Verify OTP for test account: $formattedPhone');
      await _verifyBackendOtpBypass(formattedPhone, otp);
      return;
    }

    // Switch to Backend Verify OTP to avoid Firebase dependencies and reCAPTCHA
    try {
      state = state.copyWith(status: AuthStatus.loading, error: null);

      final fcmToken = await FCMService().getToken();
      final response = await ref.read(authServiceProvider).verifyOtp(
            phoneNumber: phoneNumber,
            otp: otp,
          );

      if (response.success) {
        AppLogger.i(
            'AuthStore: Backend Authentication SUCCESS for $phoneNumber');

        final user = response.data ?? UserModel.placeholder(phoneNumber);
        final access = response.token ?? '';
        final refresh = response.refreshToken ?? '';

        if (refresh.isEmpty) {
          AppLogger.w(
              'AuthStore: No refresh token received in backend response.');
        }

        await _persistAuth(user, access, refresh);
        unawaited(syncFcmToken());
      } else {
        AppLogger.w(
            'AuthStore: Backend verification FAILED: ${response.message}');
        state = AuthState.unauthenticated(
            error: _handleAuthError(response.message));
      }
    } catch (e, stack) {
      AppLogger.e('AuthStore: Error during backend verifyOtp', e, stack);
      state = AuthState.unauthenticated(error: _handleAuthError(e));
    }
  }

  Future<void> _verifyBackendOtpBypass(String phoneNumber, String otp) async {
    if (state.status == AuthStatus.loading ||
        state.status == AuthStatus.authenticated) {
      return;
    }

    try {
      state = state.copyWith(status: AuthStatus.loading, error: null);

      final fcmToken = await FCMService().getToken();
      final response = await ref.read(authServiceProvider).verifyOtp(
            phoneNumber: phoneNumber,
            otp: otp,
          );

      if (response.success) {
        AppLogger.i(
            'AuthStore: Authentication SUCCESS (Bypass) for $phoneNumber');

        final user = response.data ?? UserModel.placeholder(phoneNumber);
        final access = response.token ?? '';
        final refresh = response.refreshToken ?? '';

        if (refresh.isEmpty) {
          AppLogger.w(
              'AuthStore: No refresh token received in bypass response.');
        }

        await _persistAuth(user, access, refresh);
        unawaited(syncFcmToken());
      } else {
        AppLogger.w(
            'AuthStore: verification result - FAILED: ${response.message}');
        if (state.status != AuthStatus.authenticated) {
          state = AuthState.unauthenticated(
              error: _handleAuthError(response.message));
        }
      }
    } catch (e, stack) {
      AppLogger.e('AuthStore: Error finalizing test sign-in', e, stack);
      if (state.status != AuthStatus.authenticated) {
        state = AuthState.unauthenticated(error: _handleAuthError(e));
      }
    }
  }

  Future<void> logout() async {
    state = AuthStatus.loading != state.status ? AuthState.loading() : state;
    try {
      await ref.read(authServiceProvider).logout();
    } catch (_) {}
    await _storage.clearAll();
    state = AuthState.unauthenticated();
  }

  void setUnauthenticated({String? error}) {
    _storage.clearAll();
    state = AuthState.unauthenticated(error: error);
  }

  Future<void> syncFcmToken() async {
    final user = state.user;
    if (user == null || user.id == 'placeholder') return;

    final fcmToken = await FCMService().getToken();
    if (fcmToken != null) {
      await ref.read(authServiceProvider).updateFcmToken(fcmToken: fcmToken);
    }
  }

  Future<AuthResponseModel> deleteAccount({String? reason}) async {
    final user = state.user;
    if (user == null) {
      return AuthResponseModel(success: false, message: 'User not found');
    }

    state = state.copyWith(status: AuthStatus.loading);
    try {
      final response = await ref.read(authServiceProvider).deleteAccount(
            name: user.fullName,
            email: user.email,
            reason: reason ?? 'deleat account',
          );
      if (response.success) {
        await logout();
      } else {
        state = state.copyWith(
            status: AuthStatus.authenticated, error: response.message);
      }
      return response;
    } catch (e) {
      state =
          state.copyWith(status: AuthStatus.authenticated, error: e.toString());
      return AuthResponseModel(success: false, message: e.toString());
    }
  }
}

final authStoreProvider = NotifierProvider<AuthStore, AuthState>(() {
  return AuthStore();
});

// Provide easy access to authenticated status
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authStoreProvider).status == AuthStatus.authenticated;
});
