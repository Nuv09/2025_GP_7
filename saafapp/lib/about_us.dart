import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// الألوان
const Color kDeepGreen = Color(0xFF042C25);
const Color kLightBeige = Color(0xFFFFF6E0);
const Color kAccentColor = Color(0xFFEBB974);

class AboutUsPage extends StatefulWidget {
  const AboutUsPage({super.key});

  @override
  State<AboutUsPage> createState() => _AboutUsPageState();
}

class _AboutUsPageState extends State<AboutUsPage> {
  final PageController _sliderController = PageController(viewportFraction: 0.98);
  final ValueNotifier<int> _activeIndex = ValueNotifier<int>(0);
  Timer? _sliderTimer;

  final List<String> _aboutImages = [
    'assets/images/about1.png',
    'assets/images/about2.png',
    'assets/images/about3.png',
  ];

  @override
  void initState() {
    super.initState();

    _sliderController.addListener(() {
      if (!_sliderController.hasClients) return;
      final p = _sliderController.page;
      if (p == null) return;
      final idx = p.round().clamp(0, _aboutImages.length - 1);
      if (_activeIndex.value != idx) _activeIndex.value = idx;
    });

    // Auto-scroll slider
    _sliderTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_sliderController.hasClients) return;
      final current = (_sliderController.page ?? 0).round();
      final next = (current + 1) % _aboutImages.length;

      _sliderController.animateToPage(
        next,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _sliderTimer?.cancel();
    _sliderController.dispose();
    _activeIndex.dispose();
    super.dispose();
  }

  // ------------------ Helpers -----------------------
  TextStyle _titleSmallStyle() => GoogleFonts.almarai(
        color: kAccentColor,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      );

  TextStyle _headlineStyle(bool narrow) => GoogleFonts.almarai(
        color: kLightBeige,
        fontSize: narrow ? 34 : 44,
        fontWeight: FontWeight.w900,
        height: 1.15,
      );

  TextStyle _bodyStyle() => GoogleFonts.almarai(
        color: kLightBeige.withValues(alpha: 0.78),
        height: 1.8,
        fontSize: 16.5,
        fontWeight: FontWeight.w500,
      );

  // ------------------ Luxury Background -----------------------
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
                    kAccentColor.withValues(alpha: 0.25),
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

  // ------------------ Glass Card -----------------------
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

  // ------------------ Slider -----------------------
  Widget _buildImageSlider(bool narrow) {
    final double h = narrow ? 270 : 520;

    return SizedBox(
      height: h,
      width: double.infinity,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: _glassCard(
            padding: EdgeInsets.zero,
            borderRadius: const BorderRadius.all(Radius.circular(26)),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(26)),
                    child: PageView.builder(
                      controller: _sliderController,
                      itemCount: _aboutImages.length,
                      itemBuilder: (context, index) {
                        return Image.asset(
                          _aboutImages[index],
                          fit: BoxFit.cover,
                        );
                      },
                    ),
                  ),
                ),

                // Overlay luxury gradient
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(Radius.circular(26)),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          kDeepGreen.withValues(alpha: 0.78),
                          kDeepGreen.withValues(alpha: 0.25),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.42, 1.0],
                      ),
                    ),
                  ),
                ),

                // Subtle gold top sheen
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 70,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          kAccentColor.withValues(alpha: 0.08),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

             

                // Dots indicator (lux)
                Positioned(
                  bottom: 18,
                  left: 18,
                  child: ValueListenableBuilder<int>(
                    valueListenable: _activeIndex,
                    builder: (_, active, __) {
                      return _glassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        borderRadius: const BorderRadius.all(Radius.circular(18)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            _aboutImages.length,
                            (i) {
                              final bool on = i == active;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: on ? 18 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: on ? kAccentColor : Colors.white.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------ Text Section -----------------------
  Widget _buildTextSection(bool narrow) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("سعـف… حيث تلتقي الزراعة بالذكاء", textAlign: TextAlign.right, style: _titleSmallStyle()),
          const SizedBox(height: 10),
          Text("نحو مستقبل زراعي أكثر دقّة واستدامة", textAlign: TextAlign.right, style: _headlineStyle(narrow)),
          const SizedBox(height: 18),

          _glassCard(
            padding: const EdgeInsets.all(18),
            child: Text(
              "في سعف، نؤمن أن الزراعة ليست مجرد مهنة… بل إرثٌ يُحفظ وتقنيةٌ تتطور.\n\n"
              "نمكن المزارعين بخدمات ذكية تعتمد على الذكاء الاصطناعي وصور الأقمار الصناعية، لنقدم رؤية واضحة لحالة النخيل وصحته، ونساعد في اكتشاف التغيرات والإجهاد الزراعي مبكرًا.\n\n"
              "هدفنا هو دعم القطاع الزراعي بالحلول الرقمية التي ترتقي بجودة الإنتاج وتحافظ على استدامة النخيل، أحد أهم رموز الخير في أرض المملكة.",
              textAlign: TextAlign.right,
              style: _bodyStyle(),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------ Contact Section -----------------------
  Future<void> _launchSupportEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'support@saafapp.com',
      query: Uri.encodeQueryComponent('subject=استفسار حول تطبيق سعف'),
    );

    await launchUrl(emailLaunchUri, mode: LaunchMode.externalApplication);
  }

  Widget _buildContactSection() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700),
      child: _glassCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: kAccentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kAccentColor.withValues(alpha: 0.28)),
                  ),
                  child: const Icon(Icons.support_agent_rounded, color: kAccentColor, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "تواصل معنا",
                    style: GoogleFonts.almarai(
                      color: kLightBeige,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
  width: double.infinity,
  child: Text(
    "للمساعدة أو الاستفسارات نرحّب بتواصلكم.",
    textAlign: TextAlign.center,
    style: GoogleFonts.almarai(
      color: Colors.white70,
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
    ),
  ),
),
            const SizedBox(height: 14),

            // Email Button (lux)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _launchSupportEmail,
                icon: const Icon(Icons.email_rounded),
                label: Text(
                  "support@saafapp.com",
                  style: GoogleFonts.almarai(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAccentColor,
                  foregroundColor: kDeepGreen,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),

            const SizedBox(height: 10),

           
          ],
        ),
      ),
    );
  }

  // ------------------ Build -----------------------
  @override
  Widget build(BuildContext context) {
    final bool narrow = MediaQuery.of(context).size.width < 900;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kDeepGreen,
        body: Stack(
          children: [
            _buildLuxBackground(),
            SafeArea(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (narrow) {
                      // ------------------ Mobile Layout -----------------------
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 28),
                          child: Column(
                            children: [
                              const SizedBox(height: 12),
                              _buildImageSlider(true),
                              const SizedBox(height: 18),

                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildTextSection(true),
                                    const SizedBox(height: 16),
                                    _buildContactSection(),
                                    const SizedBox(height: 60),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // ------------------ Wide Layout -----------------------
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1200),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: _buildImageSlider(false),
                                  ),
                                ),
                                const SizedBox(width: 22),
                                Expanded(
                                  flex: 5,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildTextSection(false),
                                        const SizedBox(height: 16),
                                        _buildContactSection(),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}