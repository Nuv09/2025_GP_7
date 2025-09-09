// lib/login_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'signup_screen.dart';

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
  bool _remember = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: GoogleFonts.notoNaskhArabicTextTheme(
            Theme.of(context).textTheme,
          ),
        ),
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
                      kDeepGreen.withOpacity(0.7),
                      kDeepGreen.withOpacity(0.95),
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
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.15),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'مرحبًا بعودتك!',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.notoNaskhArabic(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w700,
                                      color: kLightBeige,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'سجّل دخولك إلى حسابك',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: kLightBeige.withOpacity(0.85),
                                    ),
                                  ),
                                  const SizedBox(height: 18),

                                  _SaafField(
                                    controller: _emailCtrl,
                                    hint: 'اسم المستخدم',
                                    icon: Icons.person_outline,
                                    keyboardType: TextInputType.text,
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
                                  ),
                                  const SizedBox(height: 10),

                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Checkbox(
                                            value: _remember,
                                            onChanged: (v) => setState(
                                              () => _remember = v ?? false,
                                            ),
                                            activeColor: kOrange,
                                            checkColor: kDeepGreen,
                                            side: BorderSide(
                                              color: Colors.white.withOpacity(
                                                0.6,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            'تذكرني',
                                            style: TextStyle(
                                              color: kLightBeige.withOpacity(
                                                0.9,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'لسا ما فعّلنا استرجاع كلمة المرور',
                                              ),
                                            ),
                                          );
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: kLightBeige
                                              .withOpacity(0.9),
                                        ),
                                        child: const Text(
                                          'هل نسيت كلمة المرور؟',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),

                                  _SaafButton(
                                    label: 'تسجيل الدخول',
                                    onTap: () {
                                      Navigator.pushReplacementNamed(
                                        context,
                                        '/farms',
                                      );
                                    },
                                  ),

                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'لا تملك حسابًا؟ ',
                                        style: TextStyle(
                                          color: kLightBeige.withOpacity(0.85),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pushNamed(
                                          context,
                                          SignUpScreen.routeName,
                                        ),
                                        style: TextButton.styleFrom(
                                          foregroundColor: kOrange,
                                        ),
                                        child: const Text('أنشئ حسابًا'),
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
        color: kLightBeige.withOpacity(opacity),
      ),
    );
  }
}

class _SaafField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool isPassword;
  final bool obscure;
  final VoidCallback? onToggleObscure;

  const _SaafField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.isPassword = false,
    this.obscure = false,
    this.onToggleObscure,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: isPassword ? obscure : false,
      style: const TextStyle(color: kDeepGreen),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: kDeepGreen.withOpacity(0.6)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.92),
        prefixIcon: Icon(icon, color: kDeepGreen),
        suffixIcon: isPassword
            ? IconButton(
                onPressed: onToggleObscure,
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: kDeepGreen.withOpacity(0.8),
                ),
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kDeepGreen, width: 1.2),
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
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: const Center(
              child: Text(
                'تسجيل الدخول',
                style: TextStyle(
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
