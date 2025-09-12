import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saafapp/constant.dart';
import 'widgets/farms/farms_body.dart';

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
      body: farmsBody(), // ✅ رجّعنا نفس الـ body القديم
      // bottomNavigationBar: bottomnavbar(),
    );
  }

  AppBar farmsAppBar(BuildContext context) {
    return AppBar(
      elevation: 0,
      title: Text(
        "مزارعي : ",
        style: GoogleFonts.getFont(
          "Almarai",
          textStyle: const TextStyle(color: WhiteColor),
        ),
      ),
      centerTitle: false,
      backgroundColor: darkGreenColor,

      // زر الإضافة
      actions: [
        IconButton(
          icon: const Icon(Icons.add, color: WhiteColor),
          onPressed: () {
            // لو مفعّلين راوت بالاسم:
            Navigator.pushNamed(context, '/pages/profilepage');

            // أو لو بتفتحين الصفحة مباشرة (ألغِ السطر فوق وفعّلي هذا):
            // Navigator.push(context, MaterialPageRoute(builder: (_) => const AddFarmPage()));
          },
        ),
      ],
    );
  }
}
