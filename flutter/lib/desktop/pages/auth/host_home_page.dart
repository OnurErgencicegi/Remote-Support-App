// flutter/lib/desktop/pages/auth/host_home_page.dart
//
// Host rolündeki (ya da hiç giriş yapmamış) kullanıcıların gördüğü tek
// ekran. Asıl RustDesk arayüzüne (Uzak Masaüstünü Denetle, ayarlar, vs.)
// erişim yoktur - sadece kendi ID'sini ve parolasını görür, tıpkı biri
// ona bağlanmak istediğinde ihtiyaç duyacağı bilgiler.
//
// Kayıt olmaya gerek yoktur: RustDesk servisi (serverModel) her zaman arka
// planda çalışır ve ID/parola login şartı olmadan geçerlidir. Sayfanın
// altında, isteyen biri (teknisyen/controller) için "Giriş yap / Kaydol"
// bağlantısı vardır.
//
// NOT: Erişim/oturum kısıtlaması (tier limiti, bağlantı süresi vb.)
// burada, parola rotasyonuyla DEĞİL, auth-server tarafındaki
// ConnectionGuard / connections tablosu katmanında ele alınıyor. Bu
// dosyada parola bilerek otomatik değiştirilmiyor.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:provider/provider.dart';
import 'login_page.dart';

class HostHomePage extends StatefulWidget {
  const HostHomePage({Key? key}) : super(key: key);

  @override
  State<HostHomePage> createState() => _HostHomePageState();
}

class _HostHomePageState extends State<HostHomePage> {
  @override
  void initState() {
    super.initState();
    gFFI.serverModel.fetchID();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Consumer<ServerModel>(
              builder: (context, model, child) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: loadLogo(),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Bu Bilgisayar',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bu bilgisayara bağlanılabilmesi için aşağıdaki '
                        'kimlik ve parola bilgilerini karşı tarafa iletin.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 32),
                      _buildInfoCard(
                        context,
                        label: 'Kimlik',
                        value: model.serverId.text,
                        onCopy: () {
                          Clipboard.setData(
                              ClipboardData(text: model.serverId.text));
                          showToast('Kopyalandı');
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildInfoCard(
                        context,
                        label: 'Tek Kullanımlık Parola',
                        value: model.serverPasswd.text,
                        onCopy: () {
                          Clipboard.setData(
                              ClipboardData(text: model.serverPasswd.text));
                          showToast('Kopyalandı');
                        },
                        trailing: AnimatedRotationWidget(
                          onPressed: () => bind.mainUpdateTemporaryPassword(),
                          child: const Tooltip(
                            message: 'Parolayı Yenile',
                            child: RotatedBox(
                              quarterTurns: 2,
                              child: Icon(Icons.refresh, size: 20),
                            ),
                          ),
                          onHover: (_) {},
                        ),
                      ),
                      const SizedBox(height: 40),
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => LoginPage(
                                onAuthenticated: () {
                                  // Login/register başarılı olduğunda
                                  // AuthSession.authenticated GetX ile
                                  // güncellenir, AuthGate otomatik olarak
                                  // DesktopTabPage'e geçer. Burada sadece
                                  // bu geçici sayfayı kapatmak yeterli.
                                  Navigator.of(context).pop();
                                },
                              ),
                            ));
                          },
                          child: const Text(
                              'Teknisyen misiniz? Giriş yap / Kaydol'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String label,
    required String value,
    required VoidCallback onCopy,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 20, letterSpacing: 1.2),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Kopyala',
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}