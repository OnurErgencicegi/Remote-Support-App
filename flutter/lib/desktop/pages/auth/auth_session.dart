// flutter/lib/desktop/pages/auth/auth_session.dart
//
// RemoteSupport auth-server ile konuşan basit istemci + oturum (token/role)
// saklama katmanı. Saklama için yeni bir paket (shared_preferences vb.)
// eklemek yerine RustDesk'in zaten kullandığı yerel config mekanizmasını
// (bind.mainGetLocalOption / mainSetLocalOption) kullanıyoruz - bu mekanizma
// Rust tarafında persist ediliyor ve tüm kod tabanında zaten kullanılıyor.
//
// GÜNCELLEME (email doğrulama): Artık kayıt (register) başarılı olsa bile
// OTOMATİK LOGIN YAPILMIYOR. Ürün kararı: email doğrulanmamış bir kullanıcı
// sistemin "kapısından bile geçmemiş" gibi ele alınıyor. register() artık
// session'ı kaydetmiyor, sadece dönen ham token'ı (email doğrulama isteği
// için Authorization header'ında kullanılacak) çağırana döndürüyor. Bu token
// _saveSession() ile kalıcı hale gelmiyor - sadece doğrulama ekranı boyunca
// bellekte tutulup kullanılıyor (bkz. EmailVerifyPage).
//
// login() da artık sunucudan 403 + {"error":"email_not_verified"} gelirse
// bunu ayrı bir AuthResult alt durumuyla (isEmailNotVerified) işaretliyor,
// böylece UI kullanıcıyı doğrudan doğrulama ekranına yönlendirebiliyor.
import 'package:flutter_hbb/models/server_model.dart' show kUseBothPasswords;
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:get/get.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;

const String kAuthServerBaseUrl = 'http://165.245.219.144:4000';
const String kInternalApiKey =
    '7f3a9c2e5b8d1046af72c9e4b3d8f105a6c2e9b47d1f83052c6a9e4b7d1f830';
const String kOptionAuthToken = 'remotesupport-auth-token';
const String kOptionAuthRole = 'remotesupport-auth-role';
const String kOptionAuthEmail = 'remotesupport-auth-email';

// RemoteSupport: kalıcı şifrenin bu makinede daha önce üretilip
// üretilmediğini işaretlemek için kullanılan local option anahtarı.
const String kOptionPermanentPasswordInitialized =
    'remotesupport-permanent-password-initialized';

// RemoteSupport: debug log dosyasının tam yolu. Sabit, elle silinip
// tekrar okunabilir. Kalıcı olarak koda bırakılması sakıncalı değil,
// sadece küçük metin satırları yazıyor.
const String kDebugLogPath = r'C:\Users\onur_\remotesupport_debug.log';
void _debugLog(String msg) {
  try {
    final f = File(kDebugLogPath);
    f.writeAsStringSync('${DateTime.now()}: $msg\n', mode: FileMode.append);
  } catch (_) {
    // Yazma başarısız olursa (izin, disk, vs.) sessizce yut - bu sadece
    // teşhis amaçlı, uygulamanın normal akışını bozmamalı.
  }
}

/// Sunucudaki role değerleriyle birebir eşleşir (bkz. authRoutes.js).
class AuthRole {
  static const String host = 'host';
  static const String controller = 'controller';
}

class AuthResult {
  final bool success;
  final String? error;

  /// RemoteSupport: sunucu 403 + {"error":"email_not_verified"} dönerse
  /// true olur. UI bunu görünce kullanıcıyı EmailVerifyPage'e yönlendirir.
  final bool isEmailNotVerified;

  AuthResult.success()
      : success = true,
        error = null,
        isEmailNotVerified = false;
  AuthResult.failure(this.error, {this.isEmailNotVerified = false})
      : success = false;
}

/// RemoteSupport: register() artık session kaydetmediği için, çağıran tarafa
/// (register sonrası doğrulama ekranına geçiş için) hem sonucu hem de
/// (başarılıysa) doğrulama isteklerinde kullanılacak ham token'ı taşır.
class RegisterResult {
  final bool success;
  final String? error;
  final String? token;
  RegisterResult.success(this.token)
      : success = true,
        error = null;
  RegisterResult.failure(this.error)
      : success = false,
        token = null;
}

class AuthSession {
  /// Reaktif durum: AuthGate ve diğer widget'lar bunu Obx(...) ile dinler.
  /// Uygulama açılışında yerel config'ten okunan değerle başlatılır.
  static final RxBool authenticated = (_readIsLoggedIn()).obs;
  static final RxString roleRx = (_readRole()).obs;

  static bool _readIsLoggedIn() =>
      (bind.mainGetLocalOption(key: kOptionAuthToken)).isNotEmpty;

  static String _readRole() {
    final r = bind.mainGetLocalOption(key: kOptionAuthRole);
    return r.isEmpty ? AuthRole.host : r;
  }

  /// Geriye dönük uyumluluk için senkron getter'lar (bazı yerlerde hâlâ
  /// kullanılıyor olabilir). Reaktif UI için authenticated/roleRx tercih edin.
  static bool get isLoggedIn => authenticated.value;
  static String get role => roleRx.value;

  static String get email => bind.mainGetLocalOption(key: kOptionAuthEmail);

  /// RemoteSupport: connection_guard.dart gibi diğer HTTP çağrılarının
  /// Authorization header'ı için kullandığı ham token.
  static String get token => bind.mainGetLocalOption(key: kOptionAuthToken);

  static Future<void> _saveSession(
      String token, String role, String email) async {
    await bind.mainSetLocalOption(key: kOptionAuthToken, value: token);
    await bind.mainSetLocalOption(key: kOptionAuthRole, value: role);
    await bind.mainSetLocalOption(key: kOptionAuthEmail, value: email);
    authenticated.value = true;
    roleRx.value = role;
  }

  static Future<void> logout() async {
    await bind.mainSetLocalOption(key: kOptionAuthToken, value: '');
    await bind.mainSetLocalOption(key: kOptionAuthRole, value: '');
    await bind.mainSetLocalOption(key: kOptionAuthEmail, value: '');
    authenticated.value = false;
    // Çıkış yapınca varsayılan olarak host moduna dön (kayıt zorunlu değil).
    roleRx.value = AuthRole.host;
  }

  /// RemoteSupport: tier durumunu ve aylık kalan kullanım süresini
  /// auth-server'dan çeker (GET /auth/me/usage). Giriş yapılmamışsa ya da
  /// istek başarısız olursa null döner - çağıran taraf (UI) bunu "gösterme"
  /// sinyali olarak kullanmalı.
  static Future<UsageInfo?> fetchUsage() async {
    if (token.isEmpty) return null;
    try {
      final resp = await http.get(
        Uri.parse('$kAuthServerBaseUrl/auth/me/usage'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return UsageInfo.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  /// RemoteSupport: email doğrulanmamışsa 403 dönebilir - bu durumda
  /// AuthResult.isEmailNotVerified = true olur, session KAYDEDİLMEZ.
  static Future<AuthResult> login(String email, String password) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$kAuthServerBaseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 403 && data['error'] == 'email_not_verified') {
        return AuthResult.failure(
          data['message']?.toString() ?? 'Email doğrulanmamış.',
          isEmailNotVerified: true,
        );
      }

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

  /// RemoteSupport: KAYIT BAŞARILI OLSA BİLE ARTIK OTOMATİK LOGIN YAPMIYOR.
  /// Email doğrulanana kadar kullanıcı "hiç kapıdan geçmemiş" sayılıyor -
  /// session kaydedilmiyor, authenticated/roleRx değişmiyor. Dönen token,
  /// sadece bir sonraki adımda (verifyEmail/resendVerification) Authorization
  /// header'ı olarak kullanılmak üzere çağırana veriliyor.
  static Future<RegisterResult> register(
      String email, String password, String role) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$kAuthServerBaseUrl/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
                {'email': email, 'password': password, 'role': role}),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode != 200) {
        return RegisterResult.failure(
            data['error']?.toString() ?? 'Bilinmeyen hata');
      }

      final token = data['token'] as String?;
      if (token == null) {
        return RegisterResult.failure('Sunucu beklenmeyen bir yanıt döndürdü.');
      }

      // BİLEREK _saveSession() ÇAĞRILMIYOR - email doğrulanmadan içeri
      // girilmiyor.
      return RegisterResult.success(token);
    } catch (e) {
      return RegisterResult.failure('Sunucuya ulaşılamadı: $e');
    }
  }

  /// RemoteSupport: register() sonrası dönen ham token ile 6 haneli kodu
  /// doğrular. Başarılı olursa DOĞRUDAN login yapmaz - çağıran taraf
  /// (EmailVerifyPage) kullanıcıyı LoginPage'e yönlendirip normal login
  /// akışını tekrar çalıştırmalı (böylece _saveSession() normal login
  /// yolundan geçmiş olur, tek bir "session açma" yolu kalır).
  static Future<AuthResult> verifyEmail(String registerToken, String code) {
    return _tokenAuthRequest(
      '/auth/verify-email',
      registerToken,
      {'code': code},
    );
  }

  static Future<AuthResult> resendVerification(String registerToken) {
    return _tokenAuthRequest(
      '/auth/resend-verification',
      registerToken,
      {},
    );
  }

  /// RemoteSupport: token gerektirmez, kullanıcı henüz giriş yapamıyor.
  static Future<AuthResult> forgotPassword(String email) {
    return _simpleAuthRequest('/auth/forgot-password', {'email': email});
  }

  /// RemoteSupport: token gerektirmez, kullanıcı henüz giriş yapamıyor.
  static Future<AuthResult> resetPassword(
      String email, String code, String newPassword) {
    return _simpleAuthRequest('/auth/reset-password', {
      'email': email,
      'code': code,
      'newPassword': newPassword,
    });
  }

  /// RemoteSupport: Authorization: Bearer header'ı ile POST atan, sadece
  /// {"success":true}/{"error":"..."} bekleyen (token/user beklemeyen)
  /// generic helper. verify-email ve resend-verification için kullanılır.
  static Future<AuthResult> _tokenAuthRequest(
    String path,
    String bearerToken,
    Map<String, dynamic> body,
  ) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$kAuthServerBaseUrl$path'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $bearerToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode != 200) {
        return AuthResult.failure(
            data['error']?.toString() ?? 'Bilinmeyen hata');
      }
      return AuthResult.success();
    } catch (e) {
      return AuthResult.failure('Sunucuya ulaşılamadı: $e');
    }
  }

  /// RemoteSupport: header gerektirmeyen, sadece {"success":true}/{"error"}
  /// bekleyen generic helper. forgot-password ve reset-password için.
  static Future<AuthResult> _simpleAuthRequest(
    String path,
    Map<String, dynamic> body,
  ) async {
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
      return AuthResult.success();
    } catch (e) {
      return AuthResult.failure('Sunucuya ulaşılamadı: $e');
    }
  }

  /// RemoteSupport: bu host'un sabit şifresini auth-server'dan çeker.
  /// Host henüz login olmamış olabileceği için kimlik olarak token değil,
  /// RustDesk ID kullanılır (server'da host_peer_id olarak saklanır).
  static Future<String?> _fetchPasswordFromServer() async {
    try {
      final myId = await bind.mainGetMyId();
      _debugLog('myId=$myId (fetch icin)');
      if (myId.isEmpty) return null;
      final resp = await http.get(
        Uri.parse('$kAuthServerBaseUrl/auth/host/password?hostId=$myId'),
        headers: {'X-Internal-Key': kInternalApiKey},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final pw = data['password'] as String?;
      return (pw == null || pw.isEmpty) ? null : pw;
    } catch (e) {
      _debugLog('_fetchPasswordFromServer hata: $e');
      return null;
    }
  }

  /// RemoteSupport: bu host'un sabit şifresini auth-server'a yazar. Public,
  /// çünkü desktop_home_page.dart'taki setPasswordDialog() (kullanıcının
  /// elle "Kalıcı parola oluştur" ile girdiği şifre) de bunu çağırıyor.
  static Future<bool> pushPasswordToServer(String password) async {
    try {
      final myId = await bind.mainGetMyId();
      _debugLog('myId=$myId (push icin)');
      if (myId.isEmpty) {
        _debugLog('pushPasswordToServer: myId bos, vazgeciliyor');
        return false;
      }
      final resp = await http
          .post(
            Uri.parse('$kAuthServerBaseUrl/auth/host/password'),
            headers: {
              'Content-Type': 'application/json',
              'X-Internal-Key': kInternalApiKey,
            },
            body: jsonEncode({'hostId': myId, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));
      final ok = resp.statusCode == 200;
      _debugLog('pushPasswordToServer sonucu: statusCode=${resp.statusCode}');
      return ok;
    } catch (e) {
      _debugLog('pushPasswordToServer hata: $e');
      return false;
    }
  }

  /// Launcher'ın eskiden RustDesk2.toml'a elle yazdığı sunucu ayarlarını
  /// (custom-rendezvous-server, relay-server, key) artık RustDesk'in kendi
  /// resmi config API'si (bind.mainSetOption) üzerinden set ediyoruz.
  ///
  /// Uygulama her açıldığında (host dahil - login olmasa bile) bir kez
  /// çağrılır. İdempotent bir işlemdir, tekrar tekrar çağrılması güvenlidir.
  static Future<void> applyServerConfig() async {
    _debugLog('applyServerConfig basladi');
    const serverIp = '165.245.219.144';

    await bind.mainSetOption(key: 'custom-rendezvous-server', value: serverIp);
    await bind.mainSetOption(key: 'relay-server', value: '$serverIp:21117');
    await bind.mainSetOption(key: 'api-server', value: 'http://$serverIp:4000');
    // 'key' bilerek set edilmiyor (secure_tcp/KeyExchange sorunu, bkz.
    // DEVİR-TESLİM #3 - hbbs bu mesajı hiç göndermiyor, gereksiz timeout'a
    // yol açıyor). Bizim güvenlik modelimiz zaten token tabanlı.

    _debugLog(
        'applyServerConfig: server ayarlari set edildi, _ensurePermanentPasswordDefaults cagriliyor');
    await _ensurePermanentPasswordDefaults();
    _debugLog('applyServerConfig bitti');
  }

  /// RemoteSupport: kalıcı şifre modunu ve onay modunu default olarak
  /// açar. approve-mode ve verification-method HER ACILISTA idempotent
  /// olarak yeniden set edilir. Sifrenin KENDISI ise idempotent flag ile
  /// korunur - bir kez üretilir, bir daha değişmez.
  static Future<void> _ensurePermanentPasswordDefaults() async {
    _debugLog('_ensurePermanentPasswordDefaults basladi');

    await bind.mainSetOption(key: 'approve-mode', value: 'password');
    await bind.mainSetOption(
        key: 'verification-method', value: kUseBothPasswords);
    _debugLog(
        'approve-mode ve verification-method set edildi (her acilista tekrarlanir)');

    final alreadyInitialized =
        bind.mainGetLocalOption(key: kOptionPermanentPasswordInitialized) ==
            'true';
    final actuallySet =
        (await bind.mainGetOption(key: 'permanent-password-set')) == 'true';
    _debugLog(
        'alreadyInitialized=$alreadyInitialized actuallySet=$actuallySet');
    if (alreadyInitialized && actuallySet) {
      _debugLog('sifre zaten uretilmis ve gercekten mevcut, cikiliyor');
      return;
    }
    if (alreadyInitialized && !actuallySet) {
      _debugLog('UYARI: flag true ama sifre gercekte YOK - yeniden uretiliyor');
    }

    // RemoteSupport: önce server'da bu host için kayıtlı bir şifre var mı
    // bak - varsa onu kullan (server tek doğru kaynak), yoksa yeni üret
    // ve server'a yaz.
    String? password = await _fetchPasswordFromServer();
    if (password == null) {
      password = _generateRandomPassword();
      _debugLog('server\'da sifre yok, yeni uretiliyor: $password');
      final pushed = await pushPasswordToServer(password);
      _debugLog('yeni sifre server\'a push edildi mi: $pushed');
    } else {
      _debugLog('server\'dan mevcut sifre alindi');
    }
    final ok =
        await bind.mainSetPermanentPasswordWithResult(password: password);
    _debugLog('mainSetPermanentPasswordWithResult sonucu ok=$ok');
    if (!ok) {
      _debugLog(
          'sifre ureteme BASARISIZ, flag set edilmiyor, bir dahaki acilista tekrar denenecek');
      return;
    }

    await bind.mainSetLocalOption(
        key: kOptionPermanentPasswordInitialized, value: 'true');
    _debugLog('kalici sifre basariyla ayarlandi, flag=true yazildi');
  }

  static String _generateRandomPassword({int length = 10}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)])
        .join();
  }
}

/// RemoteSupport: /auth/me/usage yanıtını taşıyan basit veri sınıfı.
/// AuthSession.fetchUsage() tarafından döndürülür; UI (örn. üst bar/menü)
/// tier rozeti ve kalan dakika göstergesi için kullanır.
class UsageInfo {
  final String tier;
  final bool proActive;
  final int? proDaysLeft;
  final int? usedMinutesThisMonth;
  final int? remainingMinutesThisMonth;
  final int capMinutes;
  UsageInfo({
    required this.tier,
    required this.proActive,
    this.proDaysLeft,
    this.usedMinutesThisMonth,
    this.remainingMinutesThisMonth,
    required this.capMinutes,
  });
  factory UsageInfo.fromJson(Map<String, dynamic> json) {
    return UsageInfo(
      tier: json['tier'] as String? ?? 'free',
      proActive: json['proActive'] as bool? ?? false,
      proDaysLeft: json['proDaysLeft'] as int?,
      usedMinutesThisMonth: json['usedMinutesThisMonth'] as int?,
      remainingMinutesThisMonth: json['remainingMinutesThisMonth'] as int?,
      capMinutes: json['capMinutes'] as int? ?? 240,
    );
  }
}
