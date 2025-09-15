import 'dart:convert';
import 'package:dio/dio.dart';

class HttpService {
  static final HttpService _instance = HttpService._internal();
  factory HttpService() => _instance;

  late Dio dio;

  // final String baseUrl = 'https://www.wyjfr.com';
  final String baseUrl = 'http://175.178.82.123:8070';

  HttpService._internal() {
    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
      // 关键：统一按字符串收，避免 Content-Type 异常导致抛错
      responseType: ResponseType.plain,
    );

    dio = Dio(options);

    dio.interceptors.add(LogInterceptor(
      request: false,
      requestBody: false,
      responseBody: false,
      responseHeader: false,
      error: true,
    ));
  }

  // 公共：尝试把字符串解析为 JSON；不是 JSON 就原样返回
  T parseJson<T>(Response resp) {
    final data = resp.data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        return decoded as T;
      } catch (_) {
        return data as T;
      }
    }
    return data as T;
  }

  Future<Response> get(
      String path, {
        Map<String, dynamic>? queryParameters,
      }) async {
    try {
      return await dio.get(path, queryParameters: queryParameters);
    } catch (e) {
      return _handleError(e);
    }
  }

  Future<Response> post(
      String path, {
        dynamic data,
        Map<String, dynamic>? queryParameters,
      }) async {
    try {
      return await dio.post(path, data: data, queryParameters: queryParameters);
    } catch (e) {
      return _handleError(e);
    }
  }

  Response _handleError(dynamic error) {
    if (error is DioException) {
      return Response(
        requestOptions: error.requestOptions,
        statusCode: error.response?.statusCode ?? 500,
        data: error.response?.data ??
            {'message': error.message ?? '未知错误', 'ok': false},
      );
    } else {
      return Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: 500,
        data: {'message': '未知错误', 'ok': false},
      );
    }
  }
}
