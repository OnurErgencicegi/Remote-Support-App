// flutter/lib/desktop/pages/auth/email_verify_page.dart
//
// RemoteSupport - register sonrası açılan email doğrulama ekranı.
// Kullanıcı içeri alınmadan (session kaydedilmeden) önce burada 6 haneli
// kodu girmesi gerekiyor. Doğrulama başarılı olunca kullanıcı LoginPage'e
// yönlendirilir - session açma işi HER ZAMAN normal login() akışından
// geçer, burada ayrıca session kaydetme YAPILMAZ (tek bir "session açma"
// yolu olsun diye bilinçli tercih).

import 'package:flutter/material.dart';
import 'auth_session.dart';

class EmailVerifyPage extends StatefulWidget {
  /// register() çağrısından dönen ham token - Authorization header'ı için.
  final String registerToken;
  final String email;

  const EmailVerifyPage({
    Key? key,
    required this.registerToken,
    required this.email,
  }) : super(key: key);

  @override
  State<EmailVerifyPage> createState() => _EmailVerifyPageState();
}

class _EmailVerifyPageState extends State<EmailVerifyPage> {
  final _codeCtrl = TextEditingController();

  bool _loading = false;
  bool _resending = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Lütfen 6 haneli kodu girin.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    final result = await AuthSession.verifyEmail(widget.registerToken, code);

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      // Doğrulama başarılı - kullanıcıyı login ekranına geri gönder.
      // Session burada AÇILMIYOR, kullanıcı şifresiyle normal login akışını
      // tekrar geçmeli (tek "session açma" yolu login() olsun diye).
      if (!mounted) return;
      Navigator.of(context).pop(true); // true = doğrulama başarılı
    } else {
      setState(() => _error = result.error);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
      _info = null;
    });

    final result = await AuthSession.resendVerification(widget.registerToken);

    if (!mounted) return;
    setState(() => _resending = false);

    if (result.success) {
      setState(
          () => _info = 'Yeni kod gönderildi, mail kutunuzu kontrol edin.');
    } else {
      setState(() => _error = result.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Email Doğrulama',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Text(
                  '${widget.email} adresine gönderilen 6 haneli kodu girin.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, letterSpacing: 6),
                  onSubmitted: (_) => _verify(),
                  decoration: const InputDecoration(
                    labelText: 'Kod',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _info!,
                    style: const TextStyle(color: Colors.green, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _verify,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Doğrula'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _resending ? null : _resend,
                  child: _resending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kodu Tekrar Gönder'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
