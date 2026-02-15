import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:saafapp/constant.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:saafapp/secrets.dart';
import 'package:flutter_map/flutter_map.dart'; // سنترك هذه كما هي لأننا نستخدمها بكثرة هنا
import 'package:latlong2/latlong.dart'; // سنتركها أيضاً

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

  // متغيرات الطقس
  String temp = "--";
  String weatherDesc = "جاري التحميل...";
  bool isLoadingWeather = true;

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

  Widget _buildModernHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
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
            ],
          ),
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
            color: Colors.black.withOpacity(0.3),
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
              options: MapOptions(initialCenter: center, initialZoom: 16),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://api.maptiler.com/maps/hybrid/{z}/{x}/{y}.jpg?key=${Secrets.mapTilerKey}',
                  userAgentPackageName: 'com.example.saafapp',
                ),
                CircleLayer(
                  circles: healthMapPoints.map((point) {
                    final baseColor = _getHealthColor(point['s'] as int);
                    return CircleMarker(
                      point: LatLng(
                        (point['lat'] as num).toDouble(),
                        (point['lng'] as num).toDouble(),
                      ),
                      color: baseColor.withOpacity(0.7),
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

          // 2. بطاقات المعلومات العائمة (المفتاح + المساحة)
          Positioned(
            bottom: 20,
            right: 15,
            left: 15,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // بطاقة مفتاح الألوان بتأثير زجاجي مصحح
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: darkGreenColor.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
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

                // بطاقة المساحة
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: darkGreenColor.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: goldColor.withOpacity(0.4)),
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

          // 3. التظليل العلوي للعنوان
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
                  colors: [Colors.black.withOpacity(0.5), Colors.transparent],
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
                BoxShadow(color: color.withOpacity(0.5), blurRadius: 4),
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
        return const Color.fromARGB(87, 244, 67, 54).withOpacity(0.1); // مصاب
      case 1:
        return const Color.fromARGB(
          62,
          255,
          235,
          59,
        ).withOpacity(0.1); // مراقبة
      case 0:
        return const Color.fromARGB(
          150,
          105,
          240,
          123,
        ).withOpacity(0.1); // سليم
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

          // --- إضافة زر تصدير النتائج هنا في الجهة اليمنى ---
          const SizedBox(height: 25),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () {
                // ميزة مستقبلية
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      "ميزة تصدير التقارير ستكون متاحة قريباً",
                      style: GoogleFonts.almarai(),
                    ),
                    backgroundColor: const Color(0xFF0A4D41),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: goldColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: goldColor.withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "تصدير النتائج",
                      style: GoogleFonts.almarai(
                        color: goldColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.ios_share_rounded, color: goldColor, size: 20),
                  ],
                ),
              ),
            ),
          ),

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
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
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
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
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
                        Colors.blueGrey.withOpacity(0.9),
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
                    color: Colors.white.withOpacity(0.08),
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

  LineChartBarData _lineData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 3,
      dotData: const FlDotData(show: true),
      belowBarData: BarAreaData(show: false),
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

    // جلب قيم التغير المتوقع
    final double ndviDelta =
        double.tryParse("${forecast['ndvi_delta_next_mean']}") ?? 0.0;
    final double ndmiDelta =
        double.tryParse("${forecast['ndmi_delta_next_mean']}") ?? 0.0;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        children: [
          // 1. كرت توقعات توزيع الحالة الصحية
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

          // 2. كرت التحليل الفيزيولوجي المتوقع مع النسب المئوية
          _buildPhysiologicalTrendCard(ndviDelta, ndmiDelta),

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
}
