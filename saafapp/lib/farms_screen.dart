import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saafapp/constant.dart';
import 'widgets/farms/farms_body.dart';
import 'saaf_landing_screen.dart'; // <<< ADD

// لو تستعملين راوت بالاسم '/addFarm' خليه بدون استيراد الصفحة.
// وإلا استوردي الصفحة المباشرة:
// import '../add_farm_page.dart';

class FarmsScreen extends StatelessWidget {
  const FarmsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkGreenColor,
      appBar: farmsAppBar(context), // مررنا context عشان الـ Navigator
      body: FarmsBody(), // ✅ رجّعنا نفس الـ body القديم
      // bottomNavigationBar: bottomnavbar(),
    );
  }

  // --- REPLACE: farmsAppBar بالكامل ---
  AppBar farmsAppBar(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false, // ما نبي سهم رجوع
      elevation: 0,
      backgroundColor: darkGreenColor,
      title: Row(
        textDirection: TextDirection.ltr,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 48), // فراغ يسار عشان العنوان يبقى بالنص
          Text(
            "مزارعي  ",
            style: GoogleFonts.almarai(
              // <<< CHANGED
              color: whiteColor,
              fontWeight: FontWeight.w700,
              fontSize: Theme.of(context).textTheme.titleLarge?.fontSize ?? 20,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'العودة لصفحة البداية',
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const SaafLandingScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}
