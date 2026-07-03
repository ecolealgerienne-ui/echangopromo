import 'package:dio/dio.dart';
import '../../config/env.dart';

class ApiClient {
  ApiClient() : dio = Dio(BaseOptions(baseUrl: Env.apiBaseUrl));

  final Dio dio;
}
