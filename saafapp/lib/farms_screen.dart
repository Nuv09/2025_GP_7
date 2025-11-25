import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:saafapp/constant.dart';
import 'package:saafapp/widgets/farms/farm_card.dart';

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
          // زر الإضافة +
          IconButton(
            tooltip: 'إضافة مزرعة',
            onPressed: () async {
              final result = await Navigator.pushNamed(context, '/addFarm');
              if (result == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'تمت إضافة المزرعة بنجاح ✅',
                      style: GoogleFonts.almarai(),
                    ),
                    backgroundColor: Colors.green.shade600,
                  ),
                );
              }
            },
            icon: const Icon(Icons.add, color: Colors.white),
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
            return vb.compareTo(va); // الأحدث أولًا
          });

        // لا توجد مزارع
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
                    'لا توجد مزارع بعد. أضف أول مزرعة من زر (+) بالأعلى.',
                    style: GoogleFonts.almarai(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          );
        }

        // في مزارع
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
                  final size = (d['farmSize'] ?? '').toString();
                  final imageURL = (d['imageURL'] ?? d['imageUrl'] ?? '')
                      .toString()
                      .trim();
                  final createdAt = (d['createdAt'] is Timestamp)
                      ? (d['createdAt'] as Timestamp).toDate()
                      : null;

                  final status = (d['status'] ?? '').toString();
                  final finalCount = (d['finalCount'] is int)
                      ? d['finalCount'] as int
                      : null;
                  final finalQuality = (d['finalQuality'] is num)
                      ? (d['finalQuality'] as num).toDouble()
                      : null;
                  final errorMessage = (d['errorMessage'] ?? '') as String?;

                  // 👇 نقرأ الهيلث من Firestore
                  final healthMap = d['health'] is Map<String, dynamic>
                      ? d['health'] as Map<String, dynamic>
                      : null;

                  final healthyPct = healthMap != null
                      ? _asDouble(healthMap['Healthy_Pct'])
                      : null;
                  final monitorPct = healthMap != null
                      ? _asDouble(healthMap['Monitor_Pct'])
                      : null;
                  final criticalPct = healthMap != null
                      ? _asDouble(healthMap['Critical_Pct'])
                      : null;

                  return FarmCard(
                    farmIndex: i,
                    title: name.isEmpty ? 'مزرعة بدون اسم' : name,
                    subtitle: region.isEmpty ? '—' : region,
                    sizeText: size.isEmpty ? null : '$size م²',
                    imageURL: imageURL.isNotEmpty ? imageURL : null,
                    createdAt: createdAt,
                    analysisStatus: status.isEmpty ? null : status,
                    analysisCount: finalCount,
                    analysisQuality: finalQuality,
                    analysisError:
                        (errorMessage != null && errorMessage.isNotEmpty)
                        ? errorMessage
                        : null,

                    // 🩺 نسب صحة النخيل
                    healthyPct: healthyPct,
                    monitorPct: monitorPct,
                    criticalPct: criticalPct,

                    onEdit: () async {
                      await Navigator.pushNamed(
                        context,
                        '/editFarm',
                        arguments: {'farmId': doc.id, 'initialData': d},
                      );
                    },
                    onDelete: () async {
                      final ok =
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
                                'هل أنت متأكد من حذف "${name.isEmpty ? 'هذه المزرعة' : name}"؟',
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

                      if (!ok) return;

                      try {
                        await FirebaseFirestore.instance
                            .collection('farms')
                            .doc(doc.id)
                            .delete();
                        final url = imageURL;
                        if (url.isNotEmpty) {
                          await FirebaseStorage.instance
                              .refFromURL(url)
                              .delete();
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم حذف المزرعة بنجاح ✅'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تعذر الحذف: $e')),
                          );
                        }
                      }
                    },
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
