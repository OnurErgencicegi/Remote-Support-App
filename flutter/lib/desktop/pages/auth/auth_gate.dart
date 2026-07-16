// flutter/lib/desktop/pages/auth/auth_gate.dart
//
// Uygulamanın gerçek giriş noktası (main.dart -> home: const AuthGate()).
//
// GÜNCEL DAVRANIŞ:
// - Giriş yapılmamışsa VEYA rol "host" ise: kullanıcı asla asıl RustDesk
//   arayüzüne (DesktopTabPage) giremez. Bunun yerine sadece kendi ID'sini
//   ve tek kullanımlık parolasını gösteren HostHomePage görüntülenir.
//   Host'un kayıt olmasına gerek yoktur - RustDesk servisi zaten arka planda
//   çalışır, ID/parola login şartı olmadan da geçerlidir. HostHomePage
//   içinde "Ben teknisyenim / Giriş yap" bağlantısı, isteyen kişinin
//   controller olarak login/register olmasına izin verir.
// - Rol "controller" ve giriş yapılmışsa: asıl arayüz (DesktopTabPage)
//   gösterilir. Çıkış yapınca (AuthSession.logout()) otomatik olarak
//   HostHomePage'e geri döner - Obx sayesinde manuel yönlendirme gerekmez.
//
// Biri bu bilgisayara bağlanmak istediğinde çıkan izin/onay ekranı bu
// widget'tan tamamen bağımsızdır - RustDesk'in ayrı connection-manager
// penceresi (--cm) tarafından yönetilir, bu ekranda ne gösterildiğinden
// etkilenmez.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'auth_session.dart';
import 'host_home_page.dart';
import 'login_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({Key? key}) : super(key: key);

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    // Host modunda da (login olmadan) RustDesk'in doğru sunucuya bağlı
    // çalışması gerekir, o yüzden açılışta koşulsuz uyguluyoruz.
    AuthSession.applyServerConfig();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isController = AuthSession.authenticated.value &&
          AuthSession.roleRx.value == AuthRole.controller;
      if (isController) {
        return const DesktopTabPage();
      }
      // Giriş yapılmamış VEYA rol host: sadece ID/parola ekranı.
      return const HostHomePage();
    });
  }
}

/// Controller girişi/kaydı için ayrı bir sayfa olarak kullanılabilmesi için
/// LoginPage'in çağrılma şekli değişmedi - HostHomePage içindeki
/// "Giriş yap / Kaydol" butonu bunu Navigator ile açar (bkz. host_home_page.dart).
/// AuthGate seviyesinde ayrıca bir şey yapmaya gerek yok çünkü login/register
/// başarılı olduğunda AuthSession.authenticated.value = true olur ve Obx
/// otomatik olarak DesktopTabPage'e geçer.