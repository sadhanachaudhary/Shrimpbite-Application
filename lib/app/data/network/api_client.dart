import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import '../../../core/api/auth_interceptor.dart';
import '../../../core/api/api_provider.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/utils/logger.dart';

/// Thrown when the server returns a non-2xx status or an error occurs.
class ApiException implements Exception {
  final int? statusCode;
  final String message;

  const ApiException({required this.message, this.statusCode});

  @override
  String toString() {
    if (statusCode != null) {
      return 'ApiException($statusCode): $message';
    }
    return 'ApiException: $message';
  }
}

/// Provider for ApiClient
final apiClientProvider = Provider<ApiClient>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: dotenv.get('API_BASE_URL').trim(),
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
    contentType: Headers.jsonContentType,
  ));

  final storage = ref.watch(storageServiceProvider);
  dio.interceptors.addAll([
    AuthInterceptor(dio, storage),
    PrettyDioLogger(
      requestHeader: true,
      requestBody: true,
      responseBody: true,
      responseHeader: false,
      error: true,
      compact: true,
      maxWidth: 90,
    ),
  ]);

  return ApiClient(dio);
});

class ApiClient {
  // ── Production Base URLs (Relative to API_BASE_URL) ────────────────────────
  static const String baseUrl = '/app';
  static const String riderBaseUrl = '/rider';
  static const String otpBaseUrl = '/otp';
  static const String walletBaseUrl = '/wallet';
  static const String paymentBaseUrl = '/payment';
  static const String subscriptionBaseUrl = '/subscription';
  static const String reviewBaseUrl = '/reviews';

  final Dio _dio;

  ApiClient([Dio? dio]) : _dio = dio ?? _createDefaultDio();

  static Dio _createDefaultDio() {
    final dio = Dio(BaseOptions(
      baseUrl: dotenv.get('API_BASE_URL').trim(),
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
    ));

    final storage = SecureStorageService();
    dio.interceptors.addAll([
      AuthInterceptor(dio, storage),
      PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseBody: true,
        error: true,
        compact: true,
      ),
    ]);
    return dio;
  }

  String _buildUrl(String path) {
    if (path.startsWith('http')) return path;
    var base = dotenv.get('API_BASE_URL').trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    var p = path;
    if (!p.startsWith('/')) p = '/$p';
    return base + p;
  }

  // ── HTTP Methods ───────────────────────────────────────────────────────────

  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters,
      bool requiresAuth = false}) async {
    try {
      final response = await _dio.get(
        _buildUrl(path),
        queryParameters: queryParameters,
        options: Options(extra: {'requiresAuth': requiresAuth}),
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> post(String path,
      {dynamic data, bool requiresAuth = false}) async {
    try {
      final response = await _dio.post(
        _buildUrl(path),
        data: data,
        options: Options(extra: {'requiresAuth': requiresAuth}),
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> put(String path,
      {dynamic data, bool requiresAuth = false}) async {
    try {
      final response = await _dio.put(
        _buildUrl(path),
        data: data,
        options: Options(extra: {'requiresAuth': requiresAuth}),
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> patch(String path,
      {dynamic data, bool requiresAuth = false}) async {
    try {
      final response = await _dio.patch(
        _buildUrl(path),
        data: data,
        options: Options(extra: {'requiresAuth': requiresAuth}),
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> delete(String path,
      {dynamic data, bool requiresAuth = false}) async {
    try {
      final response = await _dio.delete(
        _buildUrl(path),
        data: data,
        options: Options(extra: {'requiresAuth': requiresAuth}),
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  ApiException _handleError(DioException e) {
    // connectionError covers: no internet, DNS failure, refused connection — always user-facing
    if (e.type == DioExceptionType.connectionError) {
      return const ApiException(message: 'No internet connection. Please check your network and try again.');
    }

    // unknown can wrap a SocketException on some platforms
    if (e.type == DioExceptionType.unknown) {
      final isSocket = e.error is SocketException ||
          (e.message != null &&
              (e.message!.contains('SocketException') ||
                  e.message!.contains('Failed host lookup') ||
                  e.message!.contains('Network is unreachable')));
      if (isSocket) {
        return const ApiException(message: 'No internet connection. Please check your network and try again.');
      }
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const ApiException(message: 'Connection timed out. Please try again.');
    }

    if (e.response != null) {
      final data = e.response?.data;
      String message = e.message ?? 'Server error';
      if (data is Map) {
        message = data['message']?.toString() ?? message;
        if (e.response?.statusCode == 403) {
          if (message.contains('attestation')) {
            message = 'Security check failed. Please ensure you are using the official app and have a stable connection.';
          } else {
            message = 'Access denied. Please check your account permissions or re-authenticate.';
          }
        }
      } else if (data is String && data.isNotEmpty) {
        if (!data.contains('<html')) {
          message = data;
        }
      }
      return ApiException(statusCode: e.response?.statusCode, message: message);
    }

    AppLogger.e('API Error: ${e.message}', e, e.stackTrace);
    return const ApiException(message: 'Something went wrong. Please try again.');
  }

  // ── Helper static methods for token access ──────────────────────────────
  static Future<String?> getToken() async =>
      await SecureStorageService().getAccessToken();
  static Future<void> saveTokens({required String access, String? refresh}) async {
    final storage = SecureStorageService();
    await storage.saveAccessToken(access);
    if (refresh != null && refresh.isNotEmpty) {
      await storage.saveRefreshToken(refresh);
    }
  }

  static Future<void> saveToken(String token) async {
    await saveTokens(access: token);
  }

  static Future<void> clearToken() async =>
      await SecureStorageService().clearAll();
}
