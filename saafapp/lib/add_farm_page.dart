import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart'
    show Placemark, locationFromAddress, placemarkFromCoordinates;
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

// Firebase
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

// ألوان
const Color primaryColor = Color(0xFF1E8D5F);
const Color secondaryColor = Color(0xFFFDCB6E);
const Color darkBackground = Color(0xFF0D251D);

class AddFarmPage extends StatefulWidget {
  const AddFarmPage({super.key});

  @override
  State<AddFarmPage> createState() => _AddFarmPageState();
}

class _AddFarmPageState extends State<AddFarmPage> {
  // ---------- فورم ----------
  final _formKey = GlobalKey<FormState>();
  final _farmNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _farmSizeController = TextEditingController();
  final _notesController = TextEditingController();

  // بحث الخريطة
  final _searchCtrl = TextEditingController();

  String? _selectedRegion;

  // صورة (ويب/موبايل)
  File? _farmImage; // للأندرويد/‏iOS/‏دسكتوب
  Uint8List? _imageBytes; // للويب

  // خريطة
  GoogleMapController? _gCtrl;
  CameraPosition _initialCamera = const CameraPosition(
    target: LatLng(24.774265, 46.738586), // الرياض
    zoom: 12,
  );
  final List<LatLng> _polygonPoints = [];
  Set<Polygon> _polygons = {};
  Set<Marker> _markers = {};

  // Firebase
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  late final FirebaseStorage _storage;

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

  bool _isSaving = false;

  // === أداة تنظيف روابط الصور (إزالة فراغات/أسطر + فك %252F) ===
  String _cleanUrl(String? raw) {
    if (raw == null) return '';
    var u = raw.replaceAll(RegExp(r'\s+'), ''); // يحذف كل أنواع الفراغات/الأسطر
    if (u.contains('%252F')) u = Uri.decodeFull(u); // %252F -> %2F
    return u;
  }

  @override
  void initState() {
    super.initState();
    _storage = FirebaseStorage.instance;
    _centerToMyLocation();
  }

  @override
  void dispose() {
    _farmNameController.dispose();
    _ownerNameController.dispose();
    _farmSizeController.dispose();
    _notesController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // =================== الموقع الحالي ===================
  Future<void> _centerToMyLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final cam =
          CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 15);
      _initialCamera = cam;
      if (_gCtrl != null) {
        await _gCtrl!.animateCamera(
          CameraUpdate.newCameraPosition(cam),
        );
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('location error: $e');
    }
  }

  // =================== البحث (Geocoding) ===================
  Future<void> _searchAndGo() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    try {
      final results = await locationFromAddress(q);
      if (results.isEmpty) return;
      final loc = results.first;
      await _gCtrl?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(loc.latitude, loc.longitude), zoom: 14),
        ),
      );
    } catch (_) {
      _showSnackBar('تعذر العثور على الموقع المطلوب', isError: true);
    }
  }

  // =================== رسم المضلع ===================
  void _onMapTap(LatLng p) {
    _polygonPoints.add(p);
    _rebuildOverlays();
  }

  void _undoLastPoint() {
    if (_polygonPoints.isNotEmpty) {
      _polygonPoints.removeLast();
      _rebuildOverlays();
    }
  }

  void _clearPolygon() {
    _polygonPoints.clear();
    _markers.clear();
    _polygons.clear();
    setState(() {});
  }

  void _rebuildOverlays() {
    _markers = {
      for (int i = 0; i < _polygonPoints.length; i++)
        Marker(
          markerId: MarkerId('pt_$i'),
          position: _polygonPoints[i],
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        )
    };
    _polygons = {
      if (_polygonPoints.length >= 3)
        Polygon(
          polygonId: const PolygonId('farm'),
          points: _polygonPoints,
          fillColor: const Color.fromARGB(75, 215, 172, 92),
          strokeColor: const Color.fromARGB(255, 2, 79, 25),
          strokeWidth: 3,
        ),
    };
    setState(() {});
  }

  // =================== اختيار صورة ===================
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;

    if (kIsWeb) {
      final bytes = await x.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _farmImage = null;
      });
    } else {
      setState(() {
        _farmImage = File(x.path);
        _imageBytes = null;
      });
    }
  }

  // =================== حساب مساحة تقديرية ===================
  double _toWebMercatorX(double lon) {
    const originShift = 20037508.342789244;
    return lon * originShift / 180.0;
  }

  double _toWebMercatorY(double lat) {
    final clamped = lat.clamp(-85.05112878, 85.05112878);
    const originShift = 20037508.342789244;
    final rad = clamped * math.pi / 180.0;
    return originShift *
        math.log(math.tan(math.pi / 4.0 + rad / 2.0)) /
        math.pi;
  }

  double _estimateAreaSqM(List<LatLng> pts) {
    if (pts.length < 3) return 0;
    final xs = <double>[], ys = <double>[];
    for (final p in pts) {
      xs.add(_toWebMercatorX(p.longitude));
      ys.add(_toWebMercatorY(p.latitude));
    }
    xs.add(xs.first);
    ys.add(ys.first);
    double sum = 0;
    for (int i = 0; i < xs.length - 1; i++) {
      sum += (xs[i] * ys[i + 1]) - (xs[i + 1] * ys[i]);
    }
    return (sum.abs() * 0.5);
  }

  // =================== مطابقة المنطقة (Reverse Geocoding) ===================
  LatLng _centroid(List<LatLng> pts) {
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }

  Future<String?> _reverseRegionFromCentroid() async {
    try {
      final c = _centroid(_polygonPoints);
      final List<Placemark> p = await placemarkFromCoordinates(
        c.latitude,
        c.longitude,
        localeIdentifier: 'ar',
      );
      if (p.isEmpty) return null;
      final main = (p.first.administrativeArea ?? '').trim();
      final sub = (p.first.subAdministrativeArea ?? '').trim();
      final locality = (p.first.locality ?? '').trim();
      return [main, sub, locality]
          .firstWhere((e) => e.isNotEmpty, orElse: () => '');
    } catch (e) {
      debugPrint('reverse geocoding error: $e');
      return null;
    }
  }

  String _normalize(String s) {
    final t = s.replaceAll(' ', '').replaceAll('ـ', '').toLowerCase();
    final map = {
      'riyadh': 'الرياض',
      'abha': 'أبها',
      'asir': 'عسير',
      'makkah': 'مكةالمكرمة',
      'mecca': 'مكةالمكرمة',
      'easternprovince': 'الشرقية',
      'alqassim': 'القصيم',
      'madinah': 'المدينةالمنورة',
      'aljawf': 'الجوف',
      'hail': 'حائل',
      'tabuk': 'تبوك',
      'jazan': 'جازان',
      'najran': 'نجران',
      'albaha': 'الباحة',
      'northernborders': 'الحدودالشمالية',
    };
    for (final e in map.entries) {
      if (t.contains(e.key)) return e.value;
    }
    return t;
  }

  Future<bool> _confirmDialog(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color.fromARGB(255, 3, 56, 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.almarai(
                color: secondaryColor,
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
            ),
            content: Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.almarai(
                color: secondaryColor,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'إلغاء',
                  style: GoogleFonts.almarai(
                    color: const Color(0xFF777777),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: secondaryColor,
                  foregroundColor: const Color(0xFF042C25),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'متابعة',
                  style: GoogleFonts.almarai(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  // =================== رفع الصورة (اختياري) ===================
  // ignore: unused_element
  Future<String?> _uploadImageAndGetUrl(User user) async {
    try {
      final ref = _storage
          .ref()
          .child(
            'farm_images/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
      final meta = SettableMetadata(contentType: 'image/jpeg');

      UploadTask? task;
      if (kIsWeb && _imageBytes != null) {
        task = ref.putData(_imageBytes!, meta);
      } else if (_farmImage != null) {
        task = ref.putFile(_farmImage!, meta);
      } else {
        return null; // لا يوجد صورة
      }

      final sub = task.snapshotEvents.listen(
        (s) => debugPrint(
          'upload: ${s.state} -> ${s.bytesTransferred}/${s.totalBytes}',
        ),
        onError: (e) => debugPrint('upload error: $e'),
      );

      await task.timeout(const Duration(seconds: 90));
      await sub.cancel();

      final url = _cleanUrl(await ref.getDownloadURL());
      return url;
    } on FirebaseException catch (e) {
      _showSnackBar('تعذر رفع الصورة: ${e.code}', isError: true);
      debugPrint('FirebaseException during upload: ${e.code} ${e.message}');
      return null;
    } on TimeoutException catch (_) {
      _showSnackBar(
        'مهلة رفع الصورة انتهت. تحقق من الشبكة أو من إعدادات Storage.',
        isError: true,
      );
      return null;
    } catch (e) {
      _showSnackBar('خطأ غير متوقع أثناء رفع الصورة: $e', isError: true);
      return null;
    }
  }

  // =================== الحفظ ===================
  Future<void> _submitFarmData() async {
    if (!mounted) return;

    if (_formKey.currentState!.validate() &&
        _polygonPoints.length >= 3 &&
        _selectedRegion != null) {
      // 1) تحقق المنطقة
      String selected = _selectedRegion!;
      String? detected = await _reverseRegionFromCentroid();
      if (detected != null && detected.isNotEmpty) {
        final a = _normalize(selected);
        final b = _normalize(detected);
        final match = a.contains(b) || b.contains(a);
        if (!match) {
          final ok = await _confirmDialog(
            'تحذير عدم تطابق المنطقة',
            'المنطقة المختارة: "$selected"\n'
            'إحداثيات الخريطة تشير إلى: "$detected"\n\n'
            'هل تريد المتابعة رغم عدم التطابق؟',
          );
          if (!ok) return;
        }
      }

      // 2) تحقق المساحة ±30%
      final entered = double.tryParse(_farmSizeController.text.trim()) ?? 0.0;
      if (entered > 0) {
        final computed = _estimateAreaSqM(_polygonPoints);
        final ratio = (computed - entered).abs() / entered;
        if (ratio > 0.30) {
          final ok = await _confirmDialog(
            'تحذير اختلاف المساحة',
            'المساحة المدخلة: ${entered.toStringAsFixed(0)} م²\n'
            'المساحة المقدّرة من الخريطة: ${computed.toStringAsFixed(0)} م²\n\n'
            'يوجد فرق كبير (> 30%). هل تريد المتابعة؟',
          );
          if (!ok) return;
        }
      }

      setState(() => _isSaving = true);

      try {
        final user = _auth.currentUser;
        if (user == null) {
          _showSnackBar('يجب تسجيل الدخول أولاً.', isError: true);
          if (mounted) setState(() => _isSaving = false);
          return;
        }

        // رفع الصورة (إن وجدت)
        String? imageUrl;
        String? imagePath;
        if (_imageBytes != null || _farmImage != null) {
          final ref = _storage
              .ref()
              .child(
                'farm_images/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg',
              );
          final meta = SettableMetadata(contentType: 'image/jpeg');

          UploadTask task;
          if (kIsWeb && _imageBytes != null) {
            task = ref.putData(_imageBytes!, meta);
          } else {
            task = ref.putFile(_farmImage!, meta);
          }

          await task.timeout(const Duration(seconds: 90));
          imageUrl = _cleanUrl(await ref.getDownloadURL());
          imagePath = ref.fullPath;
        }

        final polygonData = _polygonPoints
            .map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();

        await _db.collection('farms').add({
          'farmName': _farmNameController.text.trim(),
          'ownerName': _ownerNameController.text.trim(),
          'farmSize': _farmSizeController.text.trim(),
          'region': _selectedRegion,
          'notes': _notesController.text.trim(),
          'polygon': polygonData,
          'imageURL': _cleanUrl(imageUrl),
          'imagePath': imagePath,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': user.uid,
        });

        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false); // نجاح
      } catch (e) {
        _showSnackBar('حدث خطأ أثناء حفظ البيانات: $e', isError: true);
        if (mounted) setState(() => _isSaving = false);
      } finally {
        if (mounted && Navigator.canPop(context) == false) {
          setState(() => _isSaving = false);
        }
      }
    } else {
      if (_polygonPoints.length < 3) {
        _showSnackBar('حدد 3 نقاط على الأقل لحدود المزرعة.', isError: true);
      } else if (_selectedRegion == null) {
        _showSnackBar('اختر المنطقة.', isError: true);
      }
    }
  }

  void _showSnackBar(String msg, {bool isSuccess = false, bool isError = false}) {
    if (!mounted) return;

    final Color bg = isError
        ? const Color(0xFFB00020)
        : (isSuccess ? const Color(0xFF1E8D5F) : const Color(0xFF333333));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        content: Text(
          msg,
          textAlign: TextAlign.center,
          style: GoogleFonts.almarai(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // =================== واجهة المستخدم ===================
  // في ملف add_farm_page.dart

@override
Widget build(BuildContext context) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: darkBackground,

      // 👇🏼 1. استخدام AppBar للزر (هذا يحل مشكلة الزر الطائر)
      appBar: AppBar(
        backgroundColor: darkBackground,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false, // نتحكم بالزر الأيمن يدويًا

        // 1. زر الرجوع الدائري (السهم) في اليمين (Leading) - ليتناسب مع LoginScreen
        leading: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: Material(
            color: Colors.black45, // نفس الخلفية الدائرية لشاشة الدخول
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              // الرجوع إلى الصفحة السابقة
              onTap: () => Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          ),
        ),

        // 2. العنوان في المنتصف
        title: Text(
          'إضافة مزرعة جديدة',
          style: GoogleFonts.almarai(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      // 👆🏼 نهاية الـ AppBar 👆🏼

      // 2. الـ Body: إزالة الـ Stack الزائد والاعتماد على الـ Padding العادي
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 +
                kBottomNavigationBarHeight +
                MediaQuery.of(context).viewPadding.bottom +
                12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10), // فاصل بسيط بعد الـ AppBar
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


  Widget _buildFarmForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color.fromARGB(25, 255, 255, 255),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: const Color.fromARGB(51, 255, 255, 255),
        ),
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
            _textField(
              controller: _farmNameController,
              label: 'اسم المزرعة',
              icon: Icons.grass,
            ),
            const SizedBox(height: 20),
            _textField(
              controller: _ownerNameController,
              label: 'اسم المالك',
              icon: Icons.person,
            ),
            const SizedBox(height: 20),
            _textField(
              controller: _farmSizeController,
              label: 'مساحة المزرعة (م²)',
              icon: Icons.straighten,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            _regionDropdown(),
            const SizedBox(height: 20),
            _textField(
              controller: _notesController,
              label: 'ملاحظات إضافية (اختياري)',
              icon: Icons.notes,
              optional: true,
              maxLines: 4,
            ),
            const SizedBox(height: 20),
            _imagePicker(),
            const SizedBox(height: 10),
            if (_imageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.memory(
                  _imageBytes!,
                  height: 150,
                  fit: BoxFit.cover,
                ),
              )
            else if (_farmImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.file(
                  _farmImage!,
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _textField({
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
      style: GoogleFonts.almarai(color: Colors.white),
      validator: (value) {
        if (!optional && (value == null || value.isEmpty)) {
          return 'هذا الحقل مطلوب';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.almarai(color: Colors.white70),
        prefixIcon: Icon(icon, color: secondaryColor),
        filled: true,
        fillColor: const Color.fromARGB(25, 255, 255, 255),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15.0),
          borderSide:
              const BorderSide(color: Color.fromARGB(76, 253, 203, 110)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(15.0)),
          borderSide: BorderSide(color: secondaryColor, width: 2),
        ),
      ),
    );
  }

  Widget _regionDropdown() {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: 'المنطقة',
        labelStyle: GoogleFonts.almarai(color: Colors.white70),
        prefixIcon: const Icon(Icons.location_on, color: secondaryColor),
        filled: true,
        fillColor: const Color.fromARGB(25, 255, 255, 255),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15.0),
          borderSide: BorderSide.none,
        ),
      ),
      dropdownColor: darkBackground,
      style: GoogleFonts.almarai(color: Colors.white),
      initialValue: _selectedRegion,
      isExpanded: true,
      hint: Text(
        'اختر منطقة',
        style: GoogleFonts.almarai(color: Colors.white54),
      ),
      onChanged: (val) => setState(() => _selectedRegion = val),
      items: _saudiRegions
          .map((r) => DropdownMenuItem(value: r, child: Text(r)))
          .toList(),
      validator: (v) => v == null ? 'الرجاء اختيار منطقة' : null,
    );
  }

  Widget _imagePicker() {
    return SizedBox(
      height: 60,
      child: ElevatedButton.icon(
        onPressed: _pickImage,
        icon: const Icon(Icons.add_photo_alternate_rounded,
            color: secondaryColor),
        label: const Text(
          'أضف صورة للمزرعة (اختياري)',
          style: TextStyle(color: secondaryColor, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color.fromARGB(25, 255, 255, 255),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: secondaryColor),
          ),
        ),
      ),
    );
  }

  Widget _buildMapSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'تحديد حدود المزرعة',
          style: GoogleFonts.almarai(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 350,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                GoogleMap(
                  mapType: MapType.hybrid,
                  initialCameraPosition: _initialCamera,
                  onMapCreated: (c) => _gCtrl = c,
                  onTap: _onMapTap,
                  polygons: _polygons,
                  markers: _markers,
                  zoomControlsEnabled: true,
                  compassEnabled: false,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white,
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        const Icon(Icons.search, color: Colors.black54),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _searchAndGo(),
                            decoration: InputDecoration(
                              hintText: 'ابحث باسم مكان / عنوان...',
                              hintStyle: GoogleFonts.almarai(
                                color: Colors.black45,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                            ),
                            style:
                                GoogleFonts.almarai(color: Colors.black87),
                          ),
                        ),
                        IconButton(
                          onPressed: _searchAndGo,
                          icon: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: _undoLastPoint,
              icon: const Icon(Icons.undo, color: Color(0xFF042C25)),
              label: Text(
                'تراجع',
                style: GoogleFonts.almarai(color: Color(0xFF042C25)),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFDCB6E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _clearPolygon,
              icon: const Icon(Icons.clear_all, color: Colors.white),
              label: Text(
                'مسح النقاط',
                style: GoogleFonts.almarai(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFEBB974), Color(0xFFFFF6E0)],
          ),
          borderRadius: BorderRadius.circular(35),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _isSaving ? null : _submitFarmData,
            child: Center(
              child: _isSaving
                  ? const CircularProgressIndicator(
                      strokeWidth: 3, color: Color(0xFF042C25))
                  : Text(
                      'إضافة المزرعة',
                      style: GoogleFonts.almarai(
                        color: Color(0xFF042C25),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
