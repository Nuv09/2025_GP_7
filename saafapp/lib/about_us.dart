import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// الثوابت والألوان
const Color kDeepGreen = Color(0xFF042C25); // أخضر داكن (اللون الرئيسي/الخلفية)
const Color kLightBeige = Color(
  0xFFFFF6E0,
); // البيج الفاتح (اللون المستخدم للنص الرئيسي)
const Color kAccentColor = Color(0xFFEBB974); // برتقالي (لون التمييز/العناوين)
const Color kBackgroundColor = Color(0xFFF7F7F7); // اللون الأساسي الفاتح

class AboutUsPage extends StatefulWidget {
  const AboutUsPage({super.key});

  @override
  State<AboutUsPage> createState() => _AboutUsPageState();
}

class _AboutUsPageState extends State<AboutUsPage>
    with TickerProviderStateMixin {
  // للتحكم في رسوم دخول الصور
  late AnimationController _imagesController;
  // للتحكم في رسوم دخول النص
  late AnimationController _textController;

  // تأثيرات الصور: شفافية (Fade) وتحرك (Slide)
  late Animation<double> _imageOpacity;
  late Animation<Offset> _imageOffset;

  // تأثيرات النص: شفافية (Fade) وتحرك (Slide)
  late Animation<double> _textOpacity;
  late Animation<Offset> _textOffset;

  @override
  void initState() {
    super.initState();

    // 1. إعداد الـ Controllers
    _imagesController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // 2. إعداد الـ Animations
    _imageOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _imagesController, curve: Curves.easeOut),
    );
    _imageOffset =
        Tween<Offset>(
          begin: const Offset(-0.2, 0), // التحرك من اليسار
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _imagesController, curve: Curves.easeOut),
        );

    _textOpacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _textController, curve: Curves.easeOut));
    _textOffset = Tween<Offset>(
      begin: const Offset(0, 0.1), // التحرك من الأسفل
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textController, curve: Curves.easeOut));

    // 3. تشغيل الرسوم المتحركة بتأخير
    Future.delayed(const Duration(milliseconds: 200), () {
      _imagesController.forward();
      // تأخير النص قليلاً بعد الصور لإعطاء تأثير أعمق
      Future.delayed(const Duration(milliseconds: 300), () {
        _textController.forward();
      });
    });
  }

  @override
  void dispose() {
    _imagesController.dispose();
    _textController.dispose();
    super.dispose();
  }

  // Widget صورة بدائرة مع ظل ناعم
  Widget _circleImage(String path, double size, {double rotation = 0}) {
    return Transform.rotate(
      angle: rotation,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            path,
            fit: BoxFit.cover,
            // Fallback for asset images
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey.shade300,
              child: Center(
                child: Icon(
                  Icons.image_not_supported,
                  size: size / 3,
                  color: kDeepGreen,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

Widget _buildImageSection(BuildContext context, double maxSize) {
  final double spacing = 16.0;
  final double radius = 20.0;

  return SlideTransition(
    position: _imageOffset,
    child: FadeTransition(
      opacity: _imageOpacity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide = constraints.maxWidth > 600;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // الصورة العلوية مع النص
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: Image.asset(
                      'assets/images/about1.png',
                      width: double.infinity,
                      height: isWide ? 300 : 220,
                      fit: BoxFit.cover,
                    ),
                  ),
                  // تراكب شفاف فوق الصورة
                  Container(
                    width: double.infinity,
                    height: isWide ? 300 : 220,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.4),
                        ],
                      ),
                    ),
                  ),
                  // النص في الوسط
                  Positioned(
                    bottom: 20,
                    child: Text(
                      "من قلب المزارع السعودية 🌴",
                      style: GoogleFonts.almarai(
                        color: Colors.white,
                        fontSize: isWide ? 24 : 18,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: spacing),

              // الصف السفلي بصورتين متجاورتين
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: Image.asset(
                        'assets/images/about2.png',
                        height: isWide ? 200 : 160,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  SizedBox(width: spacing),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: Image.asset(
                        'assets/images/about3.png',
                        height: isWide ? 200 : 160,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}


  // 💡 تصميم جزء النص والمحتوى
  Widget _buildTextSection() {
    return SlideTransition(
      position: _textOffset,
      child: FadeTransition(
        opacity: _textOpacity,
        child: Container(
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "   سعف… حيث تلتقي الزراعة بالذكاء",
                textAlign: TextAlign.right,
                style: GoogleFonts.almarai(
                  color: kAccentColor, // اللون البرتقالي
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "نحو مستقبل زراعي أكثر دقة واستدامة",
                textAlign: TextAlign.right,
                style: GoogleFonts.almarai(
                  color: kLightBeige, // اللون الفاتح للخلفية كالنص
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 25),
              Text(
                "في سعف، نؤمن أن الزراعة ليست مجرد مهنة… بل إرثٌ يُحفظ وتقنيةٌ تتطور.\n"
                "نعمل على تمكين المزارعين بخدمات ذكية تعتمد على الذكاء الاصطناعي وصور الأقمار الصناعية، لنقدم رؤية واضحة لحالة النخيل وصحته، ونساعد في اكتشاف التغيرات والإجهاد الزراعي مبكرًا.\n"
                "هدفنا هو دعم القطاع الزراعي بالحلول الرقمية التي ترتقي بجودة الإنتاج وتحافظ على استدامة النخيل، أحد أهم رموز الخير في أرض المملكة.",

                textAlign: TextAlign.right,
                style: GoogleFonts.almarai(
                  color: kLightBeige.withValues(alpha: 0.7), // لون فاتح لنص المحتوى
                  height: 1.7,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 30),
              // تم حذف استدعاء زر التواصل
            ],
          ),
        ),
      ),
    );
  }

  // دالة مساعدة لتحديد الشاشة الضيقة
  bool isNarrowScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 800;
  }

  @override
  Widget build(BuildContext context) {
    // تحديد ما إذا كانت الشاشة ضيقة (عرض أقل من 800)
    final isNarrow = isNarrowScreen(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        // الخلفية أصبحت kDeepGreen
        backgroundColor: kDeepGreen,
        body: Center(
          // استخدام LayoutBuilder لضمان التجاوب
          child: LayoutBuilder(
            builder: (context, constraints) {
              // إذا كان العرض ضيقاً، استخدم Column (تكدس رأسي)
              if (isNarrow) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // تمرير العرض الكامل للمقطع (مع الأخذ في الاعتبار الهامش)
                      _buildImageSection(context, constraints.maxWidth - 40),
                      const SizedBox(height: 40),
                      _buildTextSection(),
                    ],
                  ),
                );
              } else {
                // إذا كان العرض واسعاً، استخدم Row (تقسيم جانبي)
                // عرض قسم الصور يمثل 40% من العرض الكلي
                final imageSectionWidth = constraints.maxWidth * 0.40;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // قسم الصور (40% من المساحة)
                    Expanded(
                      flex: 4,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 40),
                          // تمرير عرض القسم إلى دالة بناء الصور
                          child: _buildImageSection(
                            context,
                            imageSectionWidth - 40,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 40),
                    // قسم النص (60% من المساحة)
                    Expanded(
                      flex: 6,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 40),
                        child: _buildTextSection(),
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
