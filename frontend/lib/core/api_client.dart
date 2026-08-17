import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 后端返回业务错误时抛出的异常，页面可直接展示其中的中文提示。
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({VoidCallback? onUnauthorized})
      : _onUnauthorized = onUnauthorized,
        _dio = Dio(
          BaseOptions(
            baseUrl: _defaultBaseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 每次请求临时读取安全存储，退出登录后不会继续携带旧令牌。
          final token = await _storage.read(key: _tokenKey);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          // 令牌失效时清理本机凭据，并由状态层将用户带回登录页。
          if (error.response?.statusCode == 401) {
            await _storage.delete(key: _tokenKey);
            _onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'access_token';

  final Dio _dio;
  final VoidCallback? _onUnauthorized;

  // 可在真机或部署环境中通过 --dart-define=API_BASE_URL=... 覆盖默认地址。
  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get _defaultBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl;
    }
    // Chrome 访问本机地址；Android 模拟器需通过 10.0.2.2 访问宿主机后端。
    return kIsWeb ? 'http://localhost:8080' : 'http://10.0.2.2:8080';
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final data = await _requestObject(
      () => _dio.post(
        '/api/v1/auth/login',
        data: {'username': username, 'password': password},
      ),
    );
    final token = data['accessToken'] as String;
    // 令牌只由统一客户端附加到请求头，不由页面层自行管理。
    await _storage.write(key: _tokenKey, value: token);
    return Map<String, dynamic>.from(data['user'] as Map);
  }

  Future<void> logout() async {
    // 后端采用无状态 JWT，退出只需删除本机保存的令牌。
    await _storage.delete(key: _tokenKey);
  }

  Future<Map<String, dynamic>> getObject(String path) {
    return _requestObject(() => _dio.get(path));
  }

  Future<List<Map<String, dynamic>>> getList(String path) async {
    final data = await _requestData(() => _dio.get(path));
    if (data is! List) {
      throw const ApiException('服务返回的数据类型不正确。');
    }
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> postObject(
    String path,
    Map<String, dynamic> data,
  ) {
    return _requestObject(() => _dio.post(path, data: data));
  }

  Future<void> postVoid(String path, Map<String, dynamic> data) async {
    await _requestData(() => _dio.post(path, data: data));
  }

  Future<void> putVoid(String path, Map<String, dynamic> data) async {
    await _requestData(() => _dio.put(path, data: data));
  }

  /// 删除动作仍走统一响应解析；诊断接口内部采用作废状态而非物理删除。
  Future<void> deleteVoid(String path, Map<String, dynamic> data) async {
    await _requestData(() => _dio.delete(path, data: data));
  }

  Future<Map<String, dynamic>> _requestObject(
    Future<Response<dynamic>> Function() request,
  ) async {
    final data = await _requestData(request);
    if (data is! Map) {
      throw const ApiException('服务返回的数据类型不正确。');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<dynamic> _requestData(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final response = await request();
      final body = Map<String, dynamic>.from(response.data as Map);
      final code = body['code'] as num? ?? -1;
      if (code != 0) {
        throw ApiException(
          body['message']?.toString() ?? '请求未成功，请稍后重试。',
          statusCode: response.statusCode,
        );
      }
      return body['data'];
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      final responseBody = error.response?.data;
      if (responseBody is Map && responseBody['message'] != null) {
        throw ApiException(
          responseBody['message'].toString(),
          statusCode: error.response?.statusCode,
        );
      }
      throw ApiException(
        '无法连接后端服务，请检查服务地址和网络。',
        statusCode: error.response?.statusCode,
      );
    }
  }
}
