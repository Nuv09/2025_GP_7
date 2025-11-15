import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

const Color kDeepGreen = Color(0xFF042C25);
const Color kLightBeige = Color(0xFFFFF6E0);
const Color kOrange = Color(0xFFEBB974);

class AnalysisStatusPage extends StatelessWidget {
  final String farmId;
  const AnalysisStatusPage({super.key, required this.farmId});

  void _goHome(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(context, '/main', (_) => false);
  }

  void _scheduleAutoNav(BuildContext context) {
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (context.mounted) _goHome(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final docRef = FirebaseFirestore.instance.collection('farms').doc(farmId);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kDeepGreen,
        appBar: AppBar(
          backgroundColor: kDeepGreen,
          elevation: 0,
          centerTitle: true,
          title: Text(
            'تحليل المزرعة',
            style: GoogleFonts.almarai(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => _goHome(context),
          ),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: docRef.snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const _LoadingView();
            }
            final data = snap.data!.data() as Map<String, dynamic>? ?? {};
            final status = (data['status'] ?? 'pending') as String;
            final finalCount = (data['finalCount'] ?? 0) as int;
            final err = (data['errorMessage'] ?? '') as String?;

            if (status == 'done') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scheduleAutoNav(context);
              });
              return _DoneView(count: finalCount);
            }

            if (status == 'failed' || status == 'error') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scheduleAutoNav(context);
              });
              return _ErrorView(message: err ?? 'تعذّر التحليل');
            }

            return const _LoadingView();
          },
        ),
      ),
    );
  }
}

// ===================== شاشة الانتظار =====================
class _LoadingView extends StatefulWidget {
  const _LoadingView();

  @override
  State<_LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<_LoadingView> {
  late final Timer _timer;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      setState(() => _step = (_step + 1) % 4);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.of(context).size;
    final baseStyle = GoogleFonts.almarai(
      color: Colors.white70,
      fontSize: 18,
      height: 1.6,
      fontWeight: FontWeight.w600,
    );

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ لوتي كبيرة ومتمركزة
          SizedBox(
            width: s.width * 0.8,
            height: s.height * 0.45,
            child: Image.asset(
              'assets/gif/loading.gif',
              width: 200,
              height: 200,
            ),
          ),
          const SizedBox(height: 30),

          // ✅ نص ثابت ونقاط شفافة تتحرك بهدوء
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('سَعَف يتفحص نخيلك بعناية', style: baseStyle),
              const SizedBox(width: 8),
              SizedBox(
                width: 30,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(3, (i) {
                    final visible = _step > i;
                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: visible ? 1.0 : 0.2,
                      child: Text('·', style: baseStyle),
                    );
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===================== تم =====================
class _DoneView extends StatelessWidget {
  final int count;
  const _DoneView({required this.count});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 90, color: kOrange),
          const SizedBox(height: 12),
          Text(
            'النتيجة جاهزة!',
            style: GoogleFonts.almarai(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'عدد النخيل التقريبي: $count',
            style: GoogleFonts.almarai(color: Colors.white70, fontSize: 18),
          ),
        ],
      ),
    );
  }
}

// ===================== خطأ =====================
class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 90, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(
            'تعذّر إتمام التحليل',
            style: GoogleFonts.almarai(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.almarai(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
