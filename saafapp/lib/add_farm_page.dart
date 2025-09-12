// lib/add_farm_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:animate_do/animate_do.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

const Color primaryColor = Color(0xFF1E8D5F);
const Color secondaryColor = Color(0xFFFDCB6E);
const Color darkBackground = Color(0xFF0D251D);

// -----------------------------------------------------------------------------
// * الصفحة الرئيسية
// -----------------------------------------------------------------------------
class AddFarmPage extends StatefulWidget {
  const AddFarmPage({super.key});

  @override
  State<AddFarmPage> createState() => _AddFarmPageState();
}

class _AddFarmPageState extends State<AddFarmPage> {
  // متغيرات الحالة
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _farmNameController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();
  final TextEditingController _farmSizeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  String? _selectedRegion;
  File? _farmImage;
  final MapController _mapController = MapController();
  final List<LatLng> _polygonCoordinates = [];
  bool _isLoading = false;

  final List<String> _saudiRegions = const [
    'الرياض',
    'مكة المكرمة',
    'المدينة المنورة',
    'القصيم',
    'الشرقية',
    'عسير',
    'تبوك',
    'حائل',
    'الحدود الشمالية',
    'جازان',
    'نجران',
    'الباحة',
    'الجوف',
  ];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _farmNameController.dispose();
    _ownerNameController.dispose();
    _farmSizeController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------------------
  // * دوال مساعدة
  // -----------------------------------------------------------------------------

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _mapController.move(LatLng(position.latitude, position.longitude), 15);
    } catch (e) {
      debugPrint('حدث خطأ أثناء الحصول على الموقع: $e');
    }
  }

  void _addPoint(TapPosition tapPosition, LatLng point) {
    setState(() {
      _polygonCoordinates.add(point);
    });
  }

  void _clearPolygon() {
    setState(() {
      _polygonCoordinates.clear();
    });
  }

  void _undoLastPoint() {
    setState(() {
      if (_polygonCoordinates.isNotEmpty) {
        _polygonCoordinates.removeLast();
      }
    });
  }

  void _searchLocation() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return;
    }

    final url =
        'https://nominatim.openstreetmap.org/search?q=$query&format=json&accept-language=ar';

    final headers = {
      'User-Agent':
          'Saaf App / Add Farm Page (contact: 443204566@student.ksu.edu.sa)',
    };

    try {
      final response = await http.get(Uri.parse(url), headers: headers);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final List results = json.decode(response.body);
        if (results.isNotEmpty) {
          final firstResult = results.first;
          final lat = double.parse(firstResult['lat']);
          final lon = double.parse(firstResult['lon']);
          _mapController.move(LatLng(lat, lon), 12.0);
        } else {
          _showSnackBar('لم يتم العثور على المكان.');
        }
      } else {
        _showSnackBar('حدث خطأ أثناء البحث. حاول مرة أخرى.');
      }
    } catch (e) {
      debugPrint('حدث خطأ في الاتصال بالإنترنت: $e');
      if (!mounted) return;
      _showSnackBar('تأكد من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _farmImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _submitFarmData() async {
    if (_formKey.currentState!.validate() &&
        _polygonCoordinates.length >= 3 &&
        _selectedRegion != null) {
      setState(() {
        _isLoading = true;
      });

      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnackBar('تم إضافة المزرعة بنجاح! شكراً لك.', isSuccess: true);
    } else {
      if (_polygonCoordinates.length < 3) {
        _showSnackBar(
          'الرجاء تحديد 3 نقاط على الأقل لحدود المزرعة.',
          isError: true,
        );
      } else if (_selectedRegion == null) {
        _showSnackBar('الرجاء اختيار المنطقة.', isError: true);
      }
    }
  }

  void _showSnackBar(
    String message, {
    bool isSuccess = false,
    bool isError = false,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: isSuccess
            ? primaryColor
            : (isError ? Colors.redAccent : Colors.grey),
      ),
    );
  }

  // -----------------------------------------------------------------------------
  // * بناء واجهة المستخدم (UI)
  // -----------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: darkBackground,
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 50),
                ZoomIn(
                  duration: const Duration(milliseconds: 800),
                  child: const Center(
                    child: Column(
                      children: [
                        Text(
                          'إضافة مزرعة جديدة',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 10),
                        Icon(
                          Icons.agriculture_sharp,
                          color: secondaryColor,
                          size: 50,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                _buildFarmForm(),
                const SizedBox(height: 30),
                _buildMapSection(),
                const SizedBox(height: 20),
                _buildSubmitButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------------
  // * بناء حقول النموذج (Form Fields)
  // -----------------------------------------------------------------------------
  Widget _buildFarmForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color.fromARGB(25, 255, 255, 255),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: const Color.fromARGB(51, 255, 255, 255)),
        boxShadow: const [
          BoxShadow(
            color: Color.fromARGB(51, 0, 0, 0),
            blurRadius: 15,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildTextField(
              controller: _farmNameController,
              label: 'اسم المزرعة',
              icon: Icons.grass,
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _ownerNameController,
              label: 'اسم المالك',
              icon: Icons.person,
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _farmSizeController,
              label: 'مساحة المزرعة (م²)',
              icon: Icons.straighten,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            _buildRegionDropdown(),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _notesController,
              label: 'ملاحظات إضافية (اختياري)',
              icon: Icons.notes,
              optional: true,
              maxLines: 4,
            ),
            const SizedBox(height: 20),
            _buildImagePicker(),
            if (_farmImage != null)
              FadeInDown(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.file(
                      _farmImage!,
                      height: 150,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------------
  // * بناء حقل نص مع تصميم مخصص
  // -----------------------------------------------------------------------------
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool optional = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textAlign: TextAlign.right,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      validator: (value) {
        if (!optional && (value == null || value.isEmpty)) {
          return 'هذا الحقل مطلوب';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        suffixIcon: Icon(icon, color: secondaryColor),
        filled: true,
        fillColor: const Color.fromARGB(25, 255, 255, 255),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15.0),
          borderSide: const BorderSide(
            color: Color.fromARGB(76, 253, 203, 110),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15.0),
          borderSide: const BorderSide(color: secondaryColor, width: 2),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------------
  // * بناء قائمة المناطق المنسدلة
  // -----------------------------------------------------------------------------
  Widget _buildRegionDropdown() {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: 'المنطقة',
        labelStyle: const TextStyle(color: Colors.white70),
        suffixIcon: const Icon(Icons.location_on, color: secondaryColor),
        filled: true,
        fillColor: const Color.fromARGB(25, 255, 255, 255),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15.0),
          borderSide: const BorderSide(
            color: Color.fromARGB(76, 253, 203, 110),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15.0),
          borderSide: const BorderSide(color: secondaryColor, width: 2),
        ),
      ),
      dropdownColor: darkBackground,
      style: const TextStyle(color: Colors.white),
      initialValue: _selectedRegion,
      isExpanded: true,
      hint: const Text('اختر منطقة', style: TextStyle(color: Colors.white54)),
      onChanged: (String? newValue) {
        setState(() {
          _selectedRegion = newValue;
        });
      },
      items: _saudiRegions.map<DropdownMenuItem<String>>((String value) {
        return DropdownMenuItem<String>(value: value, child: Text(value));
      }).toList(),
      validator: (value) {
        if (value == null) {
          return 'الرجاء اختيار منطقة';
        }
        return null;
      },
    );
  }

  // -----------------------------------------------------------------------------
  // * بناء زر إضافة الصورة
  // -----------------------------------------------------------------------------
  Widget _buildImagePicker() {
    return SizedBox(
      height: 60,
      child: ElevatedButton.icon(
        onPressed: _pickImage,
        icon: const Icon(
          Icons.add_photo_alternate_rounded,
          color: secondaryColor,
        ),
        label: Text(
          _farmImage == null ? 'أضف صورة للمزرعة (اختياري)' : 'تغيير الصورة',
          style: const TextStyle(
            color: secondaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color.fromARGB(25, 255, 255, 255),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: secondaryColor),
          ),
          elevation: 5,
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------------
  // * بناء قسم الخريطة
  // -----------------------------------------------------------------------------
  Widget _buildMapSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'تحديد حدود المزرعة',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        // حقل البحث
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color.fromARGB(51, 255, 255, 255),
            borderRadius: BorderRadius.circular(15),
          ),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: 'ابحث عن مدينتك (مثال: الرياض)',
              hintStyle: const TextStyle(color: Colors.white54),
              border: InputBorder.none,
              icon: const Icon(Icons.search, color: secondaryColor),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: secondaryColor),
                onPressed: _searchLocation,
              ),
            ),
            onSubmitted: (value) => _searchLocation(),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 350,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(24.774265, 46.738586),
                    initialZoom: 12,
                    onTap: (tapPosition, point) =>
                        _addPoint(tapPosition, point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.saaf_app',
                    ),
                    PolygonLayer(
                      polygons: [
                        if (_polygonCoordinates.length >= 3)
                          Polygon(
                            points: _polygonCoordinates,
                            isFilled: true,
                            color: const Color.fromARGB(75, 215, 172, 92),
                            borderColor: const Color.fromARGB(255, 2, 79, 25),
                            borderStrokeWidth: 3,
                          ),
                      ],
                    ),
                    MarkerLayer(
                      markers: _polygonCoordinates.map((point) {
                        return Marker(
                          point: point,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.local_florist,
                            color: Color.fromARGB(227, 9, 69, 4),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                // توضيح للمستخدم
                const Positioned(
                  top: 10,
                  left: 10,
                  child: Card(
                    color: Colors.black54,
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'اضغط على الخريطة لتحديد نقاط حدود المزرعة',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                // أزرار التحكم بالخريطة (مسح وتراجع)
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'undoButton',
                        onPressed: _undoLastPoint,
                        backgroundColor: const Color.fromARGB(
                          204,
                          255,
                          255,
                          255,
                        ),
                        foregroundColor: primaryColor,
                        child: const Icon(Icons.undo),
                      ),
                      const SizedBox(height: 5),
                      FloatingActionButton.small(
                        heroTag: 'clearButton',
                        onPressed: _clearPolygon,
                        backgroundColor: const Color.fromARGB(
                          204,
                          255,
                          255,
                          255,
                        ),
                        foregroundColor: primaryColor,
                        child: const Icon(Icons.clear_all_rounded),
                      ),
                    ],
                  ),
                ),
                // أزرار الزوم
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'zoomInButton',
                        onPressed: () {
                          _mapController.move(
                            _mapController.camera.center,
                            _mapController.camera.zoom + 1,
                          );
                        },
                        backgroundColor: const Color.fromARGB(
                          204,
                          255,
                          255,
                          255,
                        ),
                        foregroundColor: primaryColor,
                        child: const Icon(Icons.add),
                      ),
                      const SizedBox(height: 5),
                      FloatingActionButton.small(
                        heroTag: 'zoomOutButton',
                        onPressed: () {
                          _mapController.move(
                            _mapController.camera.center,
                            _mapController.camera.zoom - 1,
                          );
                        },
                        backgroundColor: const Color.fromARGB(
                          204,
                          255,
                          255,
                          255,
                        ),
                        foregroundColor: primaryColor,
                        child: const Icon(Icons.remove),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------------
  // * بناء زر الإضافة
  // -----------------------------------------------------------------------------
  Widget _buildSubmitButton() {
    return SizedBox(
      height: 60,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submitFarmData,
        style: ElevatedButton.styleFrom(
          backgroundColor: secondaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(35),
          ),
          elevation: 10,
        ),
        child: _isLoading
            ? const CircularProgressIndicator(
                color: primaryColor,
                strokeWidth: 3,
              )
            : const Text(
                'إضافة المزرعة',
                style: TextStyle(
                  color: primaryColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
