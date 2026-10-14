import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

String get apiBaseUrl {
  const configured = String.fromEnvironment('API_BASE_URL');
  return configured.isNotEmpty
      ? configured
      : kIsWeb
      ? Uri.base.resolve('/api').toString()
      : defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:3000'
      : 'http://localhost:3000';
}

class UserSession {
  const UserSession({
    required this.token,
    required this.id,
    required this.email,
  });
  final String token;
  final String id;
  final String email;
  Map<String, dynamic> toJson() => {
    'token': token,
    'user': {'id': id, 'email': email},
  };
  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
    token: json['token'] as String,
    id: json['user']['id'] as String,
    email: json['user']['email'] as String,
  );
}

class AuthController extends ChangeNotifier {
  static final instance = AuthController();
  static const _storageKey = 'i7l.session';
  final _storage = const FlutterSecureStorage();
  UserSession? session;
  bool busy = false;
  String? error;
  String? _attemptToken;
  int _generation = 0;
  VoidCallback? onSessionEnded;

  Future<void> restore() async {
    try {
      // Web uses an HttpOnly cookie. This also restores the temporary local
      // account when SKIP_LOGIN is enabled on the server, on every platform.
      final current = await http
          .get(Uri.parse('$apiBaseUrl/auth/me'))
          .timeout(const Duration(seconds: 10));
      if (current.statusCode == 200) {
        final user = jsonDecode(current.body) as Map<String, dynamic>;
        session = UserSession(
          token: '',
          id: user['id'] as String,
          email: user['email'] as String,
        );
        notifyListeners();
        return;
      }
      if (kIsWeb) return;
    } catch (_) {
      if (kIsWeb) return;
    }
    try {
      final stored = await _storage.read(key: _storageKey);
      if (stored == null) return;
      final cached = UserSession.fromJson(
        jsonDecode(stored) as Map<String, dynamic>,
      );
      // The API still verifies every request; this only permits opening the UI offline.
      session = cached;
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/auth/me'),
            headers: {'authorization': 'Bearer ${cached.token}'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 401) {
        await _storage.delete(key: _storageKey);
        session = null;
      } else if (response.statusCode == 200) {
        final user = jsonDecode(response.body) as Map<String, dynamic>;
        session = UserSession(
          token: cached.token,
          id: user['id'] as String,
          email: user['email'] as String,
        );
      }
    } on FormatException {
      await _storage.delete(key: _storageKey);
      session = null;
    } catch (_) {
      // Temporary network failures do not erase a saved session.
    }
    notifyListeners();
  }

  Future<void> signIn() async {
    if (busy) return;
    final generation = ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final start = await http
          .post(
            Uri.parse('$apiBaseUrl/auth/google/start${kIsWeb ? '?web=1' : ''}'),
          )
          .timeout(const Duration(seconds: 15));
      if (start.statusCode == 503) {
        throw const AuthFailure(
          'El acceso con Google aún no está disponible. Inténtalo más tarde.',
        );
      }
      if (start.statusCode != 200) {
        throw const AuthFailure('No se pudo conectar. Revisa tu conexión.');
      }
      final data = jsonDecode(start.body) as Map<String, dynamic>;
      if (kIsWeb) {
        if (!await launchUrl(
          Uri.parse(data['authorizationUrl'] as String),
          webOnlyWindowName: '_self',
        )) {
          throw const AuthFailure('No se pudo abrir Google.');
        }
        return;
      }
      final attempt = data['attemptToken'] as String;
      if (generation != _generation) {
        await _cancelAttempt(attempt);
        return;
      }
      _attemptToken = attempt;
      if (!await launchUrl(
        Uri.parse(data['authorizationUrl'] as String),
        mode: LaunchMode.externalApplication,
      )) {
        throw const AuthFailure('No se pudo abrir el navegador.');
      }
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (generation == _generation && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (generation != _generation) return;
        final response = await http
            .post(
              Uri.parse('$apiBaseUrl/auth/google/finish'),
              headers: {'content-type': 'application/json'},
              body: jsonEncode({'attemptToken': attempt}),
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 202) continue;
        if (response.statusCode != 200) {
          throw const AuthFailure(
            'El acceso se canceló o caducó. Inténtalo de nuevo.',
          );
        }
        final authenticated = UserSession.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
        if (generation != _generation) {
          await _revoke(authenticated.token);
          return;
        }
        try {
          await _storage.write(
            key: _storageKey,
            value: jsonEncode(authenticated.toJson()),
          );
        } catch (_) {
          await _revoke(authenticated.token);
          throw const AuthFailure(
            'No se pudo guardar la sesión de forma segura.',
          );
        }
        if (generation != _generation) {
          await _revoke(authenticated.token);
          await _storage.delete(key: _storageKey);
          return;
        }
        session = authenticated;
        _attemptToken = null;
        return;
      }
      if (generation == _generation) {
        throw const AuthFailure('El acceso caducó. Vuelve a intentarlo.');
      }
    } on AuthFailure catch (failure) {
      if (generation == _generation) error = failure.message;
    } catch (_) {
      if (generation == _generation) error = 'No se pudo iniciar sesión. Revisa tu conexión e inténtalo de nuevo.';
    } finally {
      if (generation == _generation) {
        final attempt = _attemptToken;
        _attemptToken = null;
        if (attempt != null) unawaited(_cancelAttempt(attempt));
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _cancelAttempt(String token) async {
    try {
      await http
          .post(
            Uri.parse('$apiBaseUrl/auth/google/cancel'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'attemptToken': token}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      /* Attempts expire server-side after five minutes. */
    }
  }

  void cancelSignIn() {
    ++_generation;
    final attempt = _attemptToken;
    _attemptToken = null;
    if (attempt != null) unawaited(_cancelAttempt(attempt));
    busy = false;
    error = null;
    notifyListeners();
  }

  Future<void> _revoke(String token) async {
    final response = await http
        .delete(
          Uri.parse('$apiBaseUrl/auth/session'),
          headers: {if (token.isNotEmpty) 'authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw const AuthFailure('No se pudo cerrar la sesión.');
    }
  }

  Future<void> signOut() async {
    final token = session?.token;
    if (token != null) await _revoke(token);
    if (!kIsWeb) await _storage.delete(key: _storageKey);
    onSessionEnded?.call();
    session = null;
    error = null;
    notifyListeners();
  }

  void expire(UserSession expectedSession) {
    if (!identical(session, expectedSession)) return;
    onSessionEnded?.call();
    session = null;
    error = 'Tu sesión caducó. Vuelve a entrar con Google.';
    if (!kIsWeb) {
      unawaited(_storage.delete(key: _storageKey).catchError((_) {}));
    }
    notifyListeners();
  }
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
}

// Bind requests to the account displayed when this API client was created.
class AuthenticatedClient extends http.BaseClient {
  AuthenticatedClient(this.inner, this.session);
  final http.Client inner;
  final UserSession? session;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final expectedSession = session;
    if (expectedSession != null) {
      if (!identical(AuthController.instance.session, expectedSession)) {
        throw const AuthFailure('La cuenta cambió. Vuelve a abrir la app.');
      }
      request.headers['x-i7l-user'] = expectedSession.id;
      if (expectedSession.token.isNotEmpty) {
        request.headers['authorization'] = 'Bearer ${expectedSession.token}';
      }
    }
    final response = await inner
        .send(request)
        .timeout(const Duration(seconds: 20));
    if (expectedSession != null &&
        (response.statusCode == 401 || response.statusCode == 409)) {
      AuthController.instance.expire(expectedSession);
    }
    if (expectedSession != null &&
        !identical(AuthController.instance.session, expectedSession)) {
      throw const AuthFailure('La cuenta cambió. Vuelve a abrir la app.');
    }
    return response;
  }

  @override
  void close() => inner.close();
}
