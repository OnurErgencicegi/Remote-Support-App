// flutter/lib/desktop/pages/auth/login_page.dart
//
// RemoteSupport - kendi auth-server'ımıza karşı giriş/kayıt ekranı.
//
// GÜNCELLEME (email doğrulama):
// - Register artık otomatik login yapmıyor. Başarılı olunca EmailVerifyPage
//   açılıyor (Navigator.push), doğrulama tamamlanınca kullanıcı buraya geri
//   dönüyor ve "şimdi giriş yapın" mesajıyla login moduna geçiliyor.
// - login()'den email_not_verified hatası gelirse, kullanıcıya şifre formu
//   yerine "email'inizi doğrulayın" mesajı + tekrar kod gönderme imkanı
//   sunuluyor. NOT: login() email_not_verified döndüğünde register token'ı
//   elimizde olmuyor (login sadece email+şifre alır) - bu yüzden bu durumda
//   "Kodu Tekrar Gönder" için email adresini tekrar register akışından değil
//   ayrı bir yoldan istemek gerekir. Basit ve güvenilir çözüm: kullanıcıya
//   sadece "email'inizi doğrulayın, mail kutunuzu kontrol edin" mesajı
//   gösteriyoruz; kod bulunamadıysa "Şifremi Unuttum değil, kayıt sırasında
//   size gelen kodu kullanın" yönlendirmesi yapıyoruz. Kod gerçekten
//   kaybolduysa kullanıcı yeniden kayıt deneyip resend akışına
//   düşebilir - bu köşe durumu şimdilik kabul edilebilir.
// - "Şifremi Unuttum" linki eklendi.

import 'package:flutter/material.dart';
import 'auth_session.dart';
import 'email_verify_page.dart';
import 'forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onAuthenticated;
  const LoginPage({Key? key, required this.onAuthenticated}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isRegisterMode = false;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email ve parola gerekli.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    if (_isRegisterMode) {
      await _handleRegister(email, password);
    } else {
      await _handleLogin(email, password);
    }
  }

  Future<void> _handleLogin(String email, String password) async {
    final result = await AuthSession.login(email, password);

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      widget.onAuthenticated();
    } else if (result.isEmailNotVerified) {
      setState(() {
        _error = null;
        _info =
            'Email adresiniz doğrulanmamış. Lütfen kayıt olurken gönderilen '
            'kodu girin, ya da mail kutunuzu kontrol edin.';
      });
    } else {
      setState(() => _error = result.error);
    }
  }

  Future<void> _handleRegister(String email, String password) async {
    // Bu ekrandan kayıt olan herkes teknisyen/controller'dır. Host'lar
    // hiç kayıt olmadan HostHomePage'de kendi ID/parolasını zaten görüyor.
    final result =
        await AuthSession.register(email, password, AuthRole.controller);

    if (!mounted) return;
    setState(() => _loading = false);

    if (!result.success) {
      setState(() => _error = result.error);
      return;
    }

    // Kayıt başarılı ama SESSION AÇILMADI - önce email doğrulama ekranına
    // git. Doğrulama başarılı olursa (pop(true) ile dönerse) kullanıcıyı
    // login moduna alıp "şimdi giriş yapın" bilgisi göster.
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EmailVerifyPage(
          registerToken: result.token!,
          email: email,
        ),
      ),
    );

    if (!mounted) return;

    if (verified == true) {
      setState(() {
        _isRegisterMode = false;
        _error = null;
        _info = 'Email doğrulandı! Şimdi giriş yapabilirsiniz.';
        _passCtrl.clear();
      });
    }
  }

  Future<void> _openForgotPassword() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
    );

    if (!mounted) return;

    if (result == true) {
      setState(() {
        _error = null;
        _info = 'Şifreniz sıfırlandı. Yeni şifrenizle giriş yapabilirsiniz.';
      });
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
                  _isRegisterMode ? 'Hesap Oluştur' : 'Giriş Yap',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Parola',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (!_isRegisterMode) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _loading ? null : _openForgotPassword,
                      child: const Text('Şifremi Unuttum',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
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
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isRegisterMode ? 'Kayıt Ol' : 'Giriş Yap'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                            _isRegisterMode = !_isRegisterMode;
                            _error = null;
                            _info = null;
                          }),
                  child: Text(_isRegisterMode
                      ? 'Zaten hesabım var, giriş yap'
                      : 'Hesabım yok, kayıt ol'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
