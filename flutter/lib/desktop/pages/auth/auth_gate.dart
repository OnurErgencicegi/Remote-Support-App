// flutter/lib/desktop/pages/auth/auth_gate.dart
//
// Uygulamanın gerçek giriş noktası (main.dart -> home: const AuthGate()).
// Kayıtlı token yoksa LoginPage gösterir; varsa doğrudan asıl RustDesk
// arayüzüne (DesktopTabPage) geçer.
//
// NOT: Burada token'ı sadece "var mı yok mu" diye kontrol ediyoruz (basit
// iskelet). İleride açılışta /auth/me ile sunucuya doğrulatıp süresi dolmuş
// / iptal edilmiş tokenlarda otomatik logout yapılabilir - bu TODO.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'auth_session.dart';
import 'login_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({Key? key}) : super(key: key);

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late bool _authenticated = AuthSession.isLoggedIn;

  @override
  Widget build(BuildContext context) {
    if (!_authenticated) {
      return LoginPage(
        onAuthenticated: () => setState(() => _authenticated = true),
      );
    }
    return const DesktopTabPage();
  }
}
