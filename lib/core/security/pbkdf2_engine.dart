import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// محرّك PBKDF2-HMAC-SHA256 (مخرجات 32 بايت = كتلة واحدة).
///
/// له مساران يعطيان نفس النتيجة بالضبط بايتًا ببايت:
///  1. [Pbkdf2Engine.derive] يحاول أولًا مكتبة ويندوز الأصلية (CNG: bcrypt.dll)
///     وهي أسرع بعشرات المرات من أي كود Dart، ولا تحتاج أي حزمة إضافية.
///  2. إن لم تتوفر (نظام قديم، أو خطأ غير متوقع، أو فشل الاختبار الذاتي)
///     يُستخدم تنفيذ Dart محسَّن ومكتوب يدويًا ([pbkdf2Sha256Dart]).
///
/// قبل الاعتماد على المسار الأصلي يُجرى اختبار ذاتي بمتجه معروف؛ لو لم تطابق
/// النتيجة تمامًا يُتجاهل المسار الأصلي كليًا. هكذا لا يمكن أن يُنتج المسار
/// الأصلي تجزئة خاطئة تُقفل المدير خارج حسابه.
///
/// ملاحظة: هذه الدوال متزامنة وثقيلة، ويجب استدعاؤها داخل Isolate منفصل
/// (يفعل ذلك `PasswordHasher`) حتى لا تتجمّد الواجهة.
class Pbkdf2Engine {
  Pbkdf2Engine._();

  /// نتيجة الاشتقاق ومعها المسار المستخدم.
  static Pbkdf2Result derive(
    List<int> password,
    List<int> salt,
    int iterations,
  ) {
    if (_nativeSelfTestPasses()) {
      final native = pbkdf2Sha256Native(password, salt, iterations);
      if (native != null) return Pbkdf2Result(native, true);
    }
    return Pbkdf2Result(pbkdf2Sha256Dart(password, salt, iterations), false);
  }

  /// هل المسار الأصلي متاح وسليم على هذا الجهاز؟ (داخل الـ Isolate الحالي)
  static bool get nativeAvailable => _nativeSelfTestPasses();

  // RFC 7914 / متجه معروف: password="password", salt="salt", c=4096.
  static const String _selfTestHex =
      'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a';

  static bool? _selfTestCache;

  static bool _nativeSelfTestPasses() {
    final cached = _selfTestCache;
    if (cached != null) return cached;
    var ok = false;
    try {
      final out = pbkdf2Sha256Native(
        'password'.codeUnits,
        'salt'.codeUnits,
        4096,
      );
      ok = out != null && _toHex(out) == _selfTestHex;
    } catch (_) {
      ok = false;
    }
    return _selfTestCache = ok;
  }

  static String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class Pbkdf2Result {
  final Uint8List bytes;
  final bool usedNative;
  const Pbkdf2Result(this.bytes, this.usedNative);
}

// ===========================================================================
//  المسار الأصلي: bcrypt.dll (Windows CNG) عبر dart:ffi — بدون حزم إضافية
// ===========================================================================

typedef _OpenNative = Int32 Function(
    Pointer<Pointer<Void>>, Pointer<Uint16>, Pointer<Uint16>, Uint32);
typedef _OpenDart = int Function(
    Pointer<Pointer<Void>>, Pointer<Uint16>, Pointer<Uint16>, int);

typedef _DeriveNative = Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32,
    Pointer<Uint8>, Uint32, Uint64, Pointer<Uint8>, Uint32, Uint32);
typedef _DeriveDart = int Function(Pointer<Void>, Pointer<Uint8>, int,
    Pointer<Uint8>, int, int, Pointer<Uint8>, int, int);

typedef _CloseNative = Int32 Function(Pointer<Void>, Uint32);
typedef _CloseDart = int Function(Pointer<Void>, int);

typedef _GetHeapNative = Pointer<Void> Function();
typedef _GetHeapDart = Pointer<Void> Function();

typedef _HeapAllocNative = Pointer<Void> Function(
    Pointer<Void>, Uint32, IntPtr);
typedef _HeapAllocDart = Pointer<Void> Function(Pointer<Void>, int, int);

typedef _HeapFreeNative = Int32 Function(Pointer<Void>, Uint32, Pointer<Void>);
typedef _HeapFreeDart = int Function(Pointer<Void>, int, Pointer<Void>);

const int _bcryptAlgHandleHmacFlag = 0x00000008;
const int _heapZeroMemory = 0x00000008;

/// يعيد null إن لم يتوفر المسار الأصلي لأي سبب. لا يرمي استثناءات أبدًا.
Uint8List? pbkdf2Sha256Native(
  List<int> password,
  List<int> salt,
  int iterations,
) {
  if (!Platform.isWindows) return null;
  // BCryptDeriveKeyPBKDF2 يرفض الأطوال الصفرية في بعض الإصدارات؛ المسار
  // البرمجي يتولى هذه الحالة النادرة.
  if (password.isEmpty || salt.isEmpty || iterations < 1) return null;

  Pointer<Void> heap = nullptr;
  late final _HeapAllocDart heapAlloc;
  late final _HeapFreeDart heapFree;
  final allocated = <Pointer<Void>>[];
  Pointer<Void> algHandle = nullptr;
  late final _CloseDart closeProvider;
  var providerOpened = false;

  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getHeap =
        kernel32.lookupFunction<_GetHeapNative, _GetHeapDart>('GetProcessHeap');
    heapAlloc = kernel32
        .lookupFunction<_HeapAllocNative, _HeapAllocDart>('HeapAlloc');
    heapFree =
        kernel32.lookupFunction<_HeapFreeNative, _HeapFreeDart>('HeapFree');
    heap = getHeap();
    if (heap == nullptr) return null;

    Pointer<Uint8> alloc(int size) {
      final p = heapAlloc(heap, _heapZeroMemory, size == 0 ? 1 : size);
      if (p == nullptr) throw StateError('HeapAlloc failed');
      allocated.add(p);
      return p.cast<Uint8>();
    }

    final bcrypt = DynamicLibrary.open('bcrypt.dll');
    final open = bcrypt
        .lookupFunction<_OpenNative, _OpenDart>('BCryptOpenAlgorithmProvider');
    final derive = bcrypt
        .lookupFunction<_DeriveNative, _DeriveDart>('BCryptDeriveKeyPBKDF2');
    closeProvider = bcrypt.lookupFunction<_CloseNative, _CloseDart>(
        'BCryptCloseAlgorithmProvider');

    // "SHA256" بترميز UTF-16 منتهٍ بصفر.
    const algName = 'SHA256';
    final algPtr = alloc((algName.length + 1) * 2).cast<Uint16>();
    final algView = algPtr.asTypedList(algName.length + 1);
    for (var i = 0; i < algName.length; i++) {
      algView[i] = algName.codeUnitAt(i);
    }
    algView[algName.length] = 0;

    final handlePtr = alloc(sizeOf<IntPtr>()).cast<Pointer<Void>>();
    var status = open(handlePtr, algPtr, nullptr, _bcryptAlgHandleHmacFlag);
    if (status != 0) return null;
    algHandle = handlePtr.value;
    providerOpened = true;

    final pwPtr = alloc(password.length);
    pwPtr.asTypedList(password.length).setAll(0, password);
    final saltPtr = alloc(salt.length);
    saltPtr.asTypedList(salt.length).setAll(0, salt);
    final outPtr = alloc(32);

    status = derive(algHandle, pwPtr, password.length, saltPtr, salt.length,
        iterations, outPtr, 32, 0);
    if (status != 0) return null;

    final result = Uint8List(32)..setAll(0, outPtr.asTypedList(32));

    // مسح كلمة السر من الذاكرة الأصلية قبل تحريرها.
    pwPtr.asTypedList(password.length).fillRange(0, password.length, 0);
    return result;
  } catch (_) {
    return null;
  } finally {
    try {
      if (providerOpened && algHandle != nullptr) closeProvider(algHandle, 0);
    } catch (_) {}
    try {
      for (final p in allocated) {
        heapFree(heap, 0, p);
      }
    } catch (_) {}
  }
}

// ===========================================================================
//  المسار البرمجي: SHA-256 / HMAC / PBKDF2 مكتوبة يدويًا ومحسَّنة
//  (بلا أي تخصيص ذاكرة داخل الحلقة، وبـ ضغطتين فقط لكل تكرار بدل أربع)
// ===========================================================================

const int _m = 0xFFFFFFFF;

final Uint32List _k = Uint32List.fromList(const [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, //
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]);

final Uint32List _iv = Uint32List.fromList(const [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
]);

@pragma('vm:prefer-inline')
int _rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & _m;

/// ضغطة SHA-256 واحدة: تقرأ `w[0..15]` وتكتب `out = state + compress(state, w)`.
/// `out` يجب ألا يكون نفس `state`.
void _compress(Uint32List state, Uint32List w, Uint32List out) {
  for (var t = 16; t < 64; t++) {
    final w15 = w[t - 15];
    final w2 = w[t - 2];
    final s0 = _rotr(w15, 7) ^ _rotr(w15, 18) ^ (w15 >>> 3);
    final s1 = _rotr(w2, 17) ^ _rotr(w2, 19) ^ (w2 >>> 10);
    w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & _m;
  }
  var a = state[0], b = state[1], c = state[2], d = state[3];
  var e = state[4], f = state[5], g = state[6], h = state[7];
  for (var t = 0; t < 64; t++) {
    final bigS1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
    final ch = (e & f) ^ ((~e & _m) & g);
    final t1 = (h + bigS1 + ch + _k[t] + w[t]) & _m;
    final bigS0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
    final maj = (a & b) ^ (a & c) ^ (b & c);
    final t2 = (bigS0 + maj) & _m;
    h = g;
    g = f;
    f = e;
    e = (d + t1) & _m;
    d = c;
    c = b;
    b = a;
    a = (t1 + t2) & _m;
  }
  out[0] = (state[0] + a) & _m;
  out[1] = (state[1] + b) & _m;
  out[2] = (state[2] + c) & _m;
  out[3] = (state[3] + d) & _m;
  out[4] = (state[4] + e) & _m;
  out[5] = (state[5] + f) & _m;
  out[6] = (state[6] + g) & _m;
  out[7] = (state[7] + h) & _m;
}

/// يكمل تجزئة SHA-256 للرسالة [msg] بدءًا من حالة وسيطة [start] سبقها
/// [prefixBytes] بايتًا (مضاعف للـ 64). يعيد الحالة النهائية (8 كلمات).
Uint32List _sha256From(Uint32List start, int prefixBytes, List<int> msg) {
  final total = prefixBytes + msg.length;
  final paddedLen = ((msg.length + 9 + 63) ~/ 64) * 64;
  final buf = Uint8List(paddedLen)..setAll(0, msg);
  buf[msg.length] = 0x80;
  final bitLen = total * 8;
  for (var i = 0; i < 8; i++) {
    buf[paddedLen - 1 - i] = (bitLen >>> (8 * i)) & 0xFF;
  }
  var state = Uint32List.fromList(start);
  var next = Uint32List(8);
  final w = Uint32List(64);
  for (var off = 0; off < paddedLen; off += 64) {
    for (var i = 0; i < 16; i++) {
      final j = off + i * 4;
      w[i] = (buf[j] << 24) | (buf[j + 1] << 16) | (buf[j + 2] << 8) | buf[j + 3];
    }
    _compress(state, w, next);
    final tmp = state;
    state = next;
    next = tmp;
  }
  return state;
}

Uint8List _wordsToBytes(Uint32List words) {
  final out = Uint8List(words.length * 4);
  for (var i = 0; i < words.length; i++) {
    out[i * 4] = words[i] >>> 24;
    out[i * 4 + 1] = (words[i] >>> 16) & 0xFF;
    out[i * 4 + 2] = (words[i] >>> 8) & 0xFF;
    out[i * 4 + 3] = words[i] & 0xFF;
  }
  return out;
}

/// حالة SHA-256 بعد معالجة كتلة المفتاح XOR [pad] (0x36 للداخلي، 0x5c للخارجي).
Uint32List _padState(Uint8List keyBlock, int pad) {
  final w = Uint32List(64);
  for (var i = 0; i < 16; i++) {
    final j = i * 4;
    w[i] = ((keyBlock[j] ^ pad) << 24) |
        ((keyBlock[j + 1] ^ pad) << 16) |
        ((keyBlock[j + 2] ^ pad) << 8) |
        (keyBlock[j + 3] ^ pad);
  }
  final out = Uint32List(8);
  _compress(_iv, w, out);
  return out;
}

/// PBKDF2-HMAC-SHA256 بطول مخرجات 32 بايت. تنفيذ Dart محسَّن.
Uint8List pbkdf2Sha256Dart(List<int> password, List<int> salt, int iterations) {
  if (iterations < 1) throw ArgumentError.value(iterations, 'iterations');

  // مفتاح HMAC: إن زاد عن 64 بايت يُجزَّأ أولًا، ثم يُحشى بأصفار حتى 64.
  final keyBlock = Uint8List(64);
  if (password.length > 64) {
    keyBlock.setAll(0, _wordsToBytes(_sha256From(_iv, 0, password)));
  } else {
    keyBlock.setAll(0, password);
  }
  final innerState = _padState(keyBlock, 0x36);
  final outerState = _padState(keyBlock, 0x5c);

  // U1 = HMAC(P, salt || INT_32_BE(1))
  final first = Uint8List(salt.length + 4)..setAll(0, salt);
  first[first.length - 1] = 1;
  final innerDigest = _sha256From(innerState, 64, first);
  var u = _sha256From(outerState, 64, _wordsToBytes(innerDigest));

  final acc = Uint32List.fromList(u);
  if (iterations > 1) {
    // كل U لاحق = HMAC(P, U_prev) — رسالة 32 بايت فتتسع في كتلة واحدة لكل نصف.
    final w = Uint32List(64);
    w[8] = 0x80000000;
    w[15] = (64 + 32) * 8; // 768 بت
    var tmp = Uint32List(8);
    var cur = Uint32List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      for (var j = 0; j < 8; j++) {
        w[j] = cur[j];
      }
      _compress(innerState, w, tmp);
      for (var j = 0; j < 8; j++) {
        w[j] = tmp[j];
      }
      _compress(outerState, w, cur);
      for (var j = 0; j < 8; j++) {
        acc[j] ^= cur[j];
      }
    }
  }
  return _wordsToBytes(acc);
}
