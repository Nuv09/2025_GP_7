import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui' show ImageFilter;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const Color kDeepGreen = Color(0xFF042C25);
const Color kLightBeige = Color(0xFFFFF6E0);
const Color kOrange = Color(0xFFEBB974);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // الحد الأقصى للمحاولات الفاشلة قبل الحظر الإجباري
  static const int _maxFailedAttempts = 10;

  static const String _securityCollection = 'security_states';

  bool _didCheckArguments = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_didCheckArguments) {
      _didCheckArguments = true;

      final args = ModalRoute.of(context)?.settings.arguments;

      if (args != null && args is Map && args['session_expired'] == true) {
        final message = args['message'] as String;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showSnack(ScaffoldMessenger.of(context), message);
        });
      }
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

void _showSnack(
    ScaffoldMessengerState messenger,
    String msg, {
    bool isError = true,
  }) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          msg, 
          style: GoogleFonts.almarai(
            color: Colors.white, 

          ),
        ),
        backgroundColor: isError ? Colors.red.shade700 : kDeepGreen,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  //  دالة لإعادة تعيين عداد المحاولات الفاشلة في Firestore
  Future<void> _resetFailedAttempts(String email) async {
    final docRef = _db.collection(_securityCollection).doc(email.toLowerCase());
    try {
      await docRef.set({
        'failedAttempts': 0,
        'isLocked': false,
      }, SetOptions(merge: true));
    } catch (e) {

      debugPrint('Firestore Error during reset: $e');
    }
  }

  //  دالة لتحديث حالة الحظر والعد في Firestore
  Future<void> _updateSecurityState(
    String email, {
    bool success = false,
  }) async {
    final docRef = _db.collection(_securityCollection).doc(email.toLowerCase());

    if (success) {
      await _resetFailedAttempts(email);
    } else {

      try {
        await _db.runTransaction((transaction) async {
          final docSnapshot = await transaction.get(docRef);
          int currentAttempts = 0;

          if (docSnapshot.exists) {
            currentAttempts = docSnapshot.data()?['failedAttempts'] ?? 0;
          }

          currentAttempts += 1;
          bool isLocked = currentAttempts >= _maxFailedAttempts;

          transaction.set(docRef, {
            'failedAttempts': currentAttempts,
            'isLocked': isLocked,
            'lastAttempt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        });


        try {
          final snapshot = await _db
              .collection(_securityCollection)
              .doc(email.toLowerCase())
              .get();

          if ((snapshot.data()?['isLocked'] ?? false) == true) {
            await _auth.sendPasswordResetEmail(email: email);
            debugPrint("🔒 Password reset email sent automatically after lockout.");
          }
        } catch (e) {
          debugPrint("Error sending auto-reset email: $e");
        }

      } catch (e) {
        debugPrint('Firestore Error during update: $e');
      }
    }
  }

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final messenger = ScaffoldMessenger.of(context);

    if (email.isEmpty || pass.isEmpty) {
      _showSnack(messenger, 'رجاءً اكتب البريد وكلمة المرور');
      return;
    }

    setState(() => _loading = true);


    try {
      final docSnapshot = await _db
          .collection(_securityCollection)
          .doc(email.toLowerCase())
          .get();
      if (docSnapshot.exists && (docSnapshot.data()?['isLocked'] ?? false)) {
        // إذا كان الحساب محظورًا، نمنع محاولة الدخول
        _showSnack(
          messenger,
          'لقد تجاوزت الحد المسموح لمحاولات تسجيل الدخول.\n'
          'تم إرسال رابط إعادة تعيين كلمة المرور إلى بريدك الإلكتروني.\n'
          'يرجى تغيير كلمة المرور ثم إعادة المحاولة.',
          isError: true,
        );
        if (mounted) setState(() => _loading = false);
        return;
      }
    } catch (_) {

      debugPrint('Warning: Failed to check Firestore lock status.');
    }

    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );


      await _updateSecurityState(email, success: true);

      // منطق فحص التحقق من البريد
      await cred.user?.reload();
      final user = _auth.currentUser;

      if (!mounted) return;

      if (user != null && !user.emailVerified) {
        await _auth.signOut();
        if (!mounted) return;
        _showVerificationErrorDialog(messenger);
        return;
      }

      Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
    } on FirebaseAuthException catch (e) {

      if (e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'INVALID_LOGIN_CREDENTIALS') {
        await _updateSecurityState(email, success: false);
      }

      String msg = '';

      switch (e.code) {
        case 'user-not-found':
          msg =
              'البريد الإلكتروني الذي أدخلته غير مسجّل. تأكدي من كتابته بشكل صحيح أو أنشئي حسابًا جديدًا.';
          break;

        case 'wrong-password':
        case 'invalid-credential':
        case 'INVALID_LOGIN_CREDENTIALS':
          msg = 'خطأ في كلمة المرور أو اسم المستخدم.';
          break;

        case 'invalid-email':
          msg =
              'صيغة البريد الإلكتروني غير صحيحة. تأكدي أن البريد مكتوب بهذا الشكل: example@email.com';
          break;

        case 'too-many-requests': 
          msg =
              'تم حظر تسجيل الدخول مؤقتًا بسبب محاولات كثيرة. انتظري قليلاً ثم جربي مجددًا.';
          break;

        default:
          msg =
              'حدث خطأ أثناء تسجيل الدخول. يرجى المحاولة لاحقًا. (كود: ${e.code})';
      }


      _showSnack(messenger, msg, isError: true);
    } catch (_) {
      _showSnack(messenger, 'حدث خطأ غير متوقع');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // دالة لإعادة إرسال بريد التحقق
  Future<void> _resendVerificationEmail(
    ScaffoldMessengerState messenger,
  ) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null || _loading) return;

    setState(() => _loading = true);
    try {
      await user.sendEmailVerification();
      _showSnack(
        messenger,
        'تم إرسال رابط تحقق جديد إلى بريدك.',
        isError: false,
      );
    } catch (_) {
      _showSnack(messenger, 'تعذر إرسال رابط التحقق، يرجى المحاولة لاحقاً.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // دالة لعرض النافذة المنبثقة للخطأ
  void _showVerificationErrorDialog(ScaffoldMessengerState messenger) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: kLightBeige,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'الحساب غير موثَّق',
            style: GoogleFonts.almarai(
              color: kDeepGreen,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
          content: Text(
            'يرجى التحقق من بريدك الإلكتروني والنقر على رابط التفعيل. (تأكد من مجلد الرسائل غير المرغوب فيها)',
            style: GoogleFonts.almarai(color: kDeepGreen),
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _resendVerificationEmail(messenger);
              },
              child: Text(
                'إعادة إرسال رابط التحقق',
                style: GoogleFonts.almarai(color: kOrange),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text(
                'حسناً',
                style: GoogleFonts.almarai(color: kDeepGreen),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendResetEmail() async {
    final email = _emailCtrl.text.trim();
    final messenger = ScaffoldMessenger.of(context);

    if (email.isEmpty) {
      _showSnack(messenger, 'اكتب بريدك أولاً');
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: email);

      await _resetFailedAttempts(email);

      _showSnack(
        messenger,
        'تم إرسال رابط إعادة التعيين إلى بريدك',
        isError: false,
      );
    } catch (_) {
      _showSnack(messenger, 'تعذر إرسال الرابط، تحقق من البريد');
    }
  }

  // دالة لتصميم الدائرة الخلفية
  Widget _softCircle(double size, {double opacity = 0.18}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.fromRGBO(255, 246, 224, opacity),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: GoogleFonts.almaraiTextTheme(Theme.of(context).textTheme),
        ),
      
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/landing', (route) => false);
          },
          child: Scaffold(
            backgroundColor: kDeepGreen,
            body: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/palms.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color.fromRGBO(4, 44, 37, 0.7),
                        const Color.fromRGBO(4, 44, 37, 0.95),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: -media.width * 0.2,
                  bottom: -media.width * 0.15,
                  child: _softCircle(media.width * 0.7),
                ),
                Positioned(
                  left: media.width * 0.15,
                  bottom: -media.width * 0.25,
                  child: _softCircle(media.width * 0.9, opacity: 0.25),
                ),
                SafeArea(
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
                        child: Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  22,
                                  18,
                                  16,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color.fromRGBO(
                                    255,
                                    255,
                                    255,
                                    0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: const Color.fromRGBO(
                                      255,
                                      255,
                                      255,
                                      0.15,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'مرحبًا بعودتك!',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.almarai(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w700,
                                        color: kLightBeige,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'سجّل الدخول إلى حسابك',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.almarai(
                                        fontSize: 18,
                                        color: const Color.fromRGBO(
                                          255,
                                          246,
                                          224,
                                          0.85,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    _SaafField(
                                      controller: _emailCtrl,
                                      hint: 'البريد الإلكتروني',
                                      icon: Icons.person_outline,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                    ),
                                    const SizedBox(height: 12),
                                    _SaafField(
                                      controller: _passCtrl,
                                      hint: 'كلمة المرور',
                                      icon: Icons.lock_outline,
                                      isPassword: true,
                                      obscure: _obscure,
                                      onToggleObscure: () =>
                                          setState(() => _obscure = !_obscure),
                                      textInputAction: TextInputAction.done,
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        TextButton(
                                          onPressed: _sendResetEmail,
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                const Color.fromRGBO(
                                                  255,
                                                  246,
                                                  224,
                                                  0.9,
                                                ),
                                          ),
                                          child: Text(
                                            'هل نسيت كلمة المرور؟',
                                            style: GoogleFonts.almarai(),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 18),
                                    _SaafButton(
                                      label: _loading
                                          ? '...جاري الدخول'
                                          : 'تسجيل الدخول',
                                      onTap: _loading ? () {} : _signIn,
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'لا تملك حسابًا؟ ',
                                          style: GoogleFonts.almarai(
                                            color: const Color.fromRGBO(
                                              255,
                                              246,
                                              224,
                                              0.85,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pushNamed(
                                            context,
                                            '/signup',
                                          ),
                                          style: TextButton.styleFrom(
                                            foregroundColor: kOrange,
                                          ),
                                          child: Text(
                                            'أنشئ حسابًا',
                                            style: GoogleFonts.almarai(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Material(
                          color: Colors.black45,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () =>
                                Navigator.of(context).pushNamedAndRemoveUntil(
                                  '/landing',
                                  (route) => false,
                                ),
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaafField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool isPassword;
  final bool obscure;
  final VoidCallback? onToggleObscure;

  const _SaafField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.isPassword = false,
    this.obscure = false,
    this.onToggleObscure,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: isPassword ? obscure : false,
      style: GoogleFonts.almarai(color: kDeepGreen),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.almarai(
          color: const Color.fromRGBO(4, 44, 37, 0.6),
        ),
        filled: true,
        fillColor: const Color.fromRGBO(255, 255, 255, 0.92),
        prefixIcon: Icon(icon, color: kDeepGreen),
        suffixIcon: isPassword
            ? IconButton(
                onPressed: onToggleObscure,
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: const Color.fromRGBO(4, 44, 37, 0.8),
                ),
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color.fromRGBO(255, 255, 255, 0.25),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color.fromRGBO(255, 255, 255, 0.20),
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: kDeepGreen, width: 1.2),
        ),
      ),
    );
  }
}

class _SaafButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SaafButton({required this.label, required this.onTap});

  static const Color _kOrange = kOrange;
  static const Color _kLightBeige = kLightBeige;
  static const Color _kDeepGreen = kDeepGreen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_kOrange, _kLightBeige]),
          borderRadius: BorderRadius.circular(35),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.almarai(
                  color: _kDeepGreen,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
