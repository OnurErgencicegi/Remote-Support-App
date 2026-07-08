// flutter/lib/desktop/pages/auth/login_page.dart
//
// RemoteSupport - kendi auth-server'ımıza karşı giriş/kayıt ekranı.
// Client artık launcher'sız da (rustdesk.exe tek başına) çalıştırıldığında
// önce burayı gösterip auth-server'dan doğrulama alıyor.

import 'package:flutter/material.dart';
import 'auth_session.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onAuthenticated;
  const LoginPage({Key? key, required this.onAuthenticated}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isRegisterMode = false;
  String _selectedRole = AuthRole.controller;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

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
    });

    final result = _isRegisterMode
        ? await AuthSession.register(email, password, _selectedRole)
        : await AuthSession.login(email, password);

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      widget.onAuthenticated();
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
                if (_isRegisterMode) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'Bu cihaz ne olarak kullanılacak?',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: AuthRole.host,
                        label: Text('Destek Alınacak\n(Host)'),
                      ),
                      ButtonSegment(
                        value: AuthRole.controller,
                        label: Text('Bağlanacak\n(Teknisyen)'),
                      ),
                    ],
                    selected: {_selectedRole},
                    onSelectionChanged: (s) =>
                        setState(() => _selectedRole = s.first),
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
                const SizedBox(height: 24),
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
