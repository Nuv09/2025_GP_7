// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// ثابت الألوان/القيم المشتركة
import 'constant.dart';

// شاشاتك
import 'saaf_landing_screen.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import 'farms_screen.dart';
import 'add_farm_page.dart';
import 'pages/profilepage.dart';
import 'edit_farm_page.dart'; // جديد

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Saaf',
      localizationsDelegates: const [
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', 'SA'), Locale('en')],
      locale: const Locale('ar', 'SA'),
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: darkGreenColor,
        scaffoldBackgroundColor: darkGreenColor,
        textTheme: GoogleFonts.almaraiTextTheme(Theme.of(context).textTheme),
        appBarTheme: const AppBarTheme(
          backgroundColor: darkGreenColor,
          foregroundColor: whiteColor,
          centerTitle: true,
          elevation: 0,
        ),
        colorScheme: const ColorScheme.dark(
          primary: darkGreenColor,
          surface: darkGreenColor,
          onSurface: whiteColor,
        ),
      ),

      // 👇 نعرض اللاندنق أولًا
      initialRoute: '/landing',
      routes: {
        '/landing': (_) => const SaafLandingScreen(),
        '/login':   (_) => const LoginScreen(),
        '/signup':  (_) => const SignUpScreen(),
        '/farms':   (_) => const FarmsScreen(),
        '/addFarm': (_) => const AddFarmPage(),
        '/editFarm':(_) => const EditFarmPage(), // جديد
        '/pages/profilepage': (_) => const ProfilePage(),
        '/main':    (_) => const MainShell(),
      },
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
        color: beige,
        backgroundColor: darkGreenColor,
        animationDuration: const Duration(milliseconds: 300),
        index: _index,
        items: const [
          Icon(Icons.home, size: 30, color: goldColor),
          Icon(Icons.add, size: 30, color: goldColor),
          Icon(Icons.person, size: 30, color: goldColor),
        ],
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
