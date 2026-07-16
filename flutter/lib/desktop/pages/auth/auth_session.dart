// flutter/lib/desktop/pages/auth/auth_session.dart
//
// RemoteSupport auth-server ile konuşan basit istemci + oturum (token/role)
// saklama katmanı. Saklama için yeni bir paket (shared_preferences vb.)
// eklemek yerine RustDesk'in zaten kullandığı yerel config mekanizmasını
// (bind.mainGetLocalOption / mainSetLocalOption) kullanıyoruz - bu mekanizma
// Rust tarafında persist ediliyor ve tüm kod tabanında zaten kullanılıyor.
//
// NOT: applyServerConfig(), eskiden launcher-app/main/main.js içindeki
// writeRustdeskConfig() fonksiyonunun (RustDesk2.toml'a elle yazma) yaptığı
// işi, RustDesk'in kendi resmi config API'si (bind.mainSetOption) üzerinden
// yapar. Launcher artık kullanılmadığı için bu adım login/register başarılı
// olduktan hemen sonra client içinden tetiklenir.
//
// GÜNCELLEME: AuthGate'in login/logout sonrası anında yeniden çizilebilmesi
// için reaktif (GetX RxBool/RxString) durum eklendi. Artık login/register/
// logout çağrıldığında UI otomatik güncelleniyor - Navigator veya manuel
// setState gerekmiyor.
//
// GÜNCELLEME 2: Kalıcı şifre + onay modu artık koda gömülü default olarak
// uygulanıyor. Teknisyenlerin her makinede elle Ayarlar > Güvenlik'e girip
// "Kalıcı Şifre Kullan" seçmesine gerek yok - applyServerConfig() ilk
// çalıştığında (host dahil, login şartı yok) otomatik olarak:
//   1. verification-method = use-permanent-password yapar (tek kullanımlık
//      parola yerine, süresiz geçerli sabit bir parola kullanılır),
//   2. daha önce hiç üretilmemişse rastgele bir kalıcı parola üretip
//      bind.mainSetPermanentPassword ile set eder (bir kere üretilir, bir
//      daha değişmez - "üretildi" bilgisi local option'da saklanır),
//   3. approve-mode = password yapar (host tarafında ekstra "Kabul Et"
//      tıklaması istenmez, doğru parolayı bilen zaten yeterli onay
//      sayılır).
// NOT: Eskiden host_home_page.dart'ta parolayı 30dk'da bir otomatik
// değiştiren bir mekanizma vardı - bu KALDIRILDI, çünkü kalıcı şifre
// modeliyle doğrudan çelişiyordu. Erişim süresi/tier kısıtlaması artık
// auth-server'daki connections tablosu (ConnectionGuard) üzerinden ayrı
// bir katmanda ele alınıyor, parolanın kendisi sabit kalıyor.
//
// GÜNCELLEME 3: print() çıktısı normal RustDesk log dosyasında (Rust
// log::info! çıktısını tutar) hiç görünmüyordu, release exe'de bunu
// izlemenin yolu yoktu. Bunun yerine, _debugLog() ile ayrı, düz bir
// dosyaya (C:\remotesupport_debug.log) yazıyoruz - böylece release
// build'de bile _ensurePermanentPasswordDefaults()'in tam olarak nerede
// takıldığını (approve-mode/verification-method set edildi mi,
// alreadyInitialized ne, mainSetPermanentPasswordWithResult ok=true/false)
// görebiliyoruz.
import 'package:flutter_hbb/models/server_model.dart'
    show kUsePermanentPassword;
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:get/get.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;

const String kAuthServerBaseUrl = 'http://165.245.219.144:4000';

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
const String kDebugLogPath = r'C:\remotesupport_debug.log';

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
  AuthResult.success()
      : success = true,
        error = null;
  AuthResult.failure(this.error) : success = false;
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

  static Future<AuthResult> login(String email, String password) async {
    return _authRequest('/auth/login', {'email': email, 'password': password});
  }

  static Future<AuthResult> register(
      String email, String password, String role) async {
    return _authRequest(
        '/auth/register', {'email': email, 'password': password, 'role': role});
  }

  static Future<AuthResult> _authRequest(
      String path, Map<String, dynamic> body) async {
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

  /// Launcher'ın eskiden RustDesk2.toml'a elle yazdığı sunucu ayarlarını
  /// (custom-rendezvous-server, relay-server, key) artık RustDesk'in kendi
  /// resmi config API'si üzerinden set ediyoruz. Bu sayede ayrı bir dosya
  /// yazmaya / launcher'a gerek kalmıyor.
  ///
  /// Uygulama her açıldığında (host dahil - login olmasa bile) bir kez
  /// çağrılır, çünkü host'un kendi ID/parolasının doğru sunucuya bağlı
  /// çalışması için bu ayarların login şartı olmadan da uygulanmış olması
  /// gerekir. İdempotent bir işlemdir, tekrar tekrar çağrılması güvenlidir.
  static Future<void> applyServerConfig() async {
    _debugLog('applyServerConfig basladi');
    const serverIp = '165.245.219.144';
    const key = '1pJutc1fhQjUPjeMUqE73Pj3Eq55BxNf4kVes1PzJQ0=';

    await bind.mainSetOption(key: 'custom-rendezvous-server', value: serverIp);
    await bind.mainSetOption(key: 'relay-server', value: '$serverIp:21117');
    // RemoteSupport: stock RustDesk'in dahili API-server/heartbeat/cihaz-kayit
    // mekanizmasi varsayilan olarak rendezvous host'una otomatik ":21114"
    // ekleyip bize ait olmayan bir servise istek atiyordu (orada dinleyen
    // olmadigi icin surekli TimedOut + TCP proxy fallback + secure_tcp
    // hatasi). Kendi auth-server'imizi (port 4000) acikca hedef gostererek
    // bu donguyu engelliyoruz.
    await bind.mainSetOption(key: 'api-server', value: 'http://$serverIp:4000');
    // 'key' bilerek set edilmiyor (bkz. onceki not - secure_tcp/KeyExchange).

    _debugLog(
        'applyServerConfig: server ayarlari set edildi, _ensurePermanentPasswordDefaults cagriliyor');
    await _ensurePermanentPasswordDefaults();
    _debugLog('applyServerConfig bitti');
  }

  /// RemoteSupport: kalıcı şifre modunu ve onay modunu default olarak
  /// açar. approve-mode ve verification-method HER ACILISTA idempotent
  /// olarak yeniden set edilir (bir onceki hatada bu deger diskte
  /// kayboluyordu ve "initialized" bayragi true oldugu icin bir daha
  /// hic denenmiyordu, host kalici olarak "Tek Kullanimlik Parola: -"
  /// durumunda kaliyordu). Sifrenin KENDISI ise idempotent flag ile
  /// korunur - bir kez üretilir, bir daha değişmez.
  static Future<void> _ensurePermanentPasswordDefaults() async {
    _debugLog('_ensurePermanentPasswordDefaults basladi');

    await bind.mainSetOption(key: 'approve-mode', value: 'password');
    await bind.mainSetOption(
        key: 'verification-method', value: kUsePermanentPassword);
    _debugLog(
        'approve-mode ve verification-method set edildi (her acilista tekrarlanir)');

    final alreadyInitialized =
        bind.mainGetLocalOption(key: kOptionPermanentPasswordInitialized) ==
            'true';
    _debugLog('alreadyInitialized=$alreadyInitialized');
    if (alreadyInitialized) {
      // Sifrenin kendisi zaten uretildi, bir daha DEGISTIRMIYORUZ
      // (kullanici elle degistirmis olabilir). Yukaridaki iki satir
      // zaten calisti, bu yeterli.
      _debugLog('sifre zaten uretilmis, cikiliyor');
      return;
    }

    final generatedPassword = _generateRandomPassword();
    _debugLog('yeni sifre uretiliyor: $generatedPassword');
    final ok = await bind.mainSetPermanentPasswordWithResult(
        password: generatedPassword);
    _debugLog('mainSetPermanentPasswordWithResult sonucu ok=$ok');
    if (!ok) {
      // Basarisiz oldu, bayragi set etmiyoruz, bir dahaki acilista
      // sifre uretmeyi tekrar dener.
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
