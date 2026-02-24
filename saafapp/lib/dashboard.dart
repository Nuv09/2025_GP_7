import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:saafapp/constant.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:saafapp/secrets.dart';
import 'package:flutter_map/flutter_map.dart'; // سنترك هذه كما هي لأننا نستخدمها بكثرة هنا
import 'package:latlong2/latlong.dart'; // سنتركها أيضاً
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// خريطة جوجل نعطيها اسماً مستعاراً (gmaps) لكي لا تتدخل في هذه الصفحة

class FarmDashboardPage extends StatefulWidget {
  final Map<String, dynamic> farmData;
  final String farmId;

  const FarmDashboardPage({
    super.key,
    required this.farmData,
    required this.farmId,
  });

  @override
  State<FarmDashboardPage> createState() => _FarmDashboardPageState();
}

class _FarmDashboardPageState extends State<FarmDashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isForecastMode = false; // التحكم في وضع الخريطة (حالي / توقعات)

  // متغيرات الطقس
  String temp = "--";
  String weatherDesc = "جاري التحميل...";
  bool isLoadingWeather = true;

  String _formatLastAnalysisDate() {
    final raw = widget.farmData['lastAnalysisAt'];

    if (raw == null) return "—";

    try {
      DateTime dt;

      // Firestore Timestamp
      if (raw.runtimeType.toString() == 'Timestamp') {
        dt = raw.toDate();
      }
      // milliseconds
      else if (raw is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(raw);
      }
      // String
      else if (raw is String) {
        dt = DateTime.parse(raw);
      } else {
        return "—";
      }

      // التاريخ فقط بدون الوقت
      return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
    } catch (_) {
      return "—";
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    try {
      final List<dynamic> polygon = widget.farmData['polygon'] ?? [];

      if (polygon.isEmpty) {
        if (mounted) {
          setState(() {
            temp = "--";
            weatherDesc = "موقع المزرعة غير متوفر";
            isLoadingWeather = false;
          });
        }
        return;
      }

      double sumLat = 0;
      double sumLon = 0;
      for (var point in polygon) {
        sumLat += double.tryParse(point['lat'].toString()) ?? 0.0;
        sumLon += double.tryParse(point['lng'].toString()) ?? 0.0;
      }
      double lat = sumLat / polygon.length;
      double lon = sumLon / polygon.length;

      final String apiKey = Secrets.weatherApiKey;
      final url = Uri.parse(
        'https://api.weatherapi.com/v1/current.json?key=$apiKey&q=$lat,$lon&lang=ar',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            temp = "${data['current']['temp_c'].toInt()}°C";
            weatherDesc = data['current']['condition']['text'];
            isLoadingWeather = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            temp = "--";
            weatherDesc = "تعذر تحديث البيانات";
            isLoadingWeather = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          temp = "--";
          weatherDesc = "تأكد من الاتصال بالإنترنت";
          isLoadingWeather = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  IconData _getWeatherIcon(String desc) {
    if (desc.contains("صافي") ||
        desc.contains("مشمس") ||
        desc.contains("صحو")) {
      return Icons.wb_sunny_rounded;
    } else if (desc.contains("غائم") || desc.contains("سحب")) {
      return Icons.wb_cloudy_rounded;
    } else if (desc.contains("مطر") || desc.contains("زخات")) {
      return Icons.umbrella_rounded;
    } else if (desc.contains("غبار") || desc.contains("عاصفة")) {
      return Icons.air_rounded;
    } else {
      return Icons.wb_cloudy_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: darkGreenColor,
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.7, -0.8),
                  radius: 1.8,
                  colors: [const Color(0xFF0A4D41), darkGreenColor],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildModernHeader(),
                  _buildFloatingTabBar(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildMapSection(),
                        _buildGeneralInfoSection(),
                        _buildRecommendationsSection(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderExportIcon() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _showExportOptions, // ✅ هنا
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: goldColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.ios_share_rounded, color: goldColor, size: 18),
            const SizedBox(width: 8),
            Text(
              "تصدير",
              style: GoogleFonts.almarai(
                color: goldColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: darkGreenColor.withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "تصدير التقرير",
                style: GoogleFonts.almarai(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),

              _exportTile(
                icon: Icons.picture_as_pdf_rounded,
                title: "PDF",
                subtitle: "مناسب للإرسال والاعتماد",
                onTap: () async {
                  Navigator.pop(ctx);
                  await _exportPdf();
                },
              ),
              const SizedBox(height: 10),
              _exportTile(
                icon: Icons.table_chart_rounded,
                title: "Excel",
                subtitle: "مناسب للتحليل والتعديل",
                onTap: () async {
                  Navigator.pop(ctx);
                  await _exportExcel();
                },
              ),

              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Widget _exportTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: goldColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: goldColor.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, color: goldColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.almarai(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.almarai(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_left_rounded, color: Colors.white60),
          ],
        ),
      ),
    );
  }

  void _showLoading(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: darkGreenColor.withValues(alpha: 0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: goldColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(msg, style: GoogleFonts.almarai(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.almarai()),
        backgroundColor: const Color(0xFF0A4D41),
      ),
    );
  }

  Future<void> _exportPdf() async {
    try {
      _showLoading("جاري تجهيز PDF...");

      final uri = Uri.parse(
        "${Secrets.apiBaseUrl}/reports/${widget.farmId}/pdf",
      );

      final res = await http
          .post(
            uri,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              // خطوة 1: نرسل farmData نفسها للسيرفر
              "farmData": widget.farmData,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (res.statusCode != 200) {
        _toast("تعذر إنشاء التقرير");
        return;
      }

      final data = jsonDecode(res.body);
      final String b64 = data["base64"] ?? "";
      final String fileName = data["fileName"] ?? "report.pdf";

      if (b64.isEmpty) {
        _toast("التقرير رجع فاضي");
        return;
      }

      final bytes = base64Decode(b64);

      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/$fileName");
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles([XFile(file.path)], text: "تقرير المزرعة (PDF)");
    } catch (e) {
      if (mounted) {
        try {
          Navigator.pop(context);
        } catch (_) {}
        _toast("حدث خطأ تأكد من الاتصال");
      }
    }
  }

  Future<void> _exportExcel() async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Excel قريباً", style: GoogleFonts.almarai()),
        backgroundColor: const Color(0xFF0A4D41),
      ),
    );
  }

  void _onExportPressed() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "ميزة تصدير التقارير ستكون متاحة قريباً",
          style: GoogleFonts.almarai(),
        ),
        backgroundColor: const Color(0xFF0A4D41),
      ),
    );
  }

  Widget _buildModernHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // النصوص (اسم المزرعة + آخر تحليل)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.farmData['farmName'] ?? 'المزرعة',
                style: GoogleFonts.almarai(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                "التحليل الذكي للمزرعة",
                style: GoogleFonts.almarai(color: goldColor, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                "آخر تحليل: ${_formatLastAnalysisDate()}",
                style: GoogleFonts.almarai(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          // أزرار اليمين (تصدير + رجوع) ✅ ثابتة دائمًا
          Row(
            children: [
              _buildHeaderExportIcon(),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 18,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      height: 75,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: goldColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: goldColor.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: goldColor,
        unselectedLabelColor: Colors.white38,
        labelStyle: GoogleFonts.almarai(
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        tabs: const [
          Tab(icon: Icon(Icons.map_outlined), text: "الخريطة"),
          Tab(icon: Icon(Icons.grid_view_rounded), text: "الحالة"),
          Tab(icon: Icon(Icons.auto_awesome_outlined), text: "الوقايه والتنبؤ"),
        ],
      ),
    );
  }

  Widget _buildMapSection() {
    final List<dynamic> polygonData = widget.farmData['polygon'] ?? [];
    final List<LatLng> points = polygonData.map((point) {
      return LatLng(
        (point['lat'] as num).toDouble(),
        (point['lng'] as num).toDouble(),
      );
    }).toList();

    LatLng center = points.isNotEmpty
        ? points[0]
        : const LatLng(24.7136, 46.6753);

    final List<dynamic> healthMapPoints = widget.farmData['healthMap'] ?? [];
    String areaValue = widget.farmData['farmSize']?.toString() ?? 'غير محدد';

    return Container(
      margin: const EdgeInsets.all(20),
      height: 400,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 1. الطبقة الأساسية: الخريطة
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: FlutterMap(
              options: MapOptions(initialCenter: center, initialZoom: 17),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://api.maptiler.com/maps/hybrid/{z}/{x}/{y}.jpg?key=${Secrets.mapTilerKey}',
                  userAgentPackageName: 'com.example.saafapp',
                ),
                CircleLayer(
                  circles: healthMapPoints.map((point) {
                    // التبديل بين s (الحالي) و ps (المتوقع) بناءً على الزر فقط
                    final int status = _isForecastMode
                        ? (point['ps'] ?? 0)
                        : (point['s'] ?? 0);

                    final baseColor = _getHealthColor(status);

                    return CircleMarker(
                      point: LatLng(
                        (point['lat'] as num).toDouble(),
                        (point['lng'] as num).toDouble(),
                      ),
                      color: baseColor.withValues(alpha: 0.7),
                      borderColor: baseColor,
                      borderStrokeWidth: 2,
                      radius: 7,
                      useRadiusInMeter: true,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // 2. التظليل العلوي للعنوان (تم نقله ليكون تحت الزر)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Text(
                "تحليل الصحة النباتية",
                style: GoogleFonts.almarai(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // 3. بطاقات المعلومات العائمة السفلى
          Positioned(
            bottom: 20,
            right: 15,
            left: 15,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: darkGreenColor.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildMapLegendItem("سليم", Colors.greenAccent),
                        _buildMapLegendItem("مشتبه به", Colors.orangeAccent),
                        _buildMapLegendItem("مصاب", Colors.redAccent),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: darkGreenColor.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: goldColor.withValues(alpha: 0.4)),
                  ),
                  child: _buildMapMiniStat(
                    Icons.square_foot_rounded,
                    "المساحة",
                    "$areaValue م²",
                  ),
                ),
              ],
            ),
          ),

          // 4. زر التبديل (تم وضعه في النهاية ليكون هو الأعلى وقابل لللمس)
          Positioned(
            top: 15,
            left: 15,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: darkGreenColor.withOpacity(0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: goldColor.withOpacity(0.3)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isForecastMode ? "وضع التنبؤ" : "الوضع الحالي",
                    style: GoogleFonts.almarai(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: _isForecastMode,
                      activeColor: goldColor,
                      onChanged: (val) {
                        setState(() {
                          _isForecastMode = val;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // دالة بناء عناصر المفتاح
  Widget _buildMapLegendItem(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.almarai(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // دالة مساعدة لتحديد لون النقطة بناءً على الحالة
  Color _getHealthColor(int status) {
    switch (status) {
      case 2:
        return const Color.fromARGB(87, 244, 67, 54); // مصاب
      case 1:
        return const Color.fromARGB(62, 255, 235, 59); // مراقبة
      case 0:
        return const Color.fromARGB(150, 105, 240, 123); // سليم
      default:
        return Colors.transparent;
    }
  }

  Widget _buildMapMiniStat(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: goldColor, size: 14),
        const SizedBox(width: 8),
        Text(
          "$label: ",
          style: GoogleFonts.almarai(color: Colors.white70, fontSize: 10),
        ),
        Text(
          value,
          style: GoogleFonts.almarai(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  //الحاله
  Widget _buildGeneralInfoSection() {
    final healthRoot =
        (widget.farmData['health'] as Map?)?.cast<String, dynamic>() ?? {};
    final current =
        (healthRoot['current_health'] as Map?)?.cast<String, dynamic>() ?? {};

    final double healthy =
        double.tryParse("${current['Healthy_Pct']}") ??
        (current['Healthy_Pct'] as num?)?.toDouble() ??
        0.0;
    final double monitor =
        double.tryParse("${current['Monitor_Pct']}") ??
        (current['Monitor_Pct'] as num?)?.toDouble() ??
        0.0;
    final double critical =
        double.tryParse("${current['Critical_Pct']}") ??
        (current['Critical_Pct'] as num?)?.toDouble() ??
        0.0;

    final int totalPalms = widget.farmData['finalCount'] is int
        ? widget.farmData['finalCount']
        : int.tryParse(widget.farmData['finalCount']?.toString() ?? '0') ?? 0;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        children: [
          _buildWeatherCard(),
          const SizedBox(height: 20),
          _buildHealthStatsCard(totalPalms, healthy, monitor, critical),
          const SizedBox(height: 20),
          _buildHistoryChart(),
          const SizedBox(height: 100), // مسافة إضافية لراحة التمرير
        ],
      ),
    );
  }

  Widget _buildWeatherCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "الطقس الآن",
                style: GoogleFonts.almarai(color: goldColor, fontSize: 14),
              ),
              const SizedBox(height: 5),
              isLoadingWeather
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: goldColor,
                      ),
                    )
                  : Text(
                      temp,
                      style: GoogleFonts.almarai(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
              Text(
                isLoadingWeather ? "جاري التحديث..." : weatherDesc,
                style: GoogleFonts.almarai(color: Colors.white60, fontSize: 13),
              ),
            ],
          ),
          Icon(_getWeatherIcon(weatherDesc), color: Colors.white70, size: 50),
        ],
      ),
    );
  }

  Widget _buildHealthStatsCard(int total, double h, double m, double c) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Text(
            "تحليل حالة النخيل",
            style: GoogleFonts.almarai(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sectionsSpace: 4,
                centerSpaceRadius: 40,
                sections: [
                  PieChartSectionData(
                    value: h,
                    color: Colors.greenAccent,
                    radius: 22,
                    showTitle: false,
                  ),
                  PieChartSectionData(
                    value: m,
                    color: Colors.orangeAccent,
                    radius: 20,
                    showTitle: false,
                  ),
                  PieChartSectionData(
                    value: c,
                    color: Colors.redAccent,
                    radius: 18,
                    showTitle: false,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildLegendItem("سليم", Colors.greenAccent, h),
          _buildLegendItem("مشتبه به", Colors.orangeAccent, m),
          _buildLegendItem("مصاب", Colors.redAccent, c),
          const Divider(color: Colors.white10, height: 30),
          Text(
            "إجمالي النخيل: $total",
            style: GoogleFonts.almarai(
              color: goldColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryChart() {
    final Map<String, dynamic> healthRoot =
        (widget.farmData['health'] as Map?)?.cast<String, dynamic>() ?? {};

    final List<dynamic> history =
        (healthRoot['indices_history_last_month'] as List?) ?? [];

    if (history.isEmpty) {
      return Container(
        height: 340,
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Center(
          child: Text(
            "لا توجد بيانات كافية لهذا الشهر",
            style: GoogleFonts.almarai(color: Colors.white70, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      height: 400,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 25, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Text(
              "مقارنة المؤشرات الأسبوعية",
              style: GoogleFonts.almarai(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 30),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 100,
                minY: 0,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) =>
                        Colors.blueGrey.withValues(alpha: 0.9),
                    tooltipPadding: const EdgeInsets.all(8),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      String suffix = rodIndex == 0
                          ? "مؤشر الغطاء النباتي"
                          : rodIndex == 1
                          ? "مؤشر الرطوبة"
                          : "مؤشر الكلوروفيل";
                      return BarTooltipItem(
                        "$suffix\n${rod.toY.toStringAsFixed(1)}%",
                        GoogleFonts.almarai(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  // --- المحور السفلي (التواريخ MM-DD) ---
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        int i = value.toInt();
                        if (i >= 0 && i < history.length) {
                          String fullDate = history[i]['date'] as String;
                          String shortDate = fullDate.substring(5, 10);
                          return SideTitleWidget(
                            meta: meta, // تمرير المتغير المطلوب لإصلاح الإيرور
                            space: 10,
                            child: Text(
                              shortDate,
                              style: GoogleFonts.almarai(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  // --- المحور الجانبي (النسب المئوية) ---
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      interval: 20,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        return SideTitleWidget(
                          meta: meta, // تمرير المتغير المطلوب لإصلاح الإيرور
                          space: 8,
                          child: Text(
                            "${value.toInt()}%",
                            style: GoogleFonts.almarai(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 20,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withValues(alpha: 0.08),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(history.length, (i) {
                  final item = history[i] as Map;
                  return BarChartGroupData(
                    x: i,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: ((item['NDVI'] as num?)?.toDouble() ?? 0.0) * 100,
                        color: const Color(0xFF69F0AE),
                        width: 8,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                      BarChartRodData(
                        toY: ((item['NDMI'] as num?)?.toDouble() ?? 0.0) * 100,
                        color: Colors.blueAccent,
                        width: 8,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                      BarChartRodData(
                        toY: ((item['NDRE'] as num?)?.toDouble() ?? 0.0) * 100,
                        color: goldColor,
                        width: 8,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 25),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSimpleLegend(
                "مؤشر الغطاء النباتي",
                const Color(0xFF69F0AE),
              ),
              const SizedBox(width: 20),
              _buildSimpleLegend("مؤشر الرطوبه", Colors.blueAccent),
              const SizedBox(width: 20),
              _buildSimpleLegend("مؤشر الكلوروفيل", goldColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleLegend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.almarai(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color, double val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.almarai(color: Colors.white70, fontSize: 13),
          ),
          const Spacer(),
          Text(
            "${val.toStringAsFixed(1)}%",
            style: GoogleFonts.almarai(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationsSection() {
    final Map<String, dynamic> healthRoot = widget.farmData['health'] != null
        ? (widget.farmData['health'] as Map).cast<String, dynamic>()
        : widget.farmData.cast<String, dynamic>();

    final Map<String, dynamic> forecast =
        (healthRoot['forecast_next_week'] is Map)
        ? (healthRoot['forecast_next_week'] as Map).cast<String, dynamic>()
        : {};

    final double hNext =
        double.tryParse("${forecast['Healthy_Pct_next']}") ?? 0.0;
    final double mNext =
        double.tryParse("${forecast['Monitor_Pct_next']}") ?? 0.0;
    final double cNext =
        double.tryParse("${forecast['Critical_Pct_next']}") ?? 0.0;

    final double ndviDelta =
        double.tryParse("${forecast['ndvi_delta_next_mean']}") ?? 0.0;
    final double ndmiDelta =
        double.tryParse("${forecast['ndmi_delta_next_mean']}") ?? 0.0;

    // ✅ (جديد) قراءة التوصيات من farmData
    final List<dynamic> recosRaw =
        (widget.farmData['recommendations'] as List?) ?? [];
    final List<Map<String, dynamic>> recos = recosRaw
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    // ✅ (جديد) ترتيبها بالأولوية
    recos.sort((a, b) {
      final pa = _priorityRank((a['priority_ar'] ?? '').toString());
      final pb = _priorityRank((b['priority_ar'] ?? '').toString());
      return pa.compareTo(pb);
    });

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        children: [
          // 1) كرت توقعات توزيع الحالة الصحية
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "توقعات توزيع الحالة الصحية (الأسبوع القادم)",
                  style: GoogleFonts.almarai(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 14),
                _forecastRow("مستقر", Colors.greenAccent, hNext),
                _forecastRow("قيد المراقبة", Colors.orangeAccent, mNext),
                _forecastRow("حرج (خطر إصابة)", Colors.redAccent, cNext),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 2) كرت التحليل الفيزيولوجي المتوقع
          _buildPhysiologicalTrendCard(ndviDelta, ndmiDelta),

          const SizedBox(height: 20),

          // ✅ (جديد) كرت التوصيات (يظهر تحت التنبؤ مباشرة)
          _buildForecastRecommendationsCard(recos),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildPhysiologicalTrendCard(double ndviDelta, double ndmiDelta) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "تحليل المؤشرات الحيوية المتوقع",
            style: GoogleFonts.almarai(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // مؤشر كثافة الخضرة (NDVI)
              Expanded(
                child: _buildTrendIndicator(
                  "كثافة الخضرة",
                  ndviDelta,
                  Icons.spa_rounded,
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: Colors.white.withValues(alpha: 0.1),
              ),
              // مؤشر مستوى الارتواء (NDMI)
              Expanded(
                child: _buildTrendIndicator(
                  "مستوى الارتواء",
                  ndmiDelta,
                  Icons.opacity_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrendIndicator(String label, double delta, IconData icon) {
    bool isPositive = delta >= 0;
    // استقرار الحالة إذا كان التغير أقل من 0.1%
    bool isStable = delta.abs() < 0.001;

    // حساب النسبة المئوية للتغير
    String percentage = (delta.abs() * 100).toStringAsFixed(1);

    String statusText;
    if (isStable) {
      statusText = "مستقر";
    } else {
      if (label == "كثافة الخضرة") {
        statusText = isPositive ? "نمو متزايد" : "ذبول محتمل";
      } else {
        statusText = isPositive ? "ارتواء جيد" : "إجهاد مائي";
      }
    }

    return Column(
      children: [
        Icon(icon, color: goldColor.withValues(alpha: 0.7), size: 24),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.almarai(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isStable
                  ? Icons.horizontal_rule_rounded
                  : (isPositive
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded),
              color: isStable
                  ? Colors.blueGrey
                  : (isPositive ? Colors.greenAccent : Colors.redAccent),
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              isStable ? statusText : "$statusText ($percentage%)",
              style: GoogleFonts.almarai(
                color: isStable
                    ? Colors.blueGrey
                    : (isPositive ? Colors.greenAccent : Colors.redAccent),
                fontWeight: FontWeight.bold,
                fontSize: 11, // صغرنا الخط قليلاً ليتناسب مع النسبة
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _forecastRow(String label, Color color, double val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.almarai(color: Colors.white70, fontSize: 13),
          ),
          const Spacer(),
          Text(
            "${val.toStringAsFixed(1)}%",
            style: GoogleFonts.almarai(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  int _priorityRank(String p) {
    // الأصغر = أهم
    if (p.contains("عاجلة")) return 0;
    if (p.contains("مرتفعة")) return 1;
    if (p.contains("متوسطة")) return 2;
    return 3; // منخفضة أو غير محددة
  }

  Color _priorityColor(String p) {
    if (p.contains("عاجلة")) return Colors.redAccent;
    if (p.contains("مرتفعة")) return Colors.orangeAccent;
    if (p.contains("متوسطة")) return Colors.blueAccent;
    return Colors.white38;
  }

  String _bestSource(List<dynamic> srcs) {
    final list = srcs.map((e) => e.toString().toLowerCase()).toList();

    // نعطي أولوية لمصادر أوضح للأيقونة
    const keys = [
      "water",
      "stress",
      "rpw",
      "growth",
      "baseline",
      "forecast",
      "unusual",
      "outlier",
      "current",
    ];

    for (final k in keys) {
      final hit = list.firstWhere((s) => s.contains(k), orElse: () => "");
      if (hit.isNotEmpty) return hit;
    }

    return list.isNotEmpty ? list.first : "";
  }

  IconData _recoIcon(String source) {
    final s = source.toLowerCase();

    if (s.contains("water")) return Icons.water_drop_rounded;
    if (s.contains("stress") || s.contains("rpw")) return Icons.opacity_rounded;
    if (s.contains("growth") || s.contains("baseline"))
      return Icons.spa_rounded;
    if (s.contains("forecast")) return Icons.auto_awesome_rounded;
    if (s.contains("unusual") || s.contains("outlier"))
      return Icons.track_changes_rounded;
    if (s.contains("current")) return Icons.warning_amber_rounded;

    return Icons.lightbulb_rounded;
  }

  Widget _buildForecastRecommendationsCard(List<Map<String, dynamic>> recos) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.recommend_rounded,
                color: goldColor.withValues(alpha: 0.9),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "توصيات",
                  style: GoogleFonts.almarai(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (recos.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Text(
                "لا توجد توصيات جديدة حاليًا. سيتم تحديثها تلقائيًا بعد التحليل القادم.",
                style: GoogleFonts.almarai(color: Colors.white60, fontSize: 12),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recos.length > 6 ? 6 : recos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = recos[i];
                final pr = (r['priority_ar'] ?? 'متوسطة').toString();
                final List<dynamic> srcs = (r['sources'] as List?) ?? [];
                final String src = _bestSource(srcs);
                final pColor = _priorityColor(pr);

                return _RecoCardExpandable(
                  r: r,
                  pColor: pColor,
                  icon: _recoIcon(src),
                  priorityText: pr,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _RecoCardExpandable extends StatefulWidget {
  final Map<String, dynamic> r;
  final Color pColor;
  final IconData icon;
  final String priorityText;

  const _RecoCardExpandable({
    required this.r,
    required this.pColor,
    required this.icon,
    required this.priorityText,
  });

  @override
  State<_RecoCardExpandable> createState() => _RecoCardExpandableState();
}

class _RecoCardExpandableState extends State<_RecoCardExpandable> {
  bool _open = false;

  String _safeStr(String k, {String fallback = ""}) {
    final v = widget.r[k];
    if (v == null) return fallback;
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final title = _safeStr('title_ar', fallback: 'توصية');
    final actionTitle = _safeStr('actionTitle_ar', fallback: 'ماذا أفعل؟');
    final actionText = _safeStr('text_ar', fallback: '');
    final whyTitle = _safeStr('whyTitle_ar', fallback: 'لماذا؟');
    final whyText = _safeStr('why_ar', fallback: '');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _open = !_open),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: widget.pColor.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.pColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(widget.icon, color: widget.pColor, size: 20),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: GoogleFonts.almarai(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: widget.pColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: widget.pColor.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              widget.priorityText,
                              style: GoogleFonts.almarai(
                                color: widget.pColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),

                const SizedBox(width: 8),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.white60,
                ),
              ],
            ),
          ),

          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Column(
                children: [
                  _infoBubble(
                    title: whyTitle,
                    icon: Icons.help_outline_rounded,
                    color: Colors.white.withValues(alpha: 0.10),
                    border: Colors.white.withValues(alpha: 0.10),
                    text: whyText,
                  ),
                  const SizedBox(height: 10),
                  _infoBubble(
                    title: actionTitle,
                    icon: Icons.check_circle_outline_rounded,
                    color: widget.pColor.withValues(alpha: 0.10),
                    border: widget.pColor.withValues(alpha: 0.22),
                    text: actionText,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBubble({
    required String title,
    required IconData icon,
    required Color color,
    required Color border,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.almarai(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text.isEmpty ? "—" : text,
            style: GoogleFonts.almarai(
              color: Colors.white70,
              fontSize: 12,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
