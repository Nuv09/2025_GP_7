// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
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
import 'idle_session.dart';
import 'about_us.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:saafapp/notifications_page.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    Firebase.app();
  } catch (_) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة Firebase
  await _initializeFirebase();
  await _initializeFCM();


  runApp(const MyApp());
}

// ======================== Firebase Init ========================

Future<void> _initializeFirebase() async {
  try {
    // لو Firebase جاهز مسبقاً
    try {
      Firebase.app();
      debugPrint('✅ Firebase already initialized');
    } catch (_) {
      // لو مو جاهز → نهيئه
      debugPrint('🔄 Initializing Firebase...');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('✅ Firebase initialized successfully');
    }

    // تهيئة App Check في الخلفية
    _initializeAppCheckInBackground();
  } catch (e) {
    debugPrint('❌ Firebase initialization error: $e');
  }
}

// ======================== App Check ========================

void _initializeAppCheckInBackground() {
  Future.delayed(Duration.zero, () async {
    try {
      if (kIsWeb) {
        // الويب → نستعمل Recaptcha V3 بدون env
        await FirebaseAppCheck.instance.activate(
          webProvider: ReCaptchaV3Provider(
            "6LeCJgQsAAAAAItp5qD11GdE0wNEHNGLk22m74wO",
          ),
        );
      } else {
        // الجوال
        await FirebaseAppCheck.instance.activate(
          androidProvider: kDebugMode
              ? AndroidProvider.debug
              : AndroidProvider.playIntegrity,
          appleProvider: AppleProvider.appAttest,
        );
      }

      debugPrint('✅ App Check initialized');
    } catch (e) {
      debugPrint('⚠️ App Check failed: $e');
    }
  });
}


Future<void> _initializeFCM() async {
  try {
    // ✅ تسجيل الهاندلر للخلفية (Android/iOS)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;

    // ✅ طلب الإذن (مهم خصوصاً iOS)
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

  
    await _saveFcmTokenIfLoggedIn();

    

    // ✅ لو تغير التوكن لاحقاً
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await _saveFcmTokenIfLoggedIn(forcedToken: newToken);
    });

    // ✅ إذا المستخدم ضغط على الإشعار وفتح التطبيق
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const NotificationsPage()),
      );
    });

    // ✅ لو التطبيق كان مقفّل بالكامل وانفتح من إشعار
    final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMsg != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const NotificationsPage()),
        );
      });
    }
  } catch (e) {
    debugPrint("⚠️ FCM init failed: $e");
  }
}

Future<void> _saveFcmTokenIfLoggedIn({String? forcedToken}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final token = forcedToken ?? await FirebaseMessaging.instance.getToken();
  if (token == null || token.isEmpty) return;

  await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
    'fcmToken': token,
    'fcmUpdatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

// ======================== MyApp ========================

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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
        '/about': (_) => const AboutUsPage(),
        '/pages/profilepage': (_) => const ProfilePage(),
        '/main': (_) => const IdleSessionWrapper(child: MainShell()),
        '/notifications': (_) => const NotificationsPage(),
        '/analysis': (ctx) {
          final args = ModalRoute.of(ctx)!.settings.arguments as Map?;
          final farmId = (args?['farmId'] ?? '') as String;
          return AnalysisStatusPage(farmId: farmId);
        },
      },
    );
  }
}

// ======================== MainShell ========================

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final List<Widget> _pages = const [
    FarmsScreen(),
    AddFarmPage(),
    ProfilePage(),
    AboutUsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: CurvedNavigationBar(
        height: 65,
        color:const Color(0xFFEADEC4),
        backgroundColor: darkGreenColor,
        animationDuration: const Duration(milliseconds: 300),
        index: _index,
items: [
  _navItem(Icons.home, "مزارعي", _index == 0),
  _navItem(Icons.add, "إضافة", _index == 1),
  _navItem(Icons.person, "ملفي", _index == 2),
  _navItem(Icons.info_outline, "عن سعف", _index == 3),
],

        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
Widget _navItem(IconData icon, String label, bool active) {
  return Padding(
    padding: const EdgeInsets.only(top: 4), // 🔥 هنا نزلنا العناصر تحت
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: active ? 33 : 29,
          color: goldColor,
        ),

        AnimatedOpacity(
          duration: Duration(milliseconds: 200),
          opacity: active ? 1.0 : 0.0,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Text(
              label,
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w900, // أثقل خط
                fontSize: 12,
                color: goldColor,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
