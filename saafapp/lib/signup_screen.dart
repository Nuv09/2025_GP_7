import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  bool _obscurePass = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
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

                                  _SaafButton(
                                    label: 'إنشاء الحساب',
                                    onTap: () {
                                      final name = _nameCtrl.text.trim();
                                      final email = _emailCtrl.text.trim();
                                      final p1 = _passCtrl.text;
                                      final p2 = _confirmCtrl.text;

                                      if (name.isEmpty ||
                                          email.isEmpty ||
                                          p1.isEmpty ||
                                          p2.isEmpty) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'فضلاً أكمل جميع الحقول', // غيّري النص حسب الحالة
                                              style:
                                                  GoogleFonts.almarai(), // <<< CHANGED
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      if (p1.length < 6) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'كلمة المرور يجب أن تكون 6 أحرف على الأقل', // غيّري النص حسب الحالة
                                              style:
                                                  GoogleFonts.almarai(), // <<< CHANGED
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      if (p1 != p2) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'تأكيد كلمة المرور غير متطابق', // غيّري النص حسب الحالة
                                              style:
                                                  GoogleFonts.almarai(), // <<< CHANGED
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'تم إنشاء الحساب ✅', // غيّري النص حسب الحالة
                                            style:
                                                GoogleFonts.almarai(), // <<< CHANGED
                                          ),
                                        ),
                                      );
                                    },
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
                                        onPressed: () =>
                                            Navigator.pushReplacementNamed(
                                              context,
                                              '/main',
                                            ),
                                        style: TextButton.styleFrom(
                                          foregroundColor: kOrange,
                                        ),
                                        child: Text(
                                          'سجّل دخولك',
                                          style:
                                              GoogleFonts.almarai(), // <<< CHANGED
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
          // <<< CHANGED
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
              // <<< no const
              child: Text(
                label, // <<< استخدم البراميتر
                style: GoogleFonts.almarai(
                  // <<< CHANGED
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
