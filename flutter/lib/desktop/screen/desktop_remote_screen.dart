import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/remote_tab_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:provider/provider.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../pages/auth/connection_guard.dart';

/// multi-tab desktop remote screen
///
/// RemoteSupport: bu widget artık StatefulWidget - açılışta, connection_page.dart
/// içindeki ConnectionGuard.checkAndStart() tarafından bu host için kaydedilmiş
/// 30 dakikalık son kullanma zamanını okuyup bir Timer ile takip ediyor. Süre
/// dolduğunda kullanıcıya "free tier limitine ulaştınız" mesajı gösterilir ve
/// ardından pencere kapatılır. Kullanıcı isterse hemen tekrar "Bağlan"a basıp
/// yeni bir 30 dakikalık oturum başlatabilir - kalıcı bir engelleme yoktur.
class DesktopRemoteScreen extends StatefulWidget {
  final Map<String, dynamic> params;

  const DesktopRemoteScreen({Key? key, required this.params}) : super(key: key);

  @override
  State<DesktopRemoteScreen> createState() => _DesktopRemoteScreenState();
}

class _DesktopRemoteScreenState extends State<DesktopRemoteScreen> {
  Timer? _sessionLimitTimer;
  bool _timeLimitDialogShown = false;

  @override
  void initState() {
    super.initState();
    bind.mainInitInputSource();
    stateGlobal.getInputSource(force: true);
    _startSessionLimitWatcher();
  }

  // RemoteSupport: auth-server'ın bu bağlantı için verdiği 30 dakikalık süre
  // sınırını burada takip ediyoruz. Süre, connection_page.dart'taki
  // ConnectionGuard.checkAndStart() tarafından bağlanmadan hemen önce
  // kaydedilmiş olmalı.
  //
  // NOT: Eğer bu ekrana ConnectionGuard'dan geçmeyen bir yoldan ulaşıldıysa
  // (örn. ileride eklenebilecek başka bir bağlanma yolu), expiresAt
  // bulunamaz ve güvenli tarafta kalıp herhangi bir süre kısıtlaması
  // uygulanmaz. Tüm bağlanma yollarının guard'dan geçtiğinden emin olun.
  void _startSessionLimitWatcher() {
    final hostPeerId = widget.params['id'] as String?;
    if (hostPeerId == null || hostPeerId.isEmpty) return;

    final expiresAt = ConnectionGuard.expiresAtFor(hostPeerId);
    if (expiresAt == null) return;

    void checkExpiry() {
      if (DateTime.now().isAfter(expiresAt)) {
        _sessionLimitTimer?.cancel();
        _showTimeLimitReachedAndClose();
      }
    }

    // Pencere açılır açılmaz süre zaten dolmuşsa hemen kapat; değilse
    // periyodik olarak kontrol et.
    checkExpiry();
    _sessionLimitTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => checkExpiry());
  }

  // Süre dolduğunda önce kullanıcıya bilgilendirme dialogu gösterir, sonra
  // pencereyi kapatır. Kalıcı bir engelleme yok - kullanıcı dialogu
  // kapattıktan sonra ana pencereden "Bağlan"a basarak hemen yeni bir 30
  // dakikalık oturum başlatabilir.
  Future<void> _showTimeLimitReachedAndClose() async {
    if (_timeLimitDialogShown) return;
    _timeLimitDialogShown = true;

    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Süre doldu'),
          content: const Text(
            'Ücretsiz plan bağlantı süreniz (30 dakika) doldu.\n\n'
            'Bağlantı şimdi kapatılacak. Daha uzun oturumlar için planınızı '
            'yükseltebilir ya da istediğiniz zaman tekrar bağlanabilirsiniz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    }

    await _closeWindow();
  }

  Future<void> _closeWindow() async {
    final wid = stateGlobal.windowId;
    if (wid != -1) {
      try {
        await WindowController.fromWindowId(wid).close();
      } catch (_) {
        // Pencere zaten kapanmış olabilir, güvenli şekilde yut.
      }
    }
  }

  @override
  void dispose() {
    _sessionLimitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: gFFI.ffiModel),
          ChangeNotifierProvider.value(value: gFFI.imageModel),
          ChangeNotifierProvider.value(value: gFFI.cursorModel),
          ChangeNotifierProvider.value(value: gFFI.canvasModel),
        ],
        child: Scaffold(
          // Set transparent background for padding the resize area out of the flutter view.
          // This allows the wallpaper goes through our resize area. (Linux only now).
          backgroundColor: isLinux ? Colors.transparent : null,
          body: ConnectionTabPage(
            params: widget.params,
          ),
        ));
  }
}
