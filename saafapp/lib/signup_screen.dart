import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zxcvbn/zxcvbn.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:ui';

// الثوابت
const Color kDeepGreen = Color(0xFF042C25);
const Color kLightBeige = Color(0xFFFFF6E0);
const Color kOrange = Color(0xFFEBB974);

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  static const routeName = '/signup';

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  // 💡 متغيرات zxcvbn
  final _zxcvbn = Zxcvbn();
  int _passwordScore = 0; // 0 (ضعيف جداً) إلى 4 (قوي جداً)
  String? _passwordWarning; // رسالة التحذير من zxcvbn

  // ⭐️ التعديل 1: حالة الموافقة على الشروط
  bool _agreeTerms = false;

  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // الحد الأدنى المقبول لتقييم كلمة المرور
  static const int _minAcceptableScore = 2; // متوسطة أو أعلى

  @override
  void initState() {
    super.initState();
    // 💡 إضافة مستمع لتحديث تقييم قوة كلمة المرور فوراً
    _passCtrl.addListener(_updatePasswordStrength);
  }

  @override
  void dispose() {
    // 💡 إزالة المستمع قبل التخلص من الـ Widget
    _passCtrl.removeListener(_updatePasswordStrength);
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _safeToast(String msg, {IconData? icon, String type = 'info'}) {
    if (!mounted) return;
    
    Color bgColor;
    Color contentColor = const Color(0xFF042C25); // kDeepGreen
    IconData toastIcon;

    switch (type) {
      case 'success':
        bgColor = const Color(0xFF1E8D5F).withValues(alpha: 0.7); // الأخضر
        contentColor = Colors.white;
        toastIcon = icon ?? Icons.check_circle_rounded;
        break;
      case 'error':
        bgColor = const Color.fromARGB(255, 153, 30, 30).withValues(alpha: 0.7); // العنابي
        contentColor = Colors.white;
        toastIcon = icon ?? Icons.error_rounded;
        break;
      default:
        bgColor = const Color(0xFFFFF6E0); // kLightBeige
        contentColor = const Color(0xFF042C25);
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
                  Icon(toastIcon, color: contentColor, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      msg,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.almarai(
                        color: contentColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
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

  void _showTermsDialog() {
    const String termsContent =
        'يقتصر استخدامك لسعف على إدارة مزارع النخيل الخاصة بك ومتابعة حالتها، ويُمنع استخدامه لأي أغراض أخرى غير مصرح بها.\n\n'
        'يتم استخدام بياناتك الشخصية، مثل البريد الإلكتروني، فقط لغرض التسجيل والتواصل المتعلق بخدمات النظام.\n\n'
        'قد يتم استخدام بيانات المزرعة — بما في ذلك الموقع، حالة النخيل، وصور الأقمار الصناعية — لأغراض تحليلية وتطوير دقة النموذج، وذلك دون أي ربط بهويتك الشخصية.\n\n'
        'يُحظر مشاركة حسابك أو بيانات الدخول مع أي أطراف أخرى بهدف حماية أمن معلوماتك.\n\n'
        'قد نقوم بتحديث هذه الشروط في المستقبل، وسيتم إخطارك في حال حدوث تغييرات جوهرية.\n\n'
        'بالنقر على "أوافق"، فإنك تقر بأنك قرأت هذه الشروط وفهمتها ووافقت عليها.';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: kLightBeige,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'شروط استخدام سعف',
            style: GoogleFonts.almarai(
              color: kDeepGreen,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
          content: SingleChildScrollView(
            child: Text(
              termsContent,
              style: GoogleFonts.almarai(color: kDeepGreen, fontSize: 14),
              textAlign: TextAlign.right,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('إغلاق', style: GoogleFonts.almarai(color: kOrange)),
            ),
          ],
        );
      },
    );
  }

  // دالة لتقييم قوة كلمة المرور وتحديث الحالة
  void _updatePasswordStrength() {
    final password = _passCtrl.text;
    if (password.isEmpty) {
      setState(() {
        _passwordScore = 0;
        _passwordWarning = null;
      });
      return;
    }

    final userInputs = [_nameCtrl.text.trim(), _emailCtrl.text.trim()];
    final result = _zxcvbn.evaluate(password, userInputs: userInputs);

    setState(() {
      _passwordScore = (result.score ?? 0)
          .toInt(); 
      _passwordWarning = result.feedback.warning;
    });
  }

  Future<void> _signUp() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final p1 = _passCtrl.text;
    final p2 = _confirmCtrl.text;

    if (name.isEmpty || email.isEmpty || p1.isEmpty || p2.isEmpty) {
      _safeToast("يرجى ملء جميع الحقول", type: 'error');
      return;
    }
    if (!_agreeTerms) {
      _safeToast("يرجى الموافقة على الشروط والأحكام", type: 'error');
      return;
    }
    _updatePasswordStrength();

    if (_passwordScore < _minAcceptableScore) {
      _safeToast("كلمة المرور ضعيفة جداً، يرجى اختيار كلمة أقوى", type: 'error');
      return;
    }

    if (p1 != p2) {
      _safeToast("كلمتا المرور غير متطابقتين", type: 'error');
      return;
    }

    setState(() => _loading = true);
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: p1,
      );

      if (!mounted) return;
      await cred.user?.reload();
      await cred.user?.sendEmailVerification();
      // ignore: avoid_print
      print("📧 تم إرسال بريد تحقق إلى ${cred.user?.email}");

      await cred.user?.updateDisplayName(name);

      if (!mounted) return;

      final uid = cred.user!.uid;
      final userDoc = _db.collection('users').doc(uid);

      await userDoc.set({
        'uid': uid,
        'name': name,
        'email': email,
        'phone': '',
        'region': '',
        'photoURL': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'termsAccepted': true,
      }, SetOptions(merge: true));

try {
  
  final token = await FirebaseMessaging.instance.getToken();
  if (token != null && token.isNotEmpty) {
    await userDoc.set({
      'fcmToken': token,
      'fcmUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
} catch (e) {
  debugPrint("⚠️ Failed to save FCM token on signup: $e");
}

      if (!mounted) return;

      _safeToast("تم إنشاء الحساب بنجاح! ضلاً تحقق من بريدك الإلكتروني لإكمال التفعيل", type: 'success');

      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String msg = 'تعذر إنشاء الحساب';
      switch (e.code) {
        case 'email-already-in-use':
          msg = 'هذا البريد مستخدم بالفعل';
          break;
        case 'invalid-email':
          msg = 'بريد إلكتروني غير صالح';
          break;
        case 'weak-password':
          msg = 'كلمة المرور ضعيفة';
          break;
        case 'operation-not-allowed':
          msg = 'طريقة التسجيل غير مفعّلة في Firebase';
          break;
      }

      _safeToast(msg, type: 'error');
    } catch (e) {
      if (!mounted) return;
      _safeToast("حدث خطأ غير متوقع، حاول مجدداً", type: 'error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _getScoreColor(int score) {
    switch (score) {
      case 0:
        return Colors.red.shade300;
      case 1:
        return Colors.orange.shade300;
      case 2:
        return Colors.yellow.shade600;
      case 3:
        return Colors.lightGreen;
      case 4:
        return Colors.green.shade600;
      default:
        return Colors.transparent;
    }
  }

  String _getScoreText(int score) {
    switch (score) {
      case 0:
        return _passCtrl.text.isEmpty ? '' : 'ضعيفة جداً';
      case 1:
        return 'ضعيفة';
      case 2:
        return 'متوسطة';
      case 3:
        return 'جيدة';
      case 4:
        return 'قوية جداً';
      default:
        return '';
    }
  }

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
        child: Scaffold(
          resizeToAvoidBottomInset: true,
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
                            filter: const ColorFilter.mode(
                              Colors.black12,
                              BlendMode.srcOver,
                            ),
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
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'إنشاء حساب جديد',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.almarai(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      color: kLightBeige,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'أدخل بياناتك لإتمام التسجيل',
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
                                    controller: _nameCtrl,
                                    hint: 'الاسم',
                                    icon: Icons.person_outline,
                                    keyboardType: TextInputType.name,
                                    textInputAction: TextInputAction.next,
                                  ),
                                  const SizedBox(height: 12),
                                  _SaafField(
                                    controller: _emailCtrl,
                                    hint: 'البريد الإلكتروني',
                                    icon: Icons.email_outlined,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                  ),
                                  const SizedBox(height: 12),
                                  _SaafField(
                                    controller: _passCtrl,
                                    hint: 'كلمة المرور',
                                    icon: Icons.lock_outline,
                                    isPassword: true,
                                    obscure: _obscurePass,
                                    onToggleObscure: () => setState(() {
                                      _obscurePass = !_obscurePass;
                                    }),
                                    textInputAction: TextInputAction.next,
                                  ),
                                  // مؤشر قوة كلمة المرور
                                  if (_passCtrl.text.isNotEmpty)
                                    _PasswordStrengthIndicator(
                                      score: _passwordScore,
                                      color: _getScoreColor(_passwordScore),
                                      text: _getScoreText(_passwordScore),
                                      warning: _passwordWarning,
                                    ),
                                  const SizedBox(height: 12),
                                  _SaafField(
                                    controller: _confirmCtrl,
                                    hint: 'تأكيد كلمة المرور',
                                    icon: Icons.lock_outline,
                                    isPassword: true,
                                    obscure: _obscureConfirm,
                                    onToggleObscure: () => setState(() {
                                      _obscureConfirm = !_obscureConfirm;
                                    }),
                                    textInputAction: TextInputAction.done,
                                  ),
                                  const SizedBox(height: 18),

                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Checkbox(
                                        value: _agreeTerms,
                                        onChanged: (v) => setState(
                                          () => _agreeTerms = v ?? false,
                                        ),
                                        activeColor: kOrange,
                                        checkColor: kDeepGreen,
                                        side: const BorderSide(
                                          color: kLightBeige,
                                        ),
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 12.0,
                                          ),
                                          child: InkWell(
                                            onTap: _showTermsDialog,
                                            child: RichText(
                                              textAlign: TextAlign.right,
                                              text: TextSpan(
                                                style: GoogleFonts.almarai(
                                                  color: kLightBeige.withValues(
                                                    alpha: 0.8,
                                                  ),
                                                  fontSize: 13,
                                                ),
                                                children: [
                                                  const TextSpan(
                                                    text: 'أوافق على ',
                                                  ),
                                                  TextSpan(
                                                    text:
                                                        'شروط الخدمة وسياسة الخصوصية',
                                                    style: GoogleFonts.almarai(
                                                      color: kOrange,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      decoration: TextDecoration
                                                          .underline,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),

                                  _SaafButton(
                                    label: _loading
                                        ? '...جاري الإنشاء'
                                        : 'إنشاء الحساب',
                                    onTap: _loading ? () {} : _signUp,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'لديك حساب مسبقًا؟ ',
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
                                        onPressed: () {
                                          if (Navigator.canPop(context)) {
                                            Navigator.pop(context);
                                          } else {
                                            Navigator.pushReplacementNamed(
                                              context,
                                              '/login',
                                            );
                                          }
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: kOrange,
                                        ),
                                        child: Text(
                                          'سجّل دخولك',
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
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.pop(context),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.arrow_back, color: Colors.white),
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
    );
  }
}

// 💡 Widget جديد لعرض مؤشر قوة كلمة المرور
class _PasswordStrengthIndicator extends StatelessWidget {
  final int score;
  final Color color;
  final String text;
  final String? warning;

  const _PasswordStrengthIndicator({
    required this.score,
    required this.color,
    required this.text,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    if (score == 0 && warning == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: score / 4,
                  backgroundColor: Colors.white54,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                text,
                style: GoogleFonts.almarai(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (warning != null && score < 2)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                'تحذير: $warning',
                style: GoogleFonts.almarai(
                  color: Colors.red.shade200,
                  fontSize: 12,
                ),
              ),
            ),
        ],
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
