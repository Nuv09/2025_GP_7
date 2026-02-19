import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saafapp/constant.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Query<Map<String, dynamic>> _baseQuery() {
    // notifications/{id} where ownerUid == uid
    return FirebaseFirestore.instance
        .collection('notifications')
        .where('ownerUid', isEqualTo: _uid)
        .orderBy('createdAt', descending: true);
  }

  IconData _iconForType(String type, String severity) {
    type = type.toLowerCase();
    severity = severity.toLowerCase();

    if (type.contains('water')) return Icons.water_drop_rounded;
    if (type.contains('stress')) return Icons.opacity_rounded;
    if (type.contains('growth')) return Icons.spa_rounded;
    if (type.contains('forecast')) return Icons.auto_awesome_rounded;
    if (type.contains('current')) return Icons.monitor_heart_rounded;

    // fallback by severity
    if (severity == 'critical') return Icons.warning_rounded;
    if (severity == 'warning') return Icons.error_outline_rounded;
    return Icons.notifications_rounded;
  }

  Color _colorForSeverity(String severity) {
    severity = severity.toLowerCase();
    if (severity == 'critical') return Colors.redAccent;
    if (severity == 'warning') return Colors.orangeAccent;
    return goldColor;
  }

  String _timeLabel(Timestamp? ts) {
    if (ts == null) return "—";
    final dt = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return "الآن";
    if (diff.inMinutes < 60) return "قبل ${diff.inMinutes} دقيقة";
    if (diff.inHours < 24) return "قبل ${diff.inHours} ساعة";
    return "قبل ${diff.inDays} يوم";
  }

  Future<void> _markAsRead(String docId) async {
    await FirebaseFirestore.instance.collection('notifications').doc(docId).update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: darkGreenColor,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildNotificationStream(isRead: false), // الجديدة
                    _buildNotificationStream(isRead: true),  // السابقة
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 25),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "التنبيهات",
                style: GoogleFonts.almarai(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                "متابعة حية لمزارعك",
                style: GoogleFonts.almarai(
                  color: goldColor,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          _backButton(),
        ],
      ),
    );
  }

  Widget _backButton() {
    return InkWell(
      onTap: () => Navigator.pop(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: goldColor,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(color: goldColor.withValues(alpha: 0.3), blurRadius: 10),
          ],
        ),
        labelColor: darkGreenColor,
        unselectedLabelColor: Colors.white54,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: GoogleFonts.almarai(fontWeight: FontWeight.bold),
        tabs: const [
          Tab(text: "الجديدة"),
          Tab(text: "السابقة"),
        ],
      ),
    );
  }

  Widget _buildNotificationStream({required bool isRead}) {
    final uid = _uid;
    if (uid == null) {
      return Center(
        child: Text(
          "يجب تسجيل الدخول لعرض التنبيهات",
          style: GoogleFonts.almarai(color: Colors.white60),
        ),
      );
    }

    final query = _baseQuery().where('isRead', isEqualTo: isRead);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              "حدث خطأ أثناء تحميل التنبيهات",
              style: GoogleFonts.almarai(color: Colors.white60),
            ),
          );
        }

        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: goldColor, strokeWidth: 2),
          );
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text(
              "لا توجد تنبيهات",
              style: GoogleFonts.almarai(color: Colors.white24),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();

            final farmName = (data['farmName'] ?? 'مزرعة').toString();
            final title = (data['title_ar'] ?? 'تنبيه').toString();
            final message = (data['message_ar'] ?? '').toString();
            final type = (data['type'] ?? '').toString();
            final severity = (data['severity'] ?? 'info').toString();
            final createdAt = data['createdAt'] as Timestamp?;

            final col = _colorForSeverity(severity);
            final icon = _iconForType(type, severity);

            return Container(
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: isRead ? Colors.transparent : col.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: col.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                      border: Border.all(color: col.withValues(alpha: 0.30)),
                    ),
                    child: Icon(icon, color: col, size: 24),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                farmName,
                                style: GoogleFonts.almarai(
                                  color: goldColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              _timeLabel(createdAt),
                              style: GoogleFonts.almarai(
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          style: GoogleFonts.almarai(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          message,
                          style: GoogleFonts.almarai(
                            color: Colors.white60,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isRead)
                    IconButton(
                      icon: Icon(Icons.done_all, color: col, size: 20),
                      onPressed: () => _markAsRead(doc.id),
                      tooltip: "وضع كمقروء",
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
