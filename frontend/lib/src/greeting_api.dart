import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class GreetingApi {
  GreetingApi({http.Client? client}) : _client = client ?? http.Client();

  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
  final http.Client _client;

  String get _baseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    return Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000';
  }

  Future<String> getGreeting() async {
    final response = await _client.get(Uri.parse('$_baseUrl/hello'));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['message'] as String;
  }

  Future<void> saveGreeting(String message) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/hello'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'message': message}),
    );
    if (response.statusCode != 201) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }
}
