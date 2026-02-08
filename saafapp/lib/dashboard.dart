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
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

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
              backgroundColor: Colors.white.withOpacity(0.05),
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
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: goldColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: goldColor.withOpacity(0.6), width: 1.5),
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
          Tab(icon: Icon(Icons.auto_awesome_outlined), text: "توصيات"),
        ],
      ),
    );
  }

  Widget _buildMapSection() {
    // 1. تحويل نقاط الـ Polygon من الداتابيز
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

    // 2. سحب المساحة باستخدام المسمى الصحيح من الداتابيز (farmSize)
    // تم استخدام farmSize بناءً على بيانات Firestore المرسلة
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
          // الخريطة
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: FlutterMap(
              options: MapOptions(initialCenter: center, initialZoom: 17.5),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://api.maptiler.com/maps/hybrid/{z}/{x}/{y}.jpg?key=${Secrets.mapTilerKey}',
                  userAgentPackageName: 'com.example.saafapp',
                ),
                if (points.isNotEmpty)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: points,
                        color: lightGreenColor.withOpacity(0.15),
                        borderColor: goldColor,
                        borderStrokeWidth: 2.5,
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // تظليل علوي للنص
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
                "حدود المزرعة الحالية",
                style: GoogleFonts.almarai(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // بطاقة المعلومات - تعرض المساحة فقط بناءً على طلبك
          Positioned(
            bottom: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
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
          ),
        ],
      ),
    );
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
    final health = widget.farmData['health'] as Map<String, dynamic>? ?? {};
    final double healthy =
        double.tryParse(health['Healthy_Pct']?.toString() ?? '0') ?? 0;
    final double monitor =
        double.tryParse(health['Monitor_Pct']?.toString() ?? '0') ?? 0;
    final double critical =
        double.tryParse(health['Critical_Pct']?.toString() ?? '0') ?? 0;
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
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildWeatherCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
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
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
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
    return Container(
      height: 340,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "تطور المؤشرات الحيوية (آخر 5 أشهر)",
            style: GoogleFonts.almarai(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildSimpleLegend(
                "مؤشر الغطاء النباتي (NDVI)",
                const Color(0xFF69F0AE),
              ),
              _buildSimpleLegend("مؤشر رطوبة النبات (NDMI)", Colors.blueAccent),
              _buildSimpleLegend("مؤشر الكلوروفيل (NDRE)", goldColor),
            ],
          ),
          const SizedBox(height: 25),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const months = [
                          'أكتوبر',
                          'نوفمبر',
                          'ديسمبر',
                          'يناير',
                          'فبراير',
                        ];
                        if (value.toInt() >= 0 &&
                            value.toInt() < months.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              months[value.toInt()],
                              style: GoogleFonts.almarai(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 35,
                      getTitlesWidget: (value, meta) => Text(
                        "${value.toInt()}%",
                        style: GoogleFonts.almarai(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  _lineData([
                    const FlSpot(0, 70),
                    const FlSpot(1, 65),
                    const FlSpot(2, 75),
                    const FlSpot(3, 80),
                    const FlSpot(4, 85),
                  ], const Color(0xFF69F0AE)),
                  _lineData([
                    const FlSpot(0, 50),
                    const FlSpot(1, 48),
                    const FlSpot(2, 55),
                    const FlSpot(3, 52),
                    const FlSpot(4, 58),
                  ], Colors.blueAccent),
                  _lineData([
                    const FlSpot(0, 40),
                    const FlSpot(1, 42),
                    const FlSpot(2, 45),
                    const FlSpot(3, 48),
                    const FlSpot(4, 50),
                  ], goldColor),
                ],
              ),
            ),
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

  Widget _buildRecommendationsSection() =>
      _placeholder("توصيات الذكاء الاصطناعي");
  Widget _placeholder(String text) => Center(
    child: Text(text, style: const TextStyle(color: Colors.white24)),
  );
}
