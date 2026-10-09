import 'package:dio/dio.dart';

import '../domain/repositories.dart';

/// Thin Dio wrapper. Maps transport/server problems to [Failure] — the UI
/// decides how to present them; we never fabricate substitute data here.
class GuideApi {
  GuideApi({required String baseUrl, Duration timeout = const Duration(seconds: 25)})
      : dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: timeout,
          receiveTimeout: timeout,
          headers: const {'Accept': 'application/json'},
        )) {
    dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      logPrint: (o) {},
    ));
  }

  final Dio dio;

  /// GET [path] with [query]; returns decoded JSON map.
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) =>
      _wrap(() async {
        final res = await dio.get<Map<String, dynamic>>(path, queryParameters: query);
        final data = res.data;
        if (data == null) {
          throw const Failure('Empty response from server', kind: FailureKind.server);
        }
        return data;
      });

  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? body,
  }) =>
      _wrap(() async {
        final res = await dio.post<Map<String, dynamic>>(path, data: body);
        final data = res.data;
        if (data == null) {
          throw const Failure('Empty response from server', kind: FailureKind.server);
        }
        return data;
      });

  Future<T> _wrap<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on Failure {
      rethrow;
    } on DioException catch (e) {
      throw _mapDio(e);
    } catch (e) {
      throw Failure(e.toString(), kind: FailureKind.unknown);
    }
  }

  Failure _mapDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return Failure('Server unreachable: ${e.message ?? 'network error'}',
            kind: FailureKind.network, statusCode: e.response?.statusCode);
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        final detail = _extractDetail(e.response?.data);
        return Failure(
          'Server error ${code ?? ''}: ${detail ?? e.message ?? 'bad response'}',
          kind: FailureKind.server,
          statusCode: code,
          detail: detail,
        );
      case DioExceptionType.cancel:
        return const Failure('Request cancelled', kind: FailureKind.network);
      case DioExceptionType.badCertificate:
        return const Failure('TLS certificate rejected', kind: FailureKind.network);
      case DioExceptionType.unknown:
        return Failure(e.message ?? 'Unknown network error',
            kind: FailureKind.network);
    }
  }

  String? _extractDetail(Object? data) {
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    return null;
  }
}
