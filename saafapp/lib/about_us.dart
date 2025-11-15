import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

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
  final PageController _sliderController = PageController();
  Timer? _sliderTimer;

  final List<String> _aboutImages = [
    'assets/images/about1.png',
    'assets/images/about2.png',
    'assets/images/about3.png',
  ];

  @override
  void initState() {
    super.initState();

    // Auto-scroll slider
    _sliderTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_sliderController.hasClients) {
        int nextPage = _sliderController.page?.round() ?? 0;
        nextPage = (nextPage + 1) % _aboutImages.length;

        _sliderController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _sliderTimer?.cancel();
    _sliderController.dispose();
    super.dispose();
  }

  // ------------------ Slider -----------------------
  Widget _buildImageSlider() {
    return SizedBox(
      height: 260,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
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

          // شادو أخضر من تحت
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    kDeepGreen.withValues(alpha: 0.65),
                    kDeepGreen.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.4, 1],
                ),
              ),
            ),
          ),

          // النقاط
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedBuilder(
                animation: _sliderController,
                builder: (context, child) {
                  int active = _sliderController.hasClients
                      ? _sliderController.page?.round() ?? 0
                      : 0;

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _aboutImages.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active == index ? 18 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active == index
                              ? kAccentColor
                              : Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(6),
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
    );
  }

  // ------------------ Text Section -----------------------
  // ------------------ Text Section -----------------------
Widget _buildTextSection() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      constraints: const BoxConstraints(maxWidth: 600),
      child: Column(
        // **التغيير هنا: Center بدلاً من End**
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          Text(
            "سعـف… حيث تلتقي الزراعة بالذكاء",
            // **التغيير هنا: Center بدلاً من Right**
            textAlign: TextAlign.right, 
            style: GoogleFonts.almarai(
              color: kAccentColor,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "نحو مستقبل زراعي أكثر دقّة واستدامة",
            // نغير هذا أيضاً ليتوسط مع العنوان أعلاه
            textAlign: TextAlign.right, 
            style: GoogleFonts.almarai(
              color: kLightBeige,
              fontSize: 42,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 25),
          Text(
            "في سعف، نؤمن أن الزراعة ليست مجرد مهنة… بل إرثٌ يُحفظ وتقنيةٌ تتطور.\n\n"
            "نعمل على تمكين المزارعين بخدمات ذكية تعتمد على الذكاء الاصطناعي وصور الأقمار الصناعية، لنقدم رؤية واضحة لحالة النخيل وصحته، ونساعد في اكتشاف التغيرات والإجهاد الزراعي مبكرًا.\n \n"
            "هدفنا هو دعم القطاع الزراعي بالحلول الرقمية التي ترتقي بجودة الإنتاج وتحافظ على استدامة النخيل، أحد أهم رموز الخير في أرض المملكة.",
            // نترك هذا النص محاذياً لليمين لأنه نص طويل
            textAlign: TextAlign.right,
            style: GoogleFonts.almarai(
              color: kLightBeige.withValues(alpha: 0.75),
              height: 1.7,
              fontSize: 17,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------ Contact Section -----------------------
  Widget _buildContactSection() {
    return Column(
      children: [
        const SizedBox(height: 40),

        InkWell(
          onTap: () async {
            final Uri emailLaunchUri = Uri(
              scheme: 'mailto',
              path: 'support@saafapp.com',
              query: Uri.encodeQueryComponent('subject=استفسار حول تطبيق سعف'),
            );
            await launchUrl(
              emailLaunchUri,
              mode: LaunchMode.externalApplication,
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.email_rounded, color: kAccentColor, size: 26),
              const SizedBox(width: 8),
              Text(
                "support@saafapp.com",
                style: GoogleFonts.almarai(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),

        Text(
          "للمساعدة أو الاستفسارات نرحّب بتواصلكم.",
          style: GoogleFonts.almarai(color: Colors.white70, fontSize: 13),
        ),

        const SizedBox(height: 40),
      ],
    );
  }

  // ------------------ Build -----------------------
  @override
  Widget build(BuildContext context) {
    final bool narrow = MediaQuery.of(context).size.width < 800;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kDeepGreen,
        body: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (narrow) {
                // ------------------ Mobile Layout -----------------------
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildImageSlider(), // ← ممتد كامل الصفحة

                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 40,
                        ),
                        child: Column(
                          children: [
                            _buildTextSection(),
                            _buildContactSection(),
                            const SizedBox(height: 70),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                // ------------------ Wide Layout -----------------------
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: _buildImageSlider(), // ← بدون أي padding
                    ),

                    const SizedBox(width: 40),

                    Expanded(
                      flex: 6,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 40, top: 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _buildTextSection(),
                            _buildContactSection(),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }
            },
          ),
        ),
      ),
    );
  }
}
