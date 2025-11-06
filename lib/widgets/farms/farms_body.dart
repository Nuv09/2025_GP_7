// lib/widgets/farms/farms_body.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saafapp/constant.dart';

// Firebase (قراءة فقط)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FarmsBody extends StatelessWidget {
  const FarmsBody({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const SizedBox(height: defaultPadding + 20),
          Expanded(
            child: Stack(
              children: [
                // الخلفية البيج
                Container(
                  margin: const EdgeInsets.only(top: 70.0),
                  decoration: const BoxDecoration(
                    color: beige,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(40),
                      topRight: Radius.circular(40),
                    ),
                  ),
                ),

                if (uid == null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'يرجى تسجيل الدخول لعرض مزارعك',
                        style: GoogleFonts.almarai(
                          color: Colors.black.withValues(alpha: 0.6),
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('farms')
                        .where('createdBy', isEqualTo: uid)
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: darkGreenColor),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              'تعذر جلب البيانات',
                              style: GoogleFonts.almarai(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              'لا توجد مزارع بعد. أضف أول مزرعة من زر (+) بالأعلى.',
                              style: GoogleFonts.almarai(
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + 84),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final d = docs[i].data() as Map<String, dynamic>;
                          final name = (d['farmName'] ?? '').toString();
                          final region = (d['region'] ?? '').toString();
                          final size = (d['farmSize'] ?? '').toString();

                          // ✅ موحّد ويغطي imageURL و imageUrl
                          final imageURL =
                              (d['imageURL'] ?? d['imageUrl'] ?? '').toString().trim();

                          final createdAt = (d['createdAt'] is Timestamp)
                              ? (d['createdAt'] as Timestamp).toDate()
                              : null;

                          return _FarmCard(
                            title: name.isEmpty ? 'مزرعة بدون اسم' : name,
                            subtitle: region.isEmpty ? '—' : region,
                            sizeText: size.isEmpty ? null : '$size م²',
                            imageURL: imageURL.isNotEmpty ? imageURL : null,
                            createdAt: createdAt,
                          );
                        },
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة عرض مزرعة (داخليًا لهذا الملف)
class _FarmCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? sizeText;
  final String? imageURL;
  final DateTime? createdAt;

  const _FarmCard({
    required this.title,
    required this.subtitle,
    this.sizeText,
    this.imageURL,
    this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.15)),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.25),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // صورة المزرعة
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            child: SizedBox(
              width: 110,
              height: 100,
              child: (imageURL != null && imageURL!.isNotEmpty)
                  ? Image.network(
                      imageURL!,
                      fit: BoxFit.cover,
                      // ✅ طباعة أي خطأ تحميل بدلًا من الصمت
                      errorBuilder: (context, error, stackTrace) {
                        debugPrint('Image load error: $error | url=$imageURL');
                        return Container(
                          color: const Color(0x22000000),
                          child: const Icon(Icons.broken_image, color: Colors.white60),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: const Color(0x22000000),
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          ),
                        );
                      },
                    )
                  : Container(
                      color: const Color(0x22000000),
                      child: const Icon(Icons.image_not_supported, color: Colors.white60),
                    ),
            ),
          ),

          // معلومات
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.almarai(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 18, color: Colors.white70),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.almarai(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (sizeText != null) ...[
                        const Icon(Icons.straighten, size: 18, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(sizeText!, style: GoogleFonts.almarai(color: Colors.white70)),
                        const SizedBox(width: 12),
                      ],
                      if (createdAt != null) ...[
                        const Icon(Icons.schedule, size: 18, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(createdAt!),
                          style: GoogleFonts.almarai(color: Colors.white70),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }
}
