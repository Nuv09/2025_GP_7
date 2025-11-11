// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';

// ثابت الألوان/القيم المشتركة
import 'constant.dart';

// شاشات التطبيق
import 'saaf_landing_screen.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import 'farms_screen.dart';
import 'add_farm_page.dart';
import 'pages/profilepage.dart';
import 'edit_farm_page.dart';
import 'pages/analysis_status_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ تحميل متغيرات البيئة
  await dotenv.load(fileName: "assets/.env");

  // ✅ تهيئة Firebase
  await _initializeFirebase();

  runApp(const MyApp());
}


// ✅ دالة منفصلة لتهيئة Firebase
Future<void> _initializeFirebase() async {
  try {
    // التحقق إذا كان Firebase مهيأ مسبقاً
    try {
      Firebase.app(); // إذا نجح هذا، значит Firebase مهيأ
      debugPrint('✅ Firebase already initialized');
      return;
    } catch (e) {
      // إذا فشل، نهيئ Firebase
      debugPrint('🔄 Initializing Firebase...');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('✅ Firebase initialized successfully');
    }

    // ✅ تهيئة App Check في الخلفية (بدون انتظار)
    _initializeAppCheckInBackground();
    
  } catch (e) {
    debugPrint('❌ Firebase initialization error: $e');
    // نكمل التشغيل حتى مع فشل Firebase
  }
}

// ✅ تهيئة App Check في الخلفية دون تعطيل التشغيل
void _initializeAppCheckInBackground() {
  Future.delayed(Duration.zero, () async {
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider:
            kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        webProvider: ReCaptchaV3Provider(
          dotenv.env['RECAPTCHA_KEY'] ?? '',
        ),
      );
      debugPrint('✅ App Check initialized');
    } catch (e) {
      debugPrint('⚠️ App Check failed: $e');
      // لا نوقف التطبيق إذا فشل App Check
    }
  });
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
      initialRoute: '/landing',
      routes: {
        '/landing': (_) => const SaafLandingScreen(),
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignUpScreen(),
        '/farms': (_) => const FarmsScreen(),
        '/addFarm': (_) => const AddFarmPage(),
        '/editFarm': (_) => const EditFarmPage(),
        '/pages/profilepage': (_) => const ProfilePage(),
        '/main': (_) => const MainShell(),
        '/analysis': (ctx) {
          final args = ModalRoute.of(ctx)!.settings.arguments as Map?;
          final farmId = (args?['farmId'] ?? '') as String;
          return AnalysisStatusPage(farmId: farmId);
        },
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