
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

class DioClient {
  Dio? _dio;

  DioClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://api.example.com',  // 基础 URL
      // connectTimeout: 5000,  // 连接超时
      // receiveTimeout: 3000,  // 响应超时
    ));

    _dio?.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // 在请求发送前做一些操作，比如添加 token
        print("Request: ${options.uri}");
        return handler.next(options);
      },
      onResponse: (response, handler) {
        // 响应成功时做一些操作
        print("Response: ${response.statusCode}");
        return handler.next(response);
      },
      onError: (DioError e, handler) {
        // 请求错误时做一些操作
        print("Error: ${e.message}");
        return handler.next(e);
      },
    ));
  }

  static DioClient? _instance;

  factory DioClient() {
    _instance ??= DioClient._internal();
    return _instance!;
  }

  Dio get dio => _dio!;
}
