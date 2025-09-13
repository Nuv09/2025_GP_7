import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';

// ثابت الألوان/القيم المشتركة
import 'constant.dart';

// شاشاتك
import 'saaf_landing_screen.dart'; // شاشة اللاندنق
import 'login_screen.dart'; // شاشة تسجيل الدخول
import 'signup_screen.dart'; // شاشة إنشاء الحساب

// شاشة صديقتك الثانية (المزارع/الرئيسية)
import 'farms_screen.dart'; // تأكدي من الاسم/الحروف

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
          foregroundColor: whiteColor,
          centerTitle: true,
          elevation: 0,
        ),
        colorScheme: ColorScheme.dark(
          primary: darkGreenColor,
          surface: darkGreenColor,
          onSurface: whiteColor,
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

// ==================== MainShell ====================
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  // صفحات التبويبات داخل البار (نفس ترتيب الأيقونات تحت)
  final List<Widget> _pages = const [
    FarmsScreen(), // 0: Home
    AddFarmPage(), // 1: Add
    ProfilePage(), // 2: Profile
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _pages),

      bottomNavigationBar: CurvedNavigationBar(
        height: 70,
        color: beige, // من constant.dart
        backgroundColor: darkGreenColor,
        animationDuration: Duration(milliseconds: 300),
        index: _index,
        items: const [
          Icon(Icons.home, size: 30, color: goldColor), // Home
          Icon(Icons.add, size: 30, color: goldColor), // add
          Icon(Icons.person, size: 30, color: goldColor), // Profile
        ],
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
