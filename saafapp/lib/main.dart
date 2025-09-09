import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
//hello latefa2
// ثابت الألوان/القيم المشتركة
import 'constant.dart';

// شاشاتك
import 'saaf_landing_screen.dart'; // شاشة اللاندنق
import 'login_screen.dart'; // شاشة تسجيل الدخول
import 'signup_screen.dart'; // شاشة إنشاء الحساب

// شاشة صديقتك الثانية (المزارع/الرئيسية)
import 'farms_Screen.dart'; // تأكدي من الاسم/الحروف

// شاشة صديقتك الثالثة (إضافة مزرعة)
import 'add_farm_page.dart'; // أو package:saaf_add_farm/add_farm_page.dart

// شاشة صديقتكم الرابعة (البروفايل)
import 'pages/profilepage.dart'; // <-- عدّلي المسار لو مختلف

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Saaf',

      // 🇸🇦 تفعيل العربية
      localizationsDelegates: const [
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', 'SA'), Locale('en')],
      locale: const Locale('ar', 'SA'),

      // 🎨 ثيم موحّد
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: darkGreenColor, // من constant.dart
        scaffoldBackgroundColor: darkGreenColor,
        textTheme: GoogleFonts.almaraiTextTheme(Theme.of(context).textTheme),
        appBarTheme: const AppBarTheme(
          backgroundColor: darkGreenColor,
          foregroundColor: WhiteColor,
          centerTitle: true,
          elevation: 0,
        ),
        colorScheme: ColorScheme.dark(
          primary: darkGreenColor,
          surface: darkGreenColor,
          onSurface: WhiteColor,
        ),
      ),

      // 🧭 الراوتس
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignUpScreen(),
        '/farms': (_) => const FarmsScreen(),
        '/addFarm': (_) => const AddFarmPage(),
        '/pages/profilepage': (_) => const ProfilePage(), // <-- جديد
        '/main': (_) => const MainShell(),
      },

      // 🚀 شاشة البداية
      home: const SaafLandingScreen(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  // الصفحات داخل الـ Bottom Nav
  final List<Widget> _pages = const [
    FarmsScreen(), // الرئيسية/قائمة المزارع
    AddFarmPage(), // إضافة مزرعة
    ProfilePage(), // البروفايل (بدل Placeholder)
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: CurvedNavigationBar(
        height: 70,
        color: Beige, // من constant.dart
        backgroundColor: darkGreenColor,
        animationDuration: const Duration(milliseconds: 300),
        index: _index,
        items: const [
          Icon(Icons.home, size: 30), // Farms
          Icon(Icons.add_home, size: 30), // Add Farm
          Icon(Icons.person, size: 30), // Profile
        ],
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
