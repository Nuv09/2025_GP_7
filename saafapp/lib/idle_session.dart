import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/foundation.dart'
  //  show debugPrint; // 👈 استيراد debugPrint للوضوح

class IdleSessionWrapper extends StatefulWidget {
  final Widget child;
  const IdleSessionWrapper({super.key, required this.child});

  @override
  State<IdleSessionWrapper> createState() => _IdleSessionWrapperState();
}

// 🛑 إضافة Mixin WidgetsBindingObserver
class _IdleSessionWrapperState extends State<IdleSessionWrapper>
    with WidgetsBindingObserver {
  static const Duration _idleTimeout = Duration(minutes: 60);
  Timer? _timer;
  bool _loggedOut = false; // لمنع تسجيل الخروج المتعدد

  @override
  void initState() {
    super.initState();
    // 🛑 ربط مراقب دورة حياة التطبيق
    WidgetsBinding.instance.addObserver(this);
    _resetTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // 🛑 فك ربط المراقب
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 🔑 دالة مراقبة حالة التطبيق (الذهاب للخلفية والعودة)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_loggedOut) return;

    if (state == AppLifecycleState.paused) {
      // ⏸️ التطبيق ذهب للخلفية: إلغاء المؤقت تماماً (لا يُحتسب كخمول)
      _timer?.cancel();
      debugPrint('⏸️ ذهب التطبيق للخلفية. تم إلغاء المؤقت.');
    } else if (state == AppLifecycleState.resumed) {
      // ▶️ التطبيق عاد للمقدمة: إعادة تشغيل المؤقت من البداية (60 دقيقة)
      _resetTimer();
      debugPrint('🔄 عاد التطبيق للمقدمة. تم إعادة تشغيل المؤقت إلى 60 دقيقة.');
    }
  }

  void _resetTimer() {
    _timer?.cancel();
    if (_loggedOut) return;
    _timer = Timer(_idleTimeout, _logoutUser);
  }

  void _handleUserInteraction([_]) {
    if (!_loggedOut && mounted) {
      _resetTimer();
    }
  }

  Future<void> _logoutUser() async {
    if (_loggedOut) return;
    _loggedOut = true;
    _timer?.cancel();

    await FirebaseAuth.instance.signOut();

    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
        arguments: {
          'session_expired': true,
          'message': 'تم تسجيل خروجك تلقائيًا بعد ساعة من الخمول.',
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleUserInteraction,
      onPanDown: _handleUserInteraction,
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}
