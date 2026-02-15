import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:saafapp/constant.dart';
import 'package:saafapp/dashboard.dart';
import 'package:saafapp/widgets/farms/farm_card.dart';
import 'package:saafapp/notifications_page.dart';

class FarmsScreen extends StatelessWidget {
  const FarmsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: darkGreenColor,
      appBar: _farmsAppBar(context),
      body: user == null ? _notLoggedIn(context) : _FarmsList(uid: user.uid),
    );
  }

  AppBar _farmsAppBar(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      elevation: 0,
      backgroundColor: darkGreenColor,
      toolbarHeight: 80,
      title: Row(
        textDirection: TextDirection.ltr,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // زر التنبيهات+
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationsPage(),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: goldColor.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: goldColor.withValues(alpha: 0.1),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    color: Colors.white,
                    size: 24,
                  ),

                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 216, 74, 74),
                        shape: BoxShape.circle,
                        border: Border.all(color: darkGreenColor, width: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ---------------------------------------------

          // اللوقو في النص
          const Expanded(child: Center(child: _LogoButton())),

          // "مرحباً <الاسم>"
          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser!.uid)
                .get(),
            builder: (context, snapshot) {
              String username = "مستخدم";

              if (snapshot.hasData && snapshot.data!.data() != null) {
                final data = snapshot.data!.data()!;
                username = data['name'] ?? 'مستخدم';
              }

              return GreetingText(username: username);
            },
          ),

          // زر تسجيل الخروج
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            tooltip: 'تسجيل الخروج',
            onPressed: () async {
              try {
                await FirebaseAuth.instance.signOut();
              } catch (_) {}
              if (context.mounted) {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/login', (r) => false);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _notLoggedIn(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              'الرجاء تسجيل الدخول لعرض مزارعك',
              style: GoogleFonts.almarai(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: darkGreenColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('تسجيل الدخول', style: GoogleFonts.almarai()),
            ),
          ],
        ),
      ),
    );
  }
}

class _FarmsList extends StatelessWidget {
  final String uid;
  const _FarmsList({required this.uid});

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  // دالة إظهار النافذة المنبثقة للتحليل بدلاً من السنيك بار
  void _showProcessingDialog(
    BuildContext context,
    String farmName,
    String status,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF042C25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Icon(
          status == 'failed' ? Icons.error_outline : Icons.auto_awesome,
          color: goldColor,
          size: 40,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              status == 'failed' ? "تعذر التحليل" : "التحليل جارٍ الآن",
              style: GoogleFonts.almarai(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              status == 'failed'
                  ? "للأسف واجهنا مشكلة في تحليل صور مزرعة $farmName. يرجى المحاولة لاحقاً."
                  : "نحن نقوم الآن بمعالجة صور الأقمار الصناعية الخاصة بمزرعة $farmName لاستخراج المؤشرات الحيوية. ستصلك النتائج فور اكتمالها.",
              textAlign: TextAlign.center,
              style: GoogleFonts.almarai(
                color: Colors.white70,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            if (status != 'failed') ...[
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: goldColor),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              "حسناً",
              style: GoogleFonts.almarai(
                color: goldColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final farmsQuery = FirebaseFirestore.instance
        .collection('farms')
        .where('createdBy', isEqualTo: uid);

    return StreamBuilder<QuerySnapshot>(
      stream: farmsQuery.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        if (snap.hasError) {
          final msg = snap.error.toString();
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'تعذر جلب البيانات:\n$msg',
                style: const TextStyle(color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final docs = (snap.data?.docs ?? []).toList()
          ..sort((a, b) {
            final ta = a['createdAt'];
            final tb = b['createdAt'];
            final va = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
            final vb = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
            return vb.compareTo(va);
          });

        if (docs.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 24, 8),
                child: Text('مزارعي', style: saafPageTitle),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'لا توجد مزارع بعد. أضف أول مزرعة من زر (+) بالأسفل.',
                    style: GoogleFonts.almarai(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 24, 8),
              child: Text('مزارعي', style: saafPageTitle),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final d = doc.data() as Map<String, dynamic>;
                  final name = (d['farmName'] ?? '').toString();
                  final region = (d['region'] ?? '').toString();
                  final imageURL = (d['imageURL'] ?? d['imageUrl'] ?? '')
                      .toString()
                      .trim();
                  final createdAt = (d['createdAt'] is Timestamp)
                      ? (d['createdAt'] as Timestamp).toDate()
                      : null;

                  final status = (d['status'] ?? 'pending').toString();

                  return GestureDetector(
                    onTap: () {
                      if (status == 'done') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                FarmDashboardPage(farmData: d, farmId: doc.id),
                          ),
                        );
                      } else {
                        // إظهار نافذة التنبيه بدلاً من السنيك بار
                        _showProcessingDialog(context, name, status);
                      }
                    },
                    child: Stack(
                      children: [
                        FarmCard(
                          farmIndex: i,
                          title: name.isEmpty ? 'مزرعة بدون اسم' : name,
                          subtitle: region.isEmpty ? '—' : region,
                          sizeText: null, // تم حذف المساحة نهائياً من العرض هنا
                          imageURL: imageURL.isNotEmpty ? imageURL : null,
                          createdAt: createdAt,
                          onEdit: () async {
                            await Navigator.pushNamed(
                              context,
                              '/editFarm',
                              arguments: {'farmId': doc.id, 'initialData': d},
                            );
                          },
                          onDelete: () async {
                            bool confirmDelete =
                                await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: const Color(0xFF042C25),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    title: Text(
                                      'تأكيد الحذف',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.almarai(
                                        color: const Color(0xFFFFF6E0),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 22,
                                      ),
                                    ),
                                    content: Text(
                                      'هل أنت متأكد من حذف مزرعة "$name"؟ لا يمكن التراجع عن هذا الإجراء.',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.almarai(
                                        color: const Color(0xFFFFF6E0),
                                        fontSize: 16,
                                        height: 1.5,
                                      ),
                                    ),
                                    actionsAlignment: MainAxisAlignment.center,
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: Text(
                                          'إلغاء',
                                          style: GoogleFonts.almarai(
                                            color: const Color(0xFFFFF6E0),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFFF44336,
                                          ),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: Text(
                                          'حذف',
                                          style: GoogleFonts.almarai(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ) ??
                                false;

                            if (confirmDelete) {
                              try {
                                if (imageURL.isNotEmpty) {
                                  try {
                                    await FirebaseStorage.instance
                                        .refFromURL(imageURL)
                                        .delete();
                                  } catch (_) {}
                                }
                                await FirebaseFirestore.instance
                                    .collection('farms')
                                    .doc(doc.id)
                                    .delete();
                              } catch (_) {}
                            }
                          },
                        ),

                        if (status == 'pending' || status == 'running')
                          Positioned(
                            left: 25,
                            top: 25,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: goldColor.withOpacity(0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        goldColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "جاري التحليل",
                                    style: GoogleFonts.almarai(
                                      color: goldColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
// ======================= ستايل الاسم =======================

class GreetingText extends StatefulWidget {
  final String username;

  const GreetingText({super.key, required this.username});

  @override
  State<GreetingText> createState() => _GreetingTextState();
}

class _GreetingTextState extends State<GreetingText>
    with TickerProviderStateMixin {
  bool _hideGreeting = false; // false = "مرحباً الاسم" ، true = "الاسم" فقط

  @override
  void initState() {
    super.initState();
    // بعد 7 ثواني نخلي "مرحباً" تتحرك يمين وتتلاشى
    Future.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() {
        _hideGreeting = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.almarai(
      color: whiteColor,
      fontWeight: FontWeight.w700,
      fontSize: 18,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
            opacity: _hideGreeting ? 0.0 : 1.0,
            child: _hideGreeting
                ? const SizedBox.shrink()
                : Text('مرحباً ', style: style),
          ),
        ),
        Text(widget.username, style: style),
      ],
    );
  }
}

// ======================= ستايل اللوقو =======================

class _LogoButton extends StatefulWidget {
  const _LogoButton();

  @override
  State<_LogoButton> createState() => _LogoButtonState();
}

class _LogoButtonState extends State<_LogoButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    const double logoSize = 150.0;

    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _scale = 1.12;
        });
      },
      onExit: (_) {
        setState(() {
          _scale = 1.0;
        });
      },
      child: GestureDetector(
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: Image.asset(
            'assets/images/saaf_logo.png',
            height: logoSize,
            width: logoSize,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
