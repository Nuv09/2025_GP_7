// lib/edit_farm_page.dart
import 'dart:io';
import 'dart:typed_data' as td show Uint8List;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

const Color primaryColor = Color(0xFF1E8D5F);
const Color secondaryColor = Color(0xFFFDCB6E);
const Color darkBackground = Color(0xFF0D251D);

class EditFarmPage extends StatefulWidget {
  const EditFarmPage({super.key});

  @override
  State<EditFarmPage> createState() => _EditFarmPageState();
}

class _EditFarmPageState extends State<EditFarmPage> {
  final _formKey = GlobalKey<FormState>();
  final _farmNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _farmSizeController = TextEditingController();
  final _notesController = TextEditingController();

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
  String? _selectedRegion;

  // صورة
  File? _farmImage;
  td.Uint8List? _imageBytes;
  String? _currentImageUrl;

  // خريطة
  GoogleMapController? _gCtrl;
  Set<Polygon> _polygons = {};
  Set<Marker> _markers = {};
  final List<LatLng> _polygonPoints = [];
  final CameraPosition _initialCamera = const CameraPosition(
    target: LatLng(24.774265, 46.738586),
    zoom: 12,
  );

  // Firebase
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  late String farmId;
  Map<String, dynamic> init = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // قراءة الـ arguments بأنواع صارمة
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    init = (args?['initialData'] as Map<String, dynamic>?) ?? {};
    farmId = (args?['farmId'] as String?) ?? '';

    _farmNameController.text = (init['farmName'] ?? '').toString();
    _ownerNameController.text = (init['ownerName'] ?? '').toString();
    _farmSizeController.text = (init['farmSize'] ?? '').toString();
    _notesController.text = (init['notes'] ?? '').toString();
    _selectedRegion = (init['region'] as String?) ?? '';
    if (_selectedRegion!.isEmpty) _selectedRegion = null;

    _currentImageUrl = (init['imageURL'] ?? init['imageUrl'])?.toString();

    final poly = (init['polygon'] as List?) ?? [];
    _polygonPoints
      ..clear()
      ..addAll(poly.map((p) {
        final lat = (p['lat'] as num).toDouble();
        final lng = (p['lng'] as num).toDouble();
        return LatLng(lat, lng);
      }));

    _rebuildOverlays();

    // لو فيه مضلع موجود، نضبط الكاميرا عليه (لاستخدام _gCtrl فعليًا).
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitCameraToPolygon());
  }

  @override
  void dispose() {
    _farmNameController.dispose();
    _ownerNameController.dispose();
    _farmSizeController.dispose();
    _notesController.dispose();
    super.dispose();
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
        ),
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

  void _onMapTap(LatLng p) {
    _polygonPoints.add(p);
    _rebuildOverlays();
    _fitCameraToPolygon();
  }

  void _undoLastPoint() {
    if (_polygonPoints.isNotEmpty) {
      _polygonPoints.removeLast();
      _rebuildOverlays();
      _fitCameraToPolygon();
    }
  }

  void _clearPolygon() {
    _polygonPoints.clear();
    _markers.clear();
    _polygons.clear();
    setState(() {});
  }

  void _fitCameraToPolygon() {
    if (_gCtrl == null || _polygonPoints.isEmpty) return;

    double minLat = _polygonPoints.first.latitude;
    double maxLat = _polygonPoints.first.latitude;
    double minLng = _polygonPoints.first.longitude;
    double maxLng = _polygonPoints.first.longitude;

    for (final p in _polygonPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    _gCtrl!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

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

  Future<void> _updateFarm() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final user = _auth.currentUser!;
      String? imageUrl = _currentImageUrl;

      if (_imageBytes != null || _farmImage != null) {
        final ref = _storage
            .ref()
            .child(
              'farm_images/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg',
            );
        final meta = SettableMetadata(contentType: 'image/jpeg');

        if (kIsWeb && _imageBytes != null) {
          await ref.putData(_imageBytes!, meta);
        } else if (_farmImage != null) {
          await ref.putFile(_farmImage!, meta);
        }
        imageUrl = (await ref.getDownloadURL()).replaceAll(RegExp(r'\s+'), '');
      }

      final polygonData = _polygonPoints
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList();

      await _db.collection('farms').doc(farmId).update({
        'farmName': _farmNameController.text.trim(),
        'ownerName': _ownerNameController.text.trim(),
        'farmSize': _farmSizeController.text.trim(),
        'region': _selectedRegion,
        'notes': _notesController.text.trim(),
        'polygon': polygonData,
        'imageURL': imageUrl?.replaceAll(RegExp(r'\s+'), ''),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر التعديل: $e', style: GoogleFonts.almarai()),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: darkBackground,

        // -------------------- الـ AppBar المُعدّل (لزر الرجوع الدائري في اليمين) --------------------
        appBar: AppBar(
          backgroundColor: darkBackground,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false, // نتحكم بالزر يدويًا

          // 1. زر الرجوع الدائري (السهم) في اليمين (Leading)
          leading: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: Material(
              color: Colors.black45, // نفس الخلفية الدائرية
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                // العودة إلى صفحة المزارع
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
            ),
          ),

          // 2. العنوان في المنتصف
          title: Text(
            'تعديل المزرعة',
            style: GoogleFonts.almarai(color: Colors.white),
          ),

          // 3. Placeholder للمحاذاة في اليسار
          actions: [const SizedBox(width: 56)],
        ),
        // -------------------- نهاية الـ AppBar المُعدّل --------------------

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
                _form(),
                const SizedBox(height: 16),
                _imagePreview(),
                const SizedBox(height: 24),
                _map(),
                const SizedBox(height: 12),
                _polygonActions(),
                const SizedBox(height: 16),
                _saveBtn(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() {
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
            _tf(_farmNameController, 'اسم المزرعة', Icons.grass),
            const SizedBox(height: 16),
            _tf(_ownerNameController, 'اسم المالك', Icons.person),
            const SizedBox(height: 16),
            _tf(
              _farmSizeController,
              'مساحة المزرعة (م²)',
              Icons.straighten,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _region(),
            const SizedBox(height: 16),
            _tf(
              _notesController,
              'ملاحظات (اختياري)',
              Icons.notes,
              optional: true,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(
                Icons.add_photo_alternate_rounded,
                color: secondaryColor,
              ),
              label: const Text(
                'تغيير الصورة',
                style: TextStyle(color: secondaryColor),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(25, 255, 255, 255),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: const BorderSide(color: secondaryColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePreview() {
    final hasNewBytes = _imageBytes != null;
    final hasNewFile = _farmImage != null;
    final hasOldUrl =
        (_currentImageUrl != null && _currentImageUrl!.isNotEmpty);

    if (!hasNewBytes && !hasNewFile && !hasOldUrl) {
      return const SizedBox.shrink();
    }

    Widget img;
    if (hasNewBytes) {
      img = Image.memory(_imageBytes!, height: 150, fit: BoxFit.cover);
    } else if (hasNewFile) {
      img = Image.file(_farmImage!, height: 150, fit: BoxFit.cover);
    } else {
      img = Image.network(_currentImageUrl!, height: 150, fit: BoxFit.cover);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: img,
    );
  }

  Widget _tf(
    TextEditingController c,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    bool optional = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: c,
      keyboardType: keyboardType,
      textAlign: TextAlign.right,
      maxLines: maxLines,
      style: GoogleFonts.almarai(color: Colors.white),
      validator: (v) {
        if (!optional && (v == null || v.isEmpty)) return 'هذا الحقل مطلوب';
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
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(15.0)),
          borderSide: BorderSide(color: Color.fromARGB(76, 253, 203, 110)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(15.0)),
          borderSide: BorderSide(color: secondaryColor, width: 2),
        ),
      ),
    );
  }

  Widget _region() {
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
      initialValue: _selectedRegion, // ✅ بديل value (لتفادي التحذير deprecated)
      isExpanded: true,
      hint: Text('اختر منطقة', style: GoogleFonts.almarai(color: Colors.white54)),
      onChanged: (v) => setState(() => _selectedRegion = v),
      items:
          _saudiRegions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
      validator: (v) => v == null ? 'الرجاء اختيار منطقة' : null,
    );
  }

  Widget _map() {
    return SizedBox(
      height: 350,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: GoogleMap(
          mapType: MapType.hybrid,
          initialCameraPosition: _initialCamera,
          onMapCreated: (c) {
            _gCtrl = c;
            _fitCameraToPolygon();
          },
          onTap: _onMapTap,
          polygons: _polygons,
          markers: _markers,
          zoomControlsEnabled: true,
          compassEnabled: false,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
        ),
      ),
    );
  }

  Widget _polygonActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton.icon(
          onPressed: _undoLastPoint,
          icon: const Icon(Icons.undo, color: Color(0xFF042C25)),
          label: Text('تراجع', style: GoogleFonts.almarai(color: Color(0xFF042C25))),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFDCB6E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _clearPolygon,
          icon: const Icon(Icons.clear_all, color: Colors.white),
          label: Text('مسح النقاط', style: GoogleFonts.almarai(color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _saveBtn() {
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
            onTap: _isSaving ? null : _updateFarm,
            child: Center(
              child: _isSaving
                  ? const CircularProgressIndicator(
                      strokeWidth: 3, color: Color(0xFF042C25),
                    )
                  : Text(
                      'حفظ التعديلات',
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
