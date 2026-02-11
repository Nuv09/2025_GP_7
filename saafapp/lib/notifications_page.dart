import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saafapp/constant.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // بيانات وهمية مرتبطة بمزارع "سعف"
  final List<Map<String, dynamic>> _notifications = [
    {
      "id": "1",
      "farm": "مزرعة النخيل (أ)",
      "msg": "تحتاج زيادة ري",
      "desc": "نسبة الرطوبة انخفضت بشكل ملحوظ في القطاع الشرقي",
      "time": "الآن",
      "type": "water",
      "isRead": false,
    },
    {
      "id": "2",
      "farm": "بيت المحمية (ب)",
      "msg": "تحذير حرارة",
      "desc": "درجة الحرارة تجاوزت الـ 40 درجة، يرجى تشغيل التهوية",
      "time": "قبل ساعة",
      "type": "temp",
      "isRead": false,
    },
    {
      "id": "3",
      "farm": "مزرعة السدر",
      "msg": "اكتمل التسميد",
      "desc": "تم إتمام عملية التسميد الدوري بنجاح لجميع الأشجار",
      "time": "أمس",
      "type": "success",
      "isRead": true,
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
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
                  _buildNotificationList(false), // الجديدة
                  _buildNotificationList(true),  // السابقة
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
              Text("التنبيهات ", 
                style: GoogleFonts.almarai(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
              Text("متابعة حية لمزارعك", 
                style: GoogleFonts.almarai(color: goldColor, fontSize: 13, letterSpacing: 1.2)),
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
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
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
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: goldColor,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: goldColor.withOpacity(0.3), blurRadius: 10)],
        ),
        labelColor: darkGreenColor,
        unselectedLabelColor: Colors.white54,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: GoogleFonts.almarai(fontWeight: FontWeight.bold),
        tabs: const [Tab(text: "الجديدة"), Tab(text: "السابقة")],
      ),
    );
  }

  Widget _buildNotificationList(bool isRead) {
    final list = _notifications.where((n) => n['isRead'] == isRead).toList();
    if (list.isEmpty) {
      return Center(child: Text("لا توجد تنبيهات", style: GoogleFonts.almarai(color: Colors.white24)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: item['isRead'] ? Colors.transparent : goldColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              _buildLeadingIcon(item['type']),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['farm'], style: GoogleFonts.almarai(color: goldColor, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(item['msg'], style: GoogleFonts.almarai(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(item['desc'], style: GoogleFonts.almarai(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
              if (!item['isRead']) 
                IconButton(
                  icon: Icon(Icons.done_all, color: goldColor, size: 20),
                  onPressed: () => setState(() => item['isRead'] = true),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeadingIcon(String type) {
    IconData icon = Icons.notifications;
    Color col = goldColor;
    if (type == 'water') { icon = Icons.water_drop; col = Colors.blueAccent; }
    if (type == 'temp') { icon = Icons.wb_sunny; col = Colors.orangeAccent; }
    if (type == 'success') { icon = Icons.check_circle; col = Colors.greenAccent; }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: col.withOpacity(0.1), shape: BoxShape.circle),
      child: Icon(icon, color: col, size: 24),
    );
  }
}