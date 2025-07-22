import 'dio_client.dart';
import 'package:dio/dio.dart';

class ApiService {

  final DioClient _dioClient = DioClient();

  // GET 请求
  Future<Response> get(String path, {Map<String, dynamic>? queryParams}) async {
    try {
      final response = await _dioClient.dio.get(path, queryParameters: queryParams);
      return response;
    } catch (e) {
      rethrow;  // 错误转发
    }
  }

  // POST 请求
  Future<Response> post(String path, {Map<String, dynamic>? data}) async {
    try {
      final response = await _dioClient.dio.post(path, data: data);
      return response;
    } catch (e) {
      rethrow;
    }
  }
}
