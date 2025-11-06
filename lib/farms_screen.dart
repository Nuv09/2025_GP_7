// lib/farms_screen.dart
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
      title: Row(
        textDirection: TextDirection.ltr,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'إضافة مزرعة',
            onPressed: () async {
              final result = await Navigator.pushNamed(context, '/addFarm');
              if (result == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تمت إضافة المزرعة بنجاح ✅', style: GoogleFonts.almarai()),
                    backgroundColor: Colors.green.shade600,
                  ),
                );
              }
            },
            icon: const Icon(Icons.add, color: Colors.white),
          ),
          Text(
            "مزارعي",
            style: GoogleFonts.almarai(
              color: whiteColor,
              fontWeight: FontWeight.w700,
              fontSize: Theme.of(context).textTheme.titleLarge?.fontSize ?? 20,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            tooltip: 'تسجيل الخروج',
            onPressed: () async {
              try {
                await FirebaseAuth.instance.signOut();
              } catch (_) {}
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
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
              style: GoogleFonts.almarai(color: Colors.white.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: darkGreenColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  @override
  Widget build(BuildContext context) {
    final farmsQuery = FirebaseFirestore.instance
        .collection('farms')
        .where('createdBy', isEqualTo: uid);
        // ملاحظة: أزلنا orderBy لتفادي الحاجة لـ Index

    return StreamBuilder<QuerySnapshot>(
      stream: farmsQuery.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
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

        if (docs.isEmpty) {
          return Center(
            child: Text(
              'لا توجد مزارع بعد. أضف أول مزرعة من زر (+) بالأعلى.',
              style: GoogleFonts.almarai(color: Colors.white70),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final d = doc.data() as Map<String, dynamic>;
            final name = (d['farmName'] ?? '').toString();
            final region = (d['region'] ?? '').toString();
            final size = (d['farmSize'] ?? '').toString();
            final imageURL = (d['imageURL'] ?? d['imageUrl'] ?? '').toString().trim();
            final createdAt = (d['createdAt'] is Timestamp)
                ? (d['createdAt'] as Timestamp).toDate()
                : null;

            return FarmCard(
              farmIndex: i,
              title: name.isEmpty ? 'مزرعة بدون اسم' : name,
              subtitle: region.isEmpty ? '—' : region,
              sizeText: size.isEmpty ? null : '$size م²',
              imageURL: imageURL.isNotEmpty ? imageURL : null,
              createdAt: createdAt,
              onEdit: () async {
                await Navigator.pushNamed(
                  context,
                  '/editFarm',
                  arguments: {
                    'farmId': doc.id,
                    'initialData': d,
                  },
                );
              },
              onDelete: () async {
                final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color.fromARGB(255, 3, 56, 13), // خلفية داكنة
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        title: Text(
                          'تأكيد الحذف',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.almarai(
                            color: const Color(0xFFFDCB6E), // secondaryColor
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                          ),
                        ),
                        content: Text(
                          'هل أنت متأكد من حذف "${name.isEmpty ? 'هذه المزرعة' : name}"؟',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.almarai(
                            color: const Color(0xFFFDCB6E),
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
                                color: const Color(0xFF777777),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              // أحمر تحذيري (بدّليه للذهبي لو تبين نفس زر "متابعة")
                              backgroundColor: const Color(0xFFF44336),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(
                              'حذف',
                              style: GoogleFonts.almarai(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ) ??
                    false;

                if (!ok) return;

                try {
                  await FirebaseFirestore.instance.collection('farms').doc(doc.id).delete();
                  final url = imageURL;
                  if (url.isNotEmpty) {
                    await FirebaseStorage.instance.refFromURL(url).delete();
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم حذف المزرعة بنجاح ✅')),
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
        );
      },
    );
  }
}
