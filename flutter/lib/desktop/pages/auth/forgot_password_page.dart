// flutter/lib/desktop/pages/auth/forgot_password_page.dart
//
// RemoteSupport - şifremi unuttum akışı. 2 adım aynı ekranda:
// Adım 1: email gir -> kod gönderilir.
// Adım 2: kod + yeni şifre gir -> şifre sıfırlanır.
// Başarılı olursa LoginPage'e geri döner (kullanıcı yeni şifresiyle
// normal login akışından geçer).

import 'package:flutter/material.dart';
import 'auth_session.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _newPassConfirmCtrl = TextEditingController();

  bool _codeRequested = false;
  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPassCtrl.dispose();
    _newPassConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Email gerekli.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    final result = await AuthSession.forgotPassword(email);

    if (!mounted) return;
    setState(() => _loading = false);

    // Sunucu her zaman {"success":true} döner (email kayıtlı olmasa bile,
    // bilgi sızdırmamak için) - bu yüzden hata durumu sadece ağ/sunucu
    // hatası olur.
    if (result.success) {
      setState(() {
        _codeRequested = true;
        _info = 'Email kayıtlıysa, kodu içeren bir mail gönderildi.';
      });
    } else {
      setState(() => _error = result.error);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final newPass = _newPassCtrl.text;
    final newPassConfirm = _newPassConfirmCtrl.text;

    if (code.length != 6) {
      setState(() => _error = 'Lütfen 6 haneli kodu girin.');
      return;
    }
    if (newPass.isEmpty) {
      setState(() => _error = 'Yeni parola gerekli.');
      return;
    }
    if (newPass != newPassConfirm) {
      setState(() => _error = 'Parolalar eşleşmiyor.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    final result = await AuthSession.resetPassword(email, code, newPass);

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      if (!mounted) return;
      // Başarılı - login ekranına dön, kullanıcı yeni şifresiyle girsin.
      Navigator.of(context).pop(true);
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
                Text(
                  'Şifremi Unuttum',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _emailCtrl,
                  enabled: !_codeRequested,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_codeRequested) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Kod',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _newPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Yeni Parola',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _newPassConfirmCtrl,
                    obscureText: true,
                    onSubmitted: (_) => _resetPassword(),
                    decoration: const InputDecoration(
                      labelText: 'Yeni Parola (Tekrar)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _info!,
                    style: const TextStyle(color: Colors.green, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading
                      ? null
                      : (_codeRequested ? _resetPassword : _requestCode),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _codeRequested ? 'Şifreyi Sıfırla' : 'Kod Gönder'),
                  ),
                ),
                if (_codeRequested) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                              _codeRequested = false;
                              _error = null;
                              _info = null;
                            }),
                    child: const Text('Farklı bir email dene'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
