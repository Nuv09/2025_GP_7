import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:saafapp/constant.dart';
import 'package:saafapp/dashboard.dart';
import 'package:saafapp/widgets/farms/farm_card.dart';
import 'package:saafapp/notifications_page.dart';
import 'package:flutter/services.dart';


class FarmsScreen extends StatelessWidget {
  const FarmsScreen({super.key});

@override
Widget build(BuildContext context) {
  final user = FirebaseAuth.instance.currentUser;

  return AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
    child: Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: _farmsAppBar(context),
      body: Stack(
        children: [
    const _FarmsLuxBackground(),
    Padding(
      padding: const EdgeInsets.only(top: 150),
      child: user == null
          ? _notLoggedIn(context)
          : _FarmsList(uid: user.uid),
          ),
        ],
      ),
    ),
  );
}

  AppBar _farmsAppBar(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      toolbarHeight: 80,
      title: Row(
        textDirection: TextDirection.ltr,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          
          // زر التنبيهات (Badge ديناميكي)
StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance
      .collection('notifications')
      .where('ownerUid', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
      .where('isRead', isEqualTo: false)
      .limit(1)
      .snapshots(),
  builder: (context, snapNoti) {
    final showBadge = (snapNoti.data?.docs.isNotEmpty ?? false);

    return IconButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NotificationsPage(),
      ),
    );
  },
  icon: Stack(
    children: [
      const Icon(
        Icons.notifications_active_outlined,
        color: Colors.white,
        size: 26,
      ),
      if (showBadge)
        Positioned(
  top: 1,
  right: 1,
  child: Container(
    width: 9.5,
    height: 9.5,
    decoration: BoxDecoration(
      color: const Color.fromARGB(255, 216, 74, 74),
      shape: BoxShape.circle,
      border: Border.all(
        color:darkGreenColor  , // أو darkGreenColor إذا تبينها تمزج مع الخلفية
        width: 1.2,
      ),
    ),
  ),
),
    ],
  ),
);
  },
),

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
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/login', (r) => false);
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

// ======================= LIST + SEARCH =======================

class _FarmsList extends StatefulWidget {
  final String uid;
  const _FarmsList({required this.uid});

  @override
  State<_FarmsList> createState() => _FarmsListState();
}

class _FarmsListState extends State<_FarmsList> {
  final TextEditingController _searchCtrl = TextEditingController();
  
  String _q = "";

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

 String _formatDateOnly(dynamic raw) {
  if (raw == null) return "—";

  try {
    DateTime dt;

    if (raw is Timestamp) {
      dt = raw.toDate();
    } else if (raw is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(raw);
    } else if (raw is String) {
      // لو كان مخزن string (مثلاً "2026-02-24" أو "24/02/2026")
      // نحاول نرجّعه بنفس الفورمات اللي نبيه
      final s = raw.trim();

      // لو أصلاً داخل DD/MM/YYYY خلّيه زي ما هو
      if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(s)) return s;

      // لو داخل YYYY-MM-DD
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
        final y = s.substring(0, 4);
        final m = s.substring(5, 7);
        final d = s.substring(8, 10);
        return "$d/$m/$y";
      }

      // آخر محاولة: parse عام
      final parsed = DateTime.tryParse(s);
      if (parsed != null) {
        dt = parsed;
      } else {
        return s; // اتركه مثل ما هو إذا ما قدرنا
      }
    } else {
      return "—";
    }

    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');

    return "$dd/$mm";
  } catch (_) {
    return "—";
  }
}
  double _getHealthyPct(Map<String, dynamic> d) {
  try {
    final healthRoot = (d['health'] as Map?)?.cast<String, dynamic>() ?? {};
    final current =
        (healthRoot['current_health'] as Map?)?.cast<String, dynamic>() ?? {};

    final v = current['Healthy_Pct'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  } catch (_) {
    return 0.0;
  }
}

 Widget _searchBar() {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
        style: GoogleFonts.almarai(
          color: const Color(0xFFEADEC4), // كريمي
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        cursorColor: const Color(0xFFFDCB6E),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06), // خلفية ناعمة
          hintText: "ابحث باسم المزرعة أو المنطقة...",
          hintStyle: GoogleFonts.almarai(
            color: Colors.white.withValues(alpha: 0.45),
            fontWeight: FontWeight.w500,
          ),

          // الأيقونة يمين (صح للـ RTL)
          suffixIcon: Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: Icon(
              Icons.search_rounded,
              color: const Color(0xFFFDCB6E).withValues(alpha: 0.85),
              size: 26,
            ),
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 48),

          // زر مسح (يسار)
          prefixIcon: _q.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _q = "");
                  },
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),

          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 16),

          // كبسولة ناعمة + إطار خفيف جدًا
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.10), width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.10), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide(
              color: const Color(0xFFFDCB6E).withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
        ),
      ),
    ),
  );
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
        .where('createdBy', isEqualTo: widget.uid);

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

        final filteredDocs = _q.isEmpty
            ? docs
            : docs.where((e) {
                final d = e.data() as Map<String, dynamic>;
                final name = (d['farmName'] ?? '').toString().toLowerCase();
                final region = (d['region'] ?? '').toString().toLowerCase();
                return name.contains(_q) || region.contains(_q);
              }).toList();

        if (filteredDocs.isEmpty) {
          // لو ما فيه مزارع أصلاً
          if (docs.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 24, 8),
                  child: Text('مزارعي', style: saafPageTitle),
                ),
                _searchBar(),
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

          // لو فيه مزارع بس البحث ما طلع نتائج
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 24, 8),
                child: Text('مزارعي', style: saafPageTitle),
              ),
              _searchBar(),
              Expanded(
                child: Center(
                  child: Text(
                    'لا توجد نتائج مطابقة للبحث.',
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
            _searchBar(),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: filteredDocs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final doc = filteredDocs[i];
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

                  final lastAnalysisAt = d['lastAnalysisAt'];
                  final lastDate = _formatDateOnly(lastAnalysisAt);

                  // (موجودة عندك سابقاً، نخليها لو احتجتي لاحقاً)
                  _asDouble(d['farmSize']);
                  final healthyPct = _getHealthyPct(d);

                  return TweenAnimationBuilder<double>(
                    
  key: ValueKey('farm-anim-${doc.id}'),                  
  tween: Tween(begin: 0.0, end: 1.0),
  duration: Duration(milliseconds: 450 + (i * 60)),
  curve: Curves.easeOutCubic,
  builder: (context, t, child) {
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 18),
        child: child,
      ),
    );
  },
  child: _PressScale(
    onTap: () {
      if (status == 'done') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FarmDashboardPage(
              farmData: d,
              farmId: doc.id,
            ),
          ),
        );
      } else {
        _showProcessingDialog(context, name, status);
      }
    },
    child: Stack(
      children: [

       FarmCard(
  farmIndex: i,
  title: name.isEmpty ? 'مزرعة بدون اسم' : name,
  subtitle: region.isEmpty ? '—' : region,
  sizeText: null,
  imageURL: imageURL.isNotEmpty ? imageURL : null,
  createdAt: createdAt,
  lastAnalysisText: lastDate == "—" ? null : lastDate,
  analysisStatus: status,
  healthyPct: healthyPct,
  healthRing: _HealthRing(pct: healthyPct),  onEdit: () async {
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
                    onPressed: () => Navigator.pop(ctx, false),
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
                      backgroundColor: const Color(0xFFF44336),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
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
            await FirebaseStorage.instance.refFromURL(imageURL).delete();
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
    

    
      ],
    ),
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

class _FarmsLuxBackground extends StatelessWidget {
  const _FarmsLuxBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF062F28), // فوق
              Color(0xFF04211C), // تحت
            ],
          ),
        ),
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.18,
            child: CustomPaint(painter: _FarmsNoisePainter()),
          ),
        ),
      ),
    );
  }
}

class _FarmsNoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.05);
    const step = 11.0;

    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        if (((x * 13 + y * 7).toInt() % 9) == 0) {
          canvas.drawCircle(Offset(x, y), 0.9, p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


class _PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _PressScale({required this.child, required this.onTap});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
class _HealthRing extends StatefulWidget {
  final double pct;
  const _HealthRing({required this.pct});

  @override
  State<_HealthRing> createState() => _HealthRingState();
}
class _HealthRingState extends State<_HealthRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color _ringColor(double v) {
    if (v >= 70) return const Color.fromARGB(255, 38, 102, 41); // أخضر
    if (v >= 40) return const Color.fromARGB(255, 244, 180, 76); // أصفر
    return const Color.fromARGB(255, 152, 34, 34); // أحمر
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.pct.clamp(0.0, 100.0);
    final progress = v / 100.0;
    final ring = _ringColor(v);

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final breath = Curves.easeInOut.transform(_c.value);

        final glowOpacity = 0.08 + (breath * 0.18);
        final blur = 18 + (breath * 12);

        return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                blurRadius: blur,
                spreadRadius: 1,
                color: ring.withValues(alpha: glowOpacity), // ✅ هنا
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ring.withValues(alpha: 0.08), // ✅ هنا
              border: Border.all(
                color: ring.withValues(alpha: 0.12), // ✅ هنا
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 6,
                    strokeCap: StrokeCap.round,
                    backgroundColor: const Color.fromARGB(255, 71, 117, 71)
                        .withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      ring.withValues(alpha: 0.95), // ✅ هنا
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "صحة مزرعتك",
                      style: GoogleFonts.almarai(
                        fontSize: 9,
                        color:
                            const Color(0xFF2F4F2F).withValues(alpha: 0.75),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),

                    // ✅ يمنع "رقص" الأرقام
                    SizedBox(
                      width: 52,
                      child: Text(
                        "${v.round()}%",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.almarai(
                          color:
                              const Color(0xFF2F4F2F).withValues(alpha: 0.95),
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}