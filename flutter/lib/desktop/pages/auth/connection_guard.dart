// flutter/lib/desktop/pages/auth/connection_guard.dart
//
// RemoteSupport: bir controller'ın bir host'a bağlanmadan HEMEN ÖNCE
// auth-server'a "bu bağlantıya izin var mı" diye sorduğu katman.
//
// Kurallar sunucuda (authRoutes.js -> /connections/start) uygulanır, bu
// dosya sadece o kararı tetikler ve sonucu client'a yansıtır:
//  - Aynı controller aynı host'a (RustDesk peer ID) daha önce bağlandıysa
//    sunucu reddeder - "tekrar bağlanamama" kuralı.
//  - İzin verilirse sunucu 30 dakikalık bir son kullanma zamanı
//    (expiresAt) döner; bu, DesktopRemoteScreen içinde bir Timer ile
//    takip edilir - süre dolunca pencere otomatik kapatılır.

import 'dart:convert';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'auth_session.dart';

class ConnectionGuard { 
  // hostPeerId -> expiresAt. DesktopRemoteScreen açıldığında bu haritadan
  // kendi süresini okuyup Timer kurar.
  static final Map<String, DateTime> _expiresAt = {};

  static DateTime? expiresAtFor(String hostPeerId) => _expiresAt[hostPeerId];

  /// Bağlanmadan HEMEN ÖNCE (RustDesk bağlantısı fiilen kurulmadan önce)
  /// çağrılır. `true` dönerse bağlanmaya devam edilir; `false` dönerse
  /// bağlantı hiç başlatılmamalıdır - kullanıcıya zaten bir hata dialogu
  /// gösterilmiş olur.
  static Future<bool> checkAndStart(
      BuildContext context, String hostPeerId) async {
    final id = hostPeerId.trim();
    if (id.isEmpty) return true;

    try {
      final resp = await http
          .post(
            Uri.parse('$kAuthServerBaseUrl/auth/connections/start'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${AuthSession.token}',
            },
            body: jsonEncode({'hostPeerId': id}),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200 && data['allowed'] == true) {
        _expiresAt[id] = DateTime.parse(data['expiresAt'] as String);

        // RemoteSupport: hbbs'in artık doğrudan doğruladığı, tek bağlantıya
        // özel kısa ömürlü token. RustDesk'in zaten var olan "access_token"
        // yerel ayarına yazıyoruz - Rust çekirdeği bunu otomatik olarak
        // PunchHoleRequest.token alanına koyup hbbs'e gönderiyor.
        final connToken = data['connToken'] as String?;
        if (connToken != null && connToken.isNotEmpty) {
          await bind.mainSetLocalOption(key: 'access_token', value: connToken);
          await Future.delayed(const Duration(milliseconds: 300));
        }

        return true;
      }

      final message =
          data['error']?.toString() ?? 'Bu bilgisayara bağlanma izniniz yok.';
      if (context.mounted) {
        await _showBlockedDialog(context, message);
      }
      return false;
    } catch (e) {
      if (context.mounted) {
        await _showBlockedDialog(
            context, 'Sunucuya ulaşılamadı, bağlanma izni doğrulanamadı: $e');
      }
      return false;
    }
  }

  static Future<void> _showBlockedDialog(BuildContext context, String message) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Bağlanılamıyor'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
}
