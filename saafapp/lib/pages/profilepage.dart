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

  // 🔔 Toast آمن
  void _safeToast(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    m?.showSnackBar(SnackBar(content: Text(msg, style: GoogleFonts.almarai())));
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

      final photo =
          (data['photoURL'] ??
                  data['photoUrl'] ??
                  data['avatar'] ??
                  u.photoURL ??
                  '')
              .toString();

      if (!mounted) return;
      setState(() {
        name = (data['name'] ?? '').toString();
        phone = (data['phone'] ?? '').toString();
        region = (data['region'] ?? '').toString();
        avatarPath = photo.isNotEmpty ? photo : null;
        email = u.email;

        _nameCtrl.text = name ?? '';
        _phoneCtrl.text = phone ?? '';
        _emailCtrl.text = email ?? '';
        _selectedRegion = (region?.isNotEmpty ?? false) ? region : null;

        _loading = false;
      });
    } catch (e) {
      _safeToast('تعذر تحميل البيانات: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // كسر الكاش + تضمين نسخة اختيارية
  String _bust(String url) {
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}rev=$_avatarRev';
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

    return const ClipOval(
      child: SizedBox(
        width: 120,
        height: 120,
        child: Image(
          image: AssetImage('assets/images/saaf_logo.png'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

Widget _clickableAvatar() {
  final avatar = _avatarWidget();

  return Stack(
    alignment: Alignment.center,
    children: [
      // الهالة الذهبية
      Container(
        width: 128,
        height: 128,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: kGold.withValues(alpha: 0.30),
            width: 3,
          ),
        ),
      ),

      // الصورة
      avatar,

      // زر استبدال الصورة (الكاميرا)
      Positioned(
        bottom: 4,
        right: 4,
        child: GestureDetector(
          onTap: _pickFromGallery,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kGold,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                ),
              ],
            ),
            child: const Icon(Icons.camera_alt_rounded,
                color: Colors.white, size: 20),
          ),
        ),
      ),

      // زر الحذف ❌ يظهر فقط لو فيه صورة مرفوعة
      if (avatarPath != null || _pickedBytes != null || _pickedFilePath != null)
        Positioned(
          top: 4,
          left: 4,
          child: GestureDetector(
            onTap: _removeAvatar,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
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
        maxWidth: 1024,
      );
      if (x == null) return;

      if (kIsWeb) {
        final bytes = await x.readAsBytes();
        if (!mounted) return;
        setState(() {
          _pickedBytes = bytes;
          _pickedFilePath = null;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _pickedFilePath = x.path;
          _pickedBytes = null;
        });
      }
    } catch (e) {
      _safeToast('خطأ أثناء اختيار الصورة: $e');
    }
  }

  Future<void> _removeAvatar() async {
  final u = _auth.currentUser;
  if (u == null) return;

  try {
    // لو في صورة قديمة من Firebase نحذفها
    if (avatarPath != null && avatarPath!.startsWith('http')) {
      try {
        await _storage.refFromURL(avatarPath!).delete();
      } catch (_) {}
    }

    // تحديث Firestore
    await _db.collection('users').doc(u.uid).set({
      'photoURL': null,
      'photoUrl': null,
      'avatar': null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // تحديث Firebase Auth
    await u.updatePhotoURL(null);

    if (!mounted) return;

    setState(() {
      avatarPath = null;
      _pickedBytes = null;
      _pickedFilePath = null;
      _avatarRev++;
    });

    _safeToast("تمت إزالة الصورة بنجاح");
  } catch (e) {
    _safeToast("تعذر حذف الصورة: $e");
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
      _safeToast('تعذر رفع الصورة: $e');
      return null;
    }
  }

  // ===== AlertDialog ملوّن لتأكيد الهوية (كلمة المرور) =====
  Future<String?> _askForEmailPassword() async {
    final ctrl = TextEditingController();
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
            fillColor: const Color.fromARGB(25, 255, 255, 255),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(15.0)),
              borderSide: BorderSide(color: Color.fromARGB(76, 253, 203, 110)),
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
      _safeToast('فشل تأكيد الهوية: ${e.message}');
      return false;
    } catch (e) {
      _safeToast('فشل تأكيد الهوية: $e');
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
        _safeToast(
          'حسابك ليس Email/Password. أعِد تسجيل الدخول بمزوّدك ثم حاول مجددًا.',
        );
        return false;
      }

      await u.verifyBeforeUpdateEmail(newEmail);
      await _db.collection('users').doc(u.uid).set({
        'pendingEmail': newEmail,
        'emailChangeRequestedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _safeToast('تم إرسال رابط تأكيد إلى البريد الجديد.');
      return true;
    } on FirebaseAuthException catch (e) {
      String msg = e.message ?? e.code;
      if (e.code == 'email-already-in-use') msg = 'البريد مستخدم من قبل.';
      if (e.code == 'invalid-email') msg = 'بريد غير صالح.';
      if (e.code == 'requires-recent-login') {
        msg = 'يلزم تأكيد الهوية. أعِد تسجيل الدخول وحاول مجددًا.';
      }
      _safeToast(msg);
      return false;
    } catch (e) {
      _safeToast('تعذر بدء تغيير البريد: $e');
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

      final newPhoto = await _uploadAvatar(u.uid);

      await _db.collection('users').doc(u.uid).set({
        'name': newName,
        'phone': newPhone,
        'region': newRegion,
        if (newPhoto != null) ...{'photoURL': newPhoto, 'photoUrl': newPhoto},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (u.displayName != newName) await u.updateDisplayName(newName);
      if (newPhoto != null) await u.updatePhotoURL(newPhoto);

      if (!mounted) return;
      setState(() {
        name = newName;
        phone = newPhone;
        region = newRegion;
        if (newPhoto != null) {
          avatarPath = newPhoto;
          _avatarRev++;
        }
      });

      _safeToast('تم حفظ التعديلات ✅');

      if (emailChanged) {
        await _auth.signOut();
        navigator.pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
    } catch (e) {
      _safeToast('خطأ أثناء الحفظ: $e');
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
          backgroundColor: const Color(0xFF0D2B24).withValues(alpha: 0.4),
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
Future<String?> _askForPassword() async {
  final ctrl = TextEditingController();
  final userEmail = _auth.currentUser?.email ?? "";
  String? localError;

  return await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: const Color(0xFF0D2B24).withValues(alpha: 0.2),
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
                obscureText: true,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'كلمة المرور الحالية',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.2),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: kAccent, width: 1.5),
                  ),
                ),
              ),

              // 🔴 رسالة الخطأ داخل النافذة
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
                  style: ElevatedButton.styleFrom(backgroundColor: kAccent, foregroundColor: kDeepGreen),
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

                      Navigator.pop(ctx, password); // نجاح
                    } on FirebaseAuthException catch (e) {
                      setDialogState(() {
                        if (e.code == 'wrong-password') {
                          localError = "كلمة المرور غير صحيحة";
                        } else if (e.code == 'network-request-failed') {
                          localError = "تأكد من اتصالك بالإنترنت";
                        } else {
                          localError = "حدث خطأ أمني، حاول مجدداً";
                        }
                      });
                    }
                  },
                  child: const Text('تأكيد'),
                ),
                const SizedBox(width: 20),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
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

    _safeToast('تم حذف الحساب وكافة البيانات بنجاح');

    if (mounted) {
      navigator.pushNamedAndRemoveUntil('/login', (route) => false);

    }
  } catch (e) {
    _safeToast('حدث خطأ غير متوقع أثناء الحذف النهائي');
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
      backgroundColor: kDeepGreen,
      appBar: AppBar(
        backgroundColor: kDeepGreen,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,

        // زر الرجوع الدائري
        leading: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: Material(
            color: Colors.black45,
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

      body: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color.fromARGB(25, 255, 255, 255),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: const Color.fromARGB(51, 255, 255, 255),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromARGB(51, 0, 0, 0),
                  blurRadius: 15,
                  offset: Offset(0, 10),
                ),
              ],
            ),
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
                      fillColor: const Color.fromARGB(25, 255, 255, 255),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(15.0)),
                        borderSide: BorderSide(
                          color: Color.fromARGB(76, 253, 203, 110),
                        ),
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
                        borderRadius: BorderRadius.circular(15),
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
                          borderRadius: BorderRadius.circular(15),
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
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: GoogleFonts.almarai(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.almarai(color: Colors.white70),
        prefixIcon: Icon(icon, color: kAccent),
        suffixIcon: IconButton(
          tooltip: editing ? 'إقفال الحقل' : 'تعديل',
          onPressed: onToggle,
          icon: Icon(
            editing ? Icons.check_rounded : Icons.edit_rounded,
            color: editing ? Colors.greenAccent : Colors.white70,
          ),
        ),
        filled: true,
        fillColor: const Color.fromARGB(25, 255, 255, 255),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(15.0)),
          borderSide: BorderSide(color: Color.fromARGB(76, 253, 203, 110)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(15.0)),
          borderSide: BorderSide(color: kAccent, width: 2),
        ),
      ),
    );
  }
}
