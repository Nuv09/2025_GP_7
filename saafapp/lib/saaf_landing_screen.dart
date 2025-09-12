import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';

class SaafLandingScreen extends StatefulWidget {
  const SaafLandingScreen({super.key});

  @override
  State<SaafLandingScreen> createState() => _SaafLandingScreenState();
}

class _SaafLandingScreenState extends State<SaafLandingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fadeLogo;
  late final Animation<Offset> _slideCard;

  // 🔊 الصوت
  late final AudioPlayer _player;
  final double _vol = 0.80;
  bool _ambientStopped = false;

  // 🎨 ألوان سَعَف الجديدة
  static const Color kDeepGreen = Color(0xFF042C25);
  static const Color kLightBeige = Color(0xFFFFF6E0);
  static const Color kOrange = Color(0xFFEBB974);

  @override
  void initState() {
    super.initState();

    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeLogo = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    _slideCard = Tween(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack));
    _c.forward();

    _player = AudioPlayer();
    _playAmbient();
  }

  Future<void> _playAmbient() async {
    try {
      await _player.setPlayerMode(PlayerMode.lowLatency);
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(_vol);
      await _player.setSource(AssetSource('audio/palm_breeze.mp3'));
      await _player.resume();
      Future.delayed(const Duration(seconds: 5), _fadeOutAndStop);
    } catch (_) {}
  }

  Future<void> _fadeOutAndStop() async {
    if (!mounted || _ambientStopped) return;
    try {
      for (double v = _vol; v > 0; v -= 0.04) {
        if (!mounted || _ambientStopped) break;
        await _player.setVolume(v);
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (!_ambientStopped) {
        await _player.stop();
        _ambientStopped = true;
      }
    } catch (_) {}
  }

  Future<void> _stopAmbientNow() async {
    if (_ambientStopped) return;
    try {
      await _player.stop();
    } catch (_) {}
    _ambientStopped = true;
  }

  @override
  void dispose() {
    _stopAmbientNow();
    _player.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // الخلفية
          Image.asset('assets/images/palms.jpg',
              fit: BoxFit.cover, alignment: Alignment.topCenter),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  kDeepGreen.withOpacity(0.7),
                  kDeepGreen.withOpacity(0.95)
                ],
              ),
            ),
          ),

          // ✅ الدوائر الناعمة
          Positioned(
              left: -media.width * 0.2,
              bottom: -media.width * 0.15,
              child: _softCircle(media.width * 0.7)),
          Positioned(
              left: media.width * 0.15,
              bottom: -media.width * 0.25,
              child: _softCircle(media.width * 0.9, opacity: 0.25)),

          // المحتوى
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  const Spacer(),
                  FadeTransition(
                    opacity: _fadeLogo,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/saaf_logo.png',
                          height: media.height * 0.5,
                          fit: BoxFit.fitHeight,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'مساحتك الخضراء لتنظيم مزرعتك',
                          style: TextStyle(
                            fontSize: 18,
                            color: kLightBeige.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  SlideTransition(
                    position: _slideCard,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.15)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'ابدأ رحلتك مع سَعَف',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 16,
                                    color: kLightBeige,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 14),
                              _SaafButton(
                                label: 'ابدأ الآن',
                                onTap: () async {
                                  await _stopAmbientNow();
                                  if (!mounted) return;
                                  Navigator.pushNamed(context, '/login');
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
      backgroundColor: kDeepGreen,
    );
  }

  Widget _softCircle(double size, {double opacity = 0.18}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          shape: BoxShape.circle, color: kLightBeige.withOpacity(opacity)),
    );
  }
}

class _SaafButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SaafButton({required this.label, required this.onTap});

  static const Color kOrange = Color(0xFFEBB974);
  static const Color kLightBeige = Color(0xFFFFF6E0);
  static const Color kDeepGreen = Color(0xFF042C25);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kOrange, kLightBeige]),
          borderRadius: BorderRadius.circular(35),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: const Center(
              child: Text(
                'ابدأ الآن',
                style: TextStyle(
                    color: kDeepGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
