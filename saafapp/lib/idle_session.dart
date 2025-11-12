import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show debugPrint; // 👈 استيراد debugPrint للوضوح

class IdleSessionWrapper extends StatefulWidget {
  final Widget child;
  const IdleSessionWrapper({super.key, required this.child});

  @override
  State<IdleSessionWrapper> createState() => _IdleSessionWrapperState();
}

class _IdleSessionWrapperState extends State<IdleSessionWrapper> {
  // المؤقت: تم ضبطه الآن على دقيقة واحدة للتجربة
  static const Duration _idleTimeout = Duration(minutes: 60);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel(); // إلغاء المؤقت عند إغلاق الـ Widget
    super.dispose();
  }

  // 1. بدأ المؤقت
  void _startTimer() {
    _timer?.cancel(); // نلغي أي مؤقت سابق لضمان وجود مؤقت واحد فقط
    _timer = Timer(_idleTimeout, _onTimeout);
  }

  // 2. إعادة ضبط المؤقت
  void _handleUserInteraction([_]) {
    if (mounted) {
      // إعادة تشغيل المؤقت في كل تفاعل
      _startTimer();
    }
  }

  // 3. انتهاء مدة الخمول (دقيقة واحدة)
  void _onTimeout() async {
    // 🟢 أوامر طباعة للتحقق من وصولنا إلى هنا 🟢
    debugPrint('⏳ المؤقت (1 دقيقة) انتهى. جاري تنفيذ عملية تسجيل الخروج...');

    // 4. تنفيذ عملية تسجيل الخروج
    await FirebaseAuth.instance.signOut();

    debugPrint('✅ تم تسجيل الخروج من Firebase Auth بنجاح');

    // توجيه المستخدم لصفحة تسجيل الدخول (استبدلي '/login' بالـ Route المناسب)
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // نستخدم GestureDetector لتغطية الشاشة بأكملها والتقاط أي حركة
    return GestureDetector(
      onTap: _handleUserInteraction, // يلتقط النقرات
      onPanDown: _handleUserInteraction, // يلتقط السحب
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}
