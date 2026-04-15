// lib/pages/profilepage.dart
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // InputFormatters + Uint8List
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saafapp/constant.dart';
import 'dart:ui';
// Firebase
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:saafapp/widgets/saaf_image.dart';


const Color kDeepGreen = Color(0xFF042C25);
const Color kGold = Color(0xFFEBB974);
const Color kBeige = Color(0xFFFFF6E0);
const Color kAccent = Color(0xFFFDCB6E);

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ImagePicker _picker = ImagePicker();
  bool _saving = false;
  bool _loading = true;

  // مفتاح النموذج (Form) للتحقق من الحقول
  final _formKey = GlobalKey<FormState>();

  // بيانات
  String? name, phone, email, region, avatarPath;
  //String? _authErrorMessage;test 
  // حقول
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _editName = false, _editPhone = false, _editEmail = false;

  // Firebase
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  // ملف/بايتات الصورة المختارة محليًا
  String? _pickedFilePath; // للأجهزة
  Uint8List? _pickedBytes; // للويب + معاينة فورية

  // المنطقة
  String? _selectedRegion;
  final List<String> _regions = const [
    'الرياض',
    'مكة المكرمة',
    'المدينة المنورة',
    'القصيم',
    'الشرقية',
    'عسير',
    'تبوك',
    'حائل',
    'الحدود الشمالية',
    'جازان',
    'نجران',
    'الباحة',
    'الجوف',
  ];

  // لمجرد إجبار إعادة بناء HtmlElementView عند الحاجة
  int _avatarRev = 0;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

// 🔔 الدالة المطورة: تدعم الألوان حسب الحالة (نجاح، خطأ، معلومات)
  void _safeToast(String msg, {IconData? icon, String type = 'info'}) {
    if (!mounted) return;
    
    // 🎨 تحديد اللون والأيقونة بناءً على النوع
    Color bgColor;
    Color contentColor = kDeepGreen; // اللون الافتراضي للنص والأيقونة
    IconData toastIcon;

    switch (type) {
      case 'success':
        bgColor = const Color(0xFF1E8D5F).withValues(alpha: 0.7); // أخضر فخم للنجاح
        contentColor = Colors.white; // نص أبيض للوضوح فوق الأخضر
        toastIcon = icon ?? Icons.check_circle_rounded;
        break;
      case 'error':
        bgColor = const Color.fromARGB(255, 153, 30, 30).withValues(alpha: 0.7); // العنابي اللي اخترتيه
        contentColor = Colors.white;
        toastIcon = icon ?? Icons.error_rounded;
        break;
      default: // 'info' أو 'loading'
        bgColor = kBeige.withValues(alpha: 0.9); // اللون البيج الحالي
        contentColor = kDeepGreen;
        toastIcon = icon ?? Icons.info_rounded;
    }

    final m = ScaffoldMessenger.maybeOf(context);
    m?.removeCurrentSnackBar(); 

    m?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(30, 0, 30, 45),
        animation: CurvedAnimation(
          parent: AnimationController(
            vsync: ScaffoldMessenger.of(context),
            duration: const Duration(seconds: 3),
          )..forward(),
          curve: Curves.easeOutBack,
        ),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: contentColor.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                textDirection: TextDirection.rtl, 
                children: [
                  Icon(toastIcon, color: contentColor, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      msg,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.almarai(
                        color: contentColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

Future<void> _loadUser() async {
    try {
      final u = _auth.currentUser;
      if (u == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final doc = await _db.collection('users').doc(u.uid).get();
      final data = doc.data() ?? {};

      // ✅ التعديل هنا: نعتمد فقط على Firestore
      // حذفنا u.photoURL لكي لا يظهر الرابط القديم المخزن في الجلسة
      final photo = (data['photoURL'] ?? '').toString(); 

      if (!mounted) return;
      setState(() {
        name = (data['name'] ?? '').toString();
        phone = (data['phone'] ?? '').toString();
        region = (data['region'] ?? '').toString();
        
        // إذا كان الحقل فارغاً في Firestore، سيكون avatarPath قيمته null 
        // وبالتالي سيختفي زر الحذف ويظهر لوغو سعف تلقائياً
        avatarPath = photo.isNotEmpty ? photo : null; 
        
        email = u.email;

        _nameCtrl.text = name ?? '';
        _phoneCtrl.text = phone ?? '';
        _emailCtrl.text = email ?? '';
        _selectedRegion = (region?.isNotEmpty ?? false) ? region : null;

        _loading = false;
      });
    } catch (e) {
      _safeToast("تعذر تحميل البيانات: $e", type: 'error');
      if (mounted) setState(() => _loading = false);
    }
  }

  // كسر الكاش + تضمين نسخة اختيارية
  String _bust(String url) {
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}rev=$_avatarRev';
  }
// ------------------ Luxury Background (مثل AboutUs) -----------------------
Widget _buildLuxBackground() {
  return Positioned.fill(
    child: Stack(
      children: [
        // Base gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Color(0xFF05352D),
                kDeepGreen,
                Color(0xFF031E1A),
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),

        // Radial glow (gold)
        Positioned(
          top: -120,
          right: -80,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  kGold.withValues(alpha: 0.25),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),

        // Radial glow (teal)
        Positioned(
          bottom: -140,
          left: -120,
          child: Container(
            width: 360,
            height: 360,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF0C6B5C).withValues(alpha: 0.18),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),

        // Subtle vignette
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.18),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.25),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
      ],
    ),
  );
}

// ------------------ Glass Card (مثل AboutUs) -----------------------
Widget _glassCard({
  required Widget child,
  EdgeInsets padding = const EdgeInsets.all(18),
  BorderRadius borderRadius = const BorderRadius.all(Radius.circular(22)),
}) {
  return ClipRRect(
    borderRadius: borderRadius,
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: borderRadius,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}
  // =========== صورة الأفاتار ===========
  static const bool _usePlainNetworkImage = false;

  Widget _avatarWidget() {
    if (_pickedBytes != null) {
      return ClipOval(
        child: Image.memory(
          _pickedBytes!,
          width: 120,
          height: 120,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _brokenImage(),
        ),
      );
    }
    if (!kIsWeb && _pickedFilePath != null) {
      return ClipOval(
        child: Image.file(
          File(_pickedFilePath!),
          width: 120,
          height: 120,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _brokenImage(),
        ),
      );
    }

    final url = avatarPath;
    if (url != null && url.startsWith('http')) {
      final busted = _bust(url);

      if (_usePlainNetworkImage) {
        return ClipOval(
          child: Image.network(
            busted,
            width: 120,
            height: 120,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _brokenImage(),
          ),
        );
      }

      return ClipOval(
        child: SizedBox(
          width: 120,
          height: 120,
          child: saafNetworkImage(
            busted,
            key: ValueKey('img-$busted'),
            width: 120,
            height: 120,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

// في نهاية دالة _avatarWidget
return const ClipOval(
  child: SizedBox(
    width: 120,
    height: 120,
    child: Image(
      image: AssetImage('assets/images/saaf_logo.png'), // ✅ تأكدي من المسار الصحيح لشعارك
      fit: BoxFit.cover,
    ),
  ),
);
  }

Widget _clickableAvatar() {
  // فحص هل توجد أي صورة حالياً
final bool hasImage = (avatarPath != null && avatarPath!.isNotEmpty) || 
                       _pickedBytes != null || 
                       _pickedFilePath != null;

  return Stack(
    alignment: Alignment.center,
    children: [
      // 1. الإطار (الهالة) - يظهر دائماً كما طلبتِ
      Container(
        width: 128,
        height: 128,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: kGold.withValues(alpha: 0.50), // ✅ الإطار الذهبي/البيج
            width: 2.5, // سماكة الإطار
          ),
        ),
      ),

      // 2. ويدجت الصورة (يعرض الصورة الشخصية أو شعار سعف)
      _avatarWidget(),

      // 3. زر الكاميرا (دائماً موجود)
      Positioned(
        bottom: 2,
        right: 2,
        child: GestureDetector(
          onTap: _pickFromGallery,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: kGold,
              shape: BoxShape.circle,
              border: Border.all(color: kDeepGreen, width: 2), // إطار صغير للزر
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
          ),
        ),
      ),

      // 4. زر الحذف - يظهر فقط في حالة وجود صورة شخصية مرفوعة
      if (hasImage)
        Positioned(
          top: 2,
          left: 2,
          child: GestureDetector(
            onTap: _removeAvatar,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
                border: Border.all(color: kDeepGreen, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.delete, size: 18, color: Colors.white),
            ),
          ),
        ),
    ],
  );
}



  Widget _brokenImage() => Container(
    width: 120,
    height: 120,
    color: Colors.white.withValues(alpha: 0.15),
    alignment: Alignment.center,
    child: const Icon(Icons.person, color: Colors.white70, size: 40),
  );

Future<void> _pickFromGallery() async {
  try {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (x == null) return;

    // 1. تحديث المعاينة فوراً للمستخدم
    if (kIsWeb) {
      _pickedBytes = await x.readAsBytes();
      _pickedFilePath = null;
    } else {
      _pickedFilePath = x.path;
      _pickedBytes = null;
    }
    setState(() {}); // لتحديث شكل الأفتار فوراً

    // 2. البدء بالرفع التلقائي وتحديث الداتا بيس
    final u = _auth.currentUser;
    if (u == null) return;

    _safeToast("جاري تحديث الصورة...", icon: Icons.sync_rounded, type: 'info');
    
    // استدعاء دالة الرفع التي عدلناها أعلاه
    final String? newUrl = await _uploadAvatar(u.uid);

    if (newUrl != null) {
      // ✅ تحديث Firestore فوراً دون انتظار زر الحفظ
      await _db.collection('users').doc(u.uid).update({
        'photoURL': newUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ✅ تحديث Firebase Auth لضمان ظهورها عند إعادة التشغيل
      await u.updatePhotoURL(newUrl);

      if (!mounted) return;
      setState(() {
        avatarPath = newUrl; // تأكيد الرابط الجديد
        _avatarRev++;        // كسر الكاش
      });
      
      _safeToast('تم حفظ الصورة بنجاح', type: 'success');
    }
  } catch (e) {
    _safeToast("خطأ أثناء اختيار أو رفع الصورة: $e", type: 'error');
  }
}

Future<void> _removeAvatar() async {
  final u = _auth.currentUser;
  if (u == null) return;

  try {
    // 1. حذف الملف من Storage إذا كان موجوداً
    if (avatarPath != null && avatarPath!.startsWith('http')) {
      try {
        await _storage.refFromURL(avatarPath!).delete();
      } catch (e) {
        debugPrint("Storage delete error: $e");
      }
    }

    // 2. تحديث Firestore (إزالة الحقل تماماً لضمان عدم تحميله مجدداً)
    await _db.collection('users').doc(u.uid).update({
      'photoURL': FieldValue.delete(), // ✅ يضمن حذف الحقل من المستند
    });

    // 3. تحديث Firebase Auth (هذا يمنع ظهور الصورة المكسورة عند إعادة التشغيل)
    await u.updatePhotoURL(null); // ✅ يصفر الرابط في سجل الجلسة
    await u.reload();            // ✅ إجبار تحديث بيانات المستخدم الحالية

    if (!mounted) return;

    setState(() {
      avatarPath = null;      // يختفي الرابط فتختفي أيقونة الزبالة
      _pickedBytes = null;    // يصفر أي اختيار محلي
      _pickedFilePath = null; // يصفر أي مسار محلي
      _avatarRev++;           // كسر الكاش لضمان تحديث الواجهة
    });

    _safeToast("تمت إزالة الصورة بنجاح", type: 'success');
  } catch (e) {
    _safeToast("تعذر حذف الصورة: $e", type: 'error');
  }
}


  Future<String?> _uploadAvatar(String uid) async {
    if (_pickedBytes == null && _pickedFilePath == null) return avatarPath;
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref().child('users/$uid/avatar_$ts.jpg');

      final meta = SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'no-store, no-cache, max-age=0, must-revalidate',
      );

      if (_pickedBytes != null) {
        await ref.putData(_pickedBytes!, meta);
      } else {
        await ref.putFile(File(_pickedFilePath!), meta);
      }

      final url = await ref.getDownloadURL();

      try {
        final bytes = await ref.getData(2 * 1024 * 1024);
        if (bytes != null && mounted) {
          setState(() {
            _pickedBytes = bytes;
            _pickedFilePath = null;
          });
        }
      } catch (_) {}

      return url;
    } catch (e) {
      _safeToast("تعذر رفع الصورة: $e", type: 'error');
      return null;
    }
  }

  // ===== AlertDialog ملوّن لتأكيد الهوية (كلمة المرور) =====
  Future<String?> _askForEmailPassword() async {
    final ctrl = TextEditingController();
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
  child: AlertDialog(
        backgroundColor: kDeepGreen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'تأكيد الهوية',
          textAlign: TextAlign.center,
          style: GoogleFonts.almarai(
            color: kAccent,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          style: GoogleFonts.almarai(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'كلمة المرور الحالية',
            labelStyle: GoogleFonts.almarai(color: Colors.white70),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
  borderRadius: const BorderRadius.all(Radius.circular(15.0)),
  borderSide: BorderSide(color: kGold.withValues(alpha: 0.25)),
),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(15.0)),
              borderSide: BorderSide(color: kAccent, width: 2),
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'إلغاء',
              style: GoogleFonts.almarai(
                color: const Color(0xFFAAAAAA),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: kDeepGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'تأكيد',
              style: GoogleFonts.almarai(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      ),
    ).then((ok) => ok == true ? ctrl.text.trim() : null);
  }

  Future<bool> _reauthWithPassword(String password) async {
    final u = _auth.currentUser!;
    try {
      final cred = EmailAuthProvider.credential(
        email: u.email!,
        password: password,
      );
      await u.reauthenticateWithCredential(cred);
      return true;
    } on FirebaseAuthException catch (e) {
      _safeToast("فشل تأكيد الهوية: ${e.message}", type: 'error');
      return false;
    } catch (e) {
      _safeToast("فشل تأكيد الهوية: $e", type: 'error');
      return false;
    }
  }

  Future<bool> _updateEmailFlow(String newEmail) async {
    final u = _auth.currentUser!;
    try {
      if (u.providerData.any((p) => p.providerId == 'password')) {
        final pwd = await _askForEmailPassword();
        if (pwd == null || pwd.isEmpty) return false;
        final ok = await _reauthWithPassword(pwd);
        if (!ok) return false;
      } else {
        _safeToast("حسابك ليس Email/Password. أعِد تسجيل الدخول بمزوّدك ثم حاول مجددًا", type: 'info');
        return false;
      }

      await u.verifyBeforeUpdateEmail(newEmail);
      await _db.collection('users').doc(u.uid).set({
        'pendingEmail': newEmail,
        'emailChangeRequestedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _safeToast("تم إرسال رابط تأكيد إلى البريد الجديد", type: 'success');
      return true;
    } on FirebaseAuthException catch (e) {
      String msg = e.message ?? e.code;
      if (e.code == 'email-already-in-use') msg = 'البريد مستخدم من قبل.';
      if (e.code == 'invalid-email') msg = 'بريد غير صالح.';
      if (e.code == 'requires-recent-login') {
        msg = 'يلزم تأكيد الهوية. أعِد تسجيل الدخول وحاول مجددًا.';
      }
      _safeToast(msg, type: 'error');
      return false;
    } catch (e) {
      _safeToast("تعذر بدء تغيير البريد: $e", type: 'error');
      return false;
    }
  }

  Future<void> _saveProfile() async {
    final navigator = Navigator.of(context);
    final u = _auth.currentUser;
    if (u == null) return;

    // ✅ أولاً: تحقق من الحقول في الـ Form
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    try {
      final newName = _nameCtrl.text.trim();
      final newPhone = _phoneCtrl.text.trim();
      final newRegion = _selectedRegion;
      final newEmail = _emailCtrl.text.trim();

      final emailChanged = newEmail.isNotEmpty && newEmail != (u.email ?? '');
      if (emailChanged) {
        final ok = await _updateEmailFlow(newEmail);
        if (!ok) {
          if (mounted) setState(() => _saving = false);
          return;
        }
      }
// داخل دالة _saveProfile
final newPhoto = await _uploadAvatar(u.uid);

await _db.collection('users').doc(u.uid).set({
  'name': newName,
  'phone': newPhone,
  'region': newRegion,
  'photoURL': newPhoto, // ✅ سيقوم بالتحديث دائماً حتى لو كانت القيمة null (عند الحذف)
  'updatedAt': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));

// تحديث الصورة في سجل Firebase Auth مباشرة
await u.updatePhotoURL(newPhoto); // ✅ تحديث مباشر بدون شرط

      if (!mounted) return;
      setState(() {
        name = newName;
        phone = newPhone;
        region = newRegion;
        avatarPath = newPhoto; // ✅ سيتحدث ليصبح null إذا حذفتِ الصورة
        _avatarRev++;
      });

      _safeToast("تم حفظ التعديلات", type: 'success');

      if (emailChanged) {
        await _auth.signOut();
        navigator.pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
    } catch (e) {
      _safeToast("خطأ أثناء الحفظ: $e", type: 'error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

// 1. دالة إظهار نافذة التأكيد
// 1. نافذة التحذير الأولى )
  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: kDeepGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
            side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 50),
              const SizedBox(height: 20),
              Text(
                'تأكيد حذف الحساب',
                style: GoogleFonts.almarai(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
              ),
              const SizedBox(height: 12),
              Text(
                'سيتم إزالة كافة البيانات المرتبطة بهذا الحساب بشكل نهائي من نظام سعف. \n\n هل ترغب في تأكيد الحذف ؟',
                textAlign: TextAlign.center,
                style: GoogleFonts.almarai(color: Colors.white.withValues(alpha: 0.9), fontSize: 14, height: 1.5),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          actions: [
            Row(
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _deleteAccountLogic(); // ننتقل للخطوة التالية
                  },
                  child: Text('تأكيد الحذف', style: GoogleFonts.almarai(fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إلغاء', style: GoogleFonts.almarai(color: Colors.white70)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }








  // 2. نافذة طلب كلمة المرور )
// 2. نافذة طلب كلمة المرور مع ميزة إظهار/إخفاء الباسوورد
Future<String?> _askForPassword() async {
  final ctrl = TextEditingController();
  final userEmail = _auth.currentUser?.email ?? "";
  String? localError;
  bool obscurePassword = true; // متغير للتحكم في ظهور النص

  return await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: const Color(0xFF0D2B24).withValues(alpha: 0.9), // زيادة التعتيم قليلاً للوضوح
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_person_rounded, color: Color(0xFFFDCB6E), size: 50),
              const SizedBox(height: 20),
              Text(
                'تأكيد الهوية',
                style: GoogleFonts.almarai(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
              ),
              const SizedBox(height: 12),
              Text(
                "يرجى إدخال كلمة المرور الخاصة بالحساب:\n($userEmail)\nلإتمام عملية الحذف.",
                textAlign: TextAlign.center,
                style: GoogleFonts.almarai(color: Colors.white.withValues(alpha: 0.9), fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                obscureText: obscurePassword, // الربط بالمتغير
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'كلمة المرور الحالية',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.2),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  
                  // --- إضافة أيقونة العين هنا ---
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: kGold.withValues(alpha: 0.7),
                    ),
                    onPressed: () {
                      setDialogState(() {
                        obscurePassword = !obscurePassword;
                      });
                    },
                  ),
                  // ---------------------------

                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: kAccent, width: 1.5),
                  ),
                ),
              ),

              if (localError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Text(
                    localError!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.almarai(
                      color: Colors.redAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent, 
                    foregroundColor: kDeepGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final password = ctrl.text.trim();
                    if (password.isEmpty) {
                      setDialogState(() => localError = "الرجاء إدخال كلمة المرور");
                      return;
                    }
                    try {
                      AuthCredential credential = EmailAuthProvider.credential(
                        email: userEmail,
                        password: password,
                      );
                      await _auth.currentUser!.reauthenticateWithCredential(credential);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx, password);
                    } on FirebaseAuthException catch (e) {
                      setDialogState(() {
                        if (e.code == 'wrong-password') {
                          localError = "كلمة المرور غير صحيحة";
                        } else {
                          localError = "حدث خطأ، تأكد من البيانات";
                        }
                      });
                    }
                  },
                  child: const Text('تأكيد'),
                ),
                const SizedBox(width: 20),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('إلغاء', style: GoogleFonts.almarai(color: Colors.white70)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}










  // 3. المنطق البرمجي للحذف النهائي
Future<void> _deleteAccountLogic() async {
  final navigator = Navigator.of(context);
  final pwd = await _askForPassword();
  if (!mounted) return;

  if (pwd == null || pwd.isEmpty) return;

  setState(() => _saving = true);
  try {
    final u = _auth.currentUser;
    if (u == null) return;

    final uid = u.uid;

    // حذف المزارع
    final farmsQuery = await _db.collection('farms').where('createdBy', isEqualTo: uid).get();
    for (var doc in farmsQuery.docs) {
      await doc.reference.delete();
    }

    // حذف البروفايل
    await _db.collection('users').doc(uid).delete();

    // حذف الحساب نهائي
    await u.delete();

   _safeToast("تم حذف الحساب وكافة البيانات بنجاح", type: 'success');

    if (mounted) {
      navigator.pushNamedAndRemoveUntil('/login', (route) => false);

    }
  } catch (e) {
    _safeToast("حدث خطأ غير متوقع أثناء الحذف النهائي", type: 'error');
  } finally {
    if (mounted) setState(() => _saving = false);
  }
}

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kDeepGreen,
        body: Center(child: CircularProgressIndicator(color: kGold)),
      );
    }

    return Scaffold(
  extendBody: true,
  extendBodyBehindAppBar: true,
  backgroundColor: Colors.transparent,
      appBar: AppBar(
  backgroundColor: Colors.transparent,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  centerTitle: true,
  automaticallyImplyLeading: false,

        // زر الرجوع الدائري
        leading: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: Material(
            color: Colors.white.withValues(alpha: 0.08),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/main', (route) => false),
              child: const Padding(
                padding: EdgeInsets.only(right: 7, left: 14),
                child: Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          ),
        ),

        title: Text('الملف الشخصي', style: saafPageTitle),


        actions: [
          IconButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await _auth.signOut();
              navigator.pushNamedAndRemoveUntil('/login', (_) => false);
            },
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            tooltip: 'تسجيل الخروج',
          ),
          const SizedBox(width: 8),
        ],
      ),

    body: Stack(
  children: [
    _buildLuxBackground(),
    SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 190),
        child: SingleChildScrollView(
          child: _glassCard(
            padding: const EdgeInsets.all(20),
            borderRadius: const BorderRadius.all(Radius.circular(25)),
            child: Form(
              // ✅ لفّينا الـ Column بـ Form
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: _clickableAvatar(),
                    ),
                  ),
                  const SizedBox(height: 24),

 
                  const SizedBox(height: 24),

                  _buildField(
                    controller: _nameCtrl,
                    label: 'الاسم الكامل',
                    icon: Icons.person,
                    editing: _editName,
                    onToggle: () => setState(() => _editName = !_editName),
                    validator: (value) {
                      final v = value?.trim() ?? '';
                      if (v.isEmpty) {
                        return 'الرجاء إدخال الاسم';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  _buildField(
                    controller: _phoneCtrl,
                    label: 'رقم الجوال',
                    icon: Icons.phone,
                    editing: _editPhone,
                    onToggle: () => setState(() => _editPhone = !_editPhone),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: (value) {
                      final p = value?.trim() ?? '';
                      if (p.isEmpty) {
                        return 'الرجاء إدخال رقم الجوال';
                      }
                      if (!RegExp(r'^05\d{8}$').hasMatch(p)) {
                        return 'رجاءً أدخل الرقم بصيغة 05XXXXXXXX';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  _buildField(
                    controller: _emailCtrl,
                    label: 'البريد الإلكتروني',
                    icon: Icons.email,
                    editing: _editEmail,
                    onToggle: () => setState(() => _editEmail = !_editEmail),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    initialValue: _selectedRegion,
                    decoration: InputDecoration(
                      labelText: 'المنطقة',
                      labelStyle: GoogleFonts.almarai(color: Colors.white70),
                      prefixIcon: const Icon(Icons.location_on, color: kAccent),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
  borderRadius: const BorderRadius.all(Radius.circular(15.0)),
  borderSide: BorderSide(color: kGold.withValues(alpha: 0.25)),
),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(15.0)),
                        borderSide: BorderSide(color: kAccent, width: 2),
                      ),
                    ),

                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'الرجاء اختيار المنطقة';
                      }
                      return null;
                    },
                    dropdownColor: kDeepGreen,
                    style: GoogleFonts.almarai(color: Colors.white),
                    isExpanded: true,
                    hint: Text(
                      'اختر منطقة',
                      style: GoogleFonts.almarai(color: Colors.white54),
                    ),
                    onChanged: (val) => setState(() => _selectedRegion = val),
                    items: _regions
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                  ),

                  const SizedBox(height: 28),

                  SizedBox(
                    height: 54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [kGold, kBeige]),
                        borderRadius: BorderRadius.circular(35),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(35),
                          onTap: _saving ? null : _saveProfile,
                          child: Center(
                            child: Text(
                              _saving ? '...جاري الحفظ' : 'حفظ التعديلات',
                              style: GoogleFonts.almarai(
                                color: kDeepGreen,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                      TextButton.icon(
                             onPressed: _saving ? null : _showDeleteConfirmation,
                              icon: const Icon(
                                 Icons.delete_forever,
                                 color: Colors.redAccent,
                                ),
                      label: Text(
                               'حذف الحساب',
                                style: GoogleFonts.almarai(
                                 color: Colors.redAccent,
                                fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                   ),
                  ),
                 ),
                ],
              ),
            ),
          ),
        ),
      ),
     ),
  ],
  ),    
      
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool editing,
    required VoidCallback onToggle,
    String? Function(String?)? validator, // ✅ إضافة
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      // ✅ بدل TextField
      controller: controller,
      readOnly: !editing,
      cursorColor: kGold,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: GoogleFonts.almarai(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.almarai(color: Colors.white70),
        prefixIcon: Icon(icon, color: kGold),
        suffixIcon: IconButton(
          tooltip: editing ? 'إقفال الحقل' : 'تعديل',
          onPressed: onToggle,
          icon: Icon(
            editing ? Icons.check_rounded : Icons.edit_rounded,
            color: editing ? Colors.greenAccent : Colors.white70,
          ),
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
  borderRadius: const BorderRadius.all(Radius.circular(15.0)),
  borderSide: BorderSide(color: kGold.withValues(alpha: 0.25)),
),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(15.0)),
          borderSide: BorderSide(color: kAccent, width: 2),
        ),
      ),
    );
  }
}
