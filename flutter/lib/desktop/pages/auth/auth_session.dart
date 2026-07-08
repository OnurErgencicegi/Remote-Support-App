// flutter/lib/desktop/pages/auth/auth_session.dart
//
// RemoteSupport auth-server ile konuşan basit istemci + oturum (token/role)
// saklama katmanı. Saklama için yeni bir paket (shared_preferences vb.)
// eklemek yerine RustDesk'in zaten kullandığı yerel config mekanizmasını
// (bind.mainGetLocalOption / mainSetLocalOption) kullanıyoruz - bu mekanizma
// Rust tarafında persist ediliyor ve tüm kod tabanında zaten kullanılıyor.

import 'dart:convert';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;

/// TODO: Kendi auth-server adresinizle değiştirin (ör: https://165.245.219.144:3000)
const String kAuthServerBaseUrl = 'https://165.245.219.144:3000';

const String kOptionAuthToken = 'remotesupport-auth-token';
const String kOptionAuthRole = 'remotesupport-auth-role';
const String kOptionAuthEmail = 'remotesupport-auth-email';

/// Sunucudaki role değerleriyle birebir eşleşir (bkz. authRoutes.js).
class AuthRole {
  static const String host = 'host';
  static const String controller = 'controller';
}

class AuthResult {
  final bool success;
  final String? error;
  AuthResult.success()
      : success = true,
        error = null;
  AuthResult.failure(this.error) : success = false;
}

class AuthSession {
  /// Yerelde kayıtlı token var mı? (senkron - RustDesk local option senkron okunur)
  static bool get isLoggedIn =>
      (bind.mainGetLocalOption(key: kOptionAuthToken)).isNotEmpty;

  static String get role {
    final r = bind.mainGetLocalOption(key: kOptionAuthRole);
    return r.isEmpty ? AuthRole.controller : r;
  }

  static String get email => bind.mainGetLocalOption(key: kOptionAuthEmail);

  static Future<void> _saveSession(
      String token, String role, String email) async {
    await bind.mainSetLocalOption(key: kOptionAuthToken, value: token);
    await bind.mainSetLocalOption(key: kOptionAuthRole, value: role);
    await bind.mainSetLocalOption(key: kOptionAuthEmail, value: email);
  }

  static Future<void> logout() async {
    await bind.mainSetLocalOption(key: kOptionAuthToken, value: '');
    await bind.mainSetLocalOption(key: kOptionAuthRole, value: '');
    await bind.mainSetLocalOption(key: kOptionAuthEmail, value: '');
  }

  static Future<AuthResult> login(String email, String password) async {
    return _authRequest('/auth/login', {'email': email, 'password': password});
  }

  static Future<AuthResult> register(
      String email, String password, String role) async {
    return _authRequest(
        '/auth/register', {'email': email, 'password': password, 'role': role});
  }

  static Future<AuthResult> _authRequest(
      String path, Map<String, dynamic> body) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$kAuthServerBaseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode != 200) {
        return AuthResult.failure(
            data['error']?.toString() ?? 'Bilinmeyen hata');
      }

      final token = data['token'] as String?;
      final user = data['user'] as Map<String, dynamic>?;
      if (token == null || user == null) {
        return AuthResult.failure('Sunucu beklenmeyen bir yanıt döndürdü.');
      }

      await _saveSession(
        token,
        (user['role'] as String?) ?? AuthRole.controller,
        (user['email'] as String?) ?? '',
      );
      return AuthResult.success();
    } catch (e) {
      return AuthResult.failure('Sunucuya ulaşılamadı: $e');
    }
  }
}
