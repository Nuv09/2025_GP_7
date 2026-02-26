// lib/edit_farm_page.dart
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data' as td show Uint8List;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:saafapp/constant.dart';

// // ✅ Reverse Geocoding
// import 'package:geocoding/geocoding.dart' show Placemark, placemarkFromCoordinates, Location, locationFromAddress;

// // ✅ Session token لِـ Places
// import 'package:uuid/uuid.dart';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:saafapp/secrets.dart';
import 'package:flutter/services.dart';


const Color primaryColor = Color(0xFF1E8D5F);
const Color secondaryColor = Color(0xFFFDCB6E);
const Color darkBackground = Color(0xFF042C25);

class EditFarmPage extends StatefulWidget {
  const EditFarmPage({super.key});

  @override
  State<EditFarmPage> createState() => _EditFarmPageState();
}

class _EditFarmPageState extends State<EditFarmPage> {
   bool _isInitialized = false;
  final _formKey = GlobalKey<FormState>();
  final _farmNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _farmSizeController = TextEditingController();
  final _notesController = TextEditingController();

  // 🔎 البحث
  final _searchCtrl = TextEditingController();

// final String _placesKey = Secrets.placesKey;

  // // Autocomplete state
  // final _uuid = const Uuid();
  // String _sessionToken = '';
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  bool _loadingSuggest = false;

  final List<String> _saudiRegions = const [
    'الرياض','مكة المكرمة','المدينة المنورة','القصيم','الشرقية','عسير','تبوك',
    'حائل','الحدود الشمالية','جازان','نجران','الباحة','الجوف',
  ];
  String? _selectedRegion;

  // صورة
  File? _farmImage;
  td.Uint8List? _imageBytes;
  String? _currentImageUrl;


// خريطة (MapTiler & Flutter Map)
  final MapController _mapController = MapController();
  LatLng _currentCenter = const LatLng(24.774265, 46.738586);

  List<Polygon> _polygons = [];
  List<Marker> _markers = [];
  final List<LatLng> _polygonPoints = [];


  // Firebase
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  late String farmId;
  Map<String, dynamic> init = {};

  bool _isSaving = false;

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  
  if (!_isInitialized) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
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

    WidgetsBinding.instance.addPostFrameCallback((_) => _fitCameraToPolygon());
    
    _isInitialized = true; // نضعها true لكي لا يتكرر الكود مرة أخرى
  }
}

  @override
  void dispose() {
    _farmNameController.dispose();
    _ownerNameController.dispose();
    _farmSizeController.dispose();
    _notesController.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ========= Helpers =========

  
void _rebuildOverlays() {
  // تحويل النقاط إلى Markers تناسب Flutter Map
  _markers = _polygonPoints.map((point) {
    return Marker(
      point: point,
      width: 40,
      height: 40,
      child: const Icon(
        Icons.location_on,
        color: Colors.green,
        size: 30,
      ),
    );
  }).toList();

  // بناء المضلع (Polygon)
  _polygons = [
    if (_polygonPoints.length >= 3)
      Polygon(
        points: _polygonPoints,
        color: const Color.fromARGB(75, 215, 172, 92),
        borderColor: const Color.fromARGB(255, 2, 79, 25),
        borderStrokeWidth: 3,
      ),
  ];

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
    if (_polygonPoints.isEmpty) return;

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

    // حساب المركز يدويًا لتحريك خريطة MapTiler
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    
    _mapController.move(LatLng(centerLat, centerLng), 15); 
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
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

  bool _isPolygonChanged() {
    final oldPoly = (init['polygon'] as List?) ?? [];
    if (oldPoly.length != _polygonPoints.length) return true;

    for (int i = 0; i < _polygonPoints.length; i++) {
      final newP = _polygonPoints[i];
      final oldP = oldPoly[i];
      final oldLat = (oldP['lat'] as num).toDouble();
      final oldLng = (oldP['lng'] as num).toDouble();
      if ((newP.latitude - oldLat).abs() > 1e-7 ||
          (newP.longitude - oldLng).abs() > 1e-7) {
        return true;
      }
    }
    return false;
  }


void _onSearchChanged(String value) {
  if (_debounce?.isActive ?? false) _debounce!.cancel();

  _debounce = Timer(const Duration(milliseconds: 500), () async {
    if (value.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    await _fetchMapTilerSuggestions(value);
  });
}

Future<void> _fetchMapTilerSuggestions(String input) async {
  setState(() => _loadingSuggest = true);
  final url = 'https://api.maptiler.com/geocoding/$input.json?key=${Secrets.mapTilerKey}&country=sa&language=ar';

  try {
    final res = await http.get(Uri.parse(url));
    final data = jsonDecode(res.body);
    final List features = data['features'] ?? [];

    setState(() {
      _suggestions = features.map((e) => {
        'primary': e['text_ar'] ?? e['text'], 
        'secondary': e['place_name_ar'] ?? e['place_name'],
        'center': e['center'], // هذا يعطينا [lng, lat]
      }).toList();
    });
  } catch (e) {
    debugPrint('MapTiler Error: $e');
  } finally {
    setState(() => _loadingSuggest = false);
  }
}

void _moveToMapTilerLocation(List<dynamic> center) {
  // center[1] هو Latitude (العرض)
  // center[0] هو Longitude (الطول)
  final newLatLng = LatLng(center[1], center[0]); 
  
  _mapController.move(newLatLng, 15); 

  setState(() {
    _currentCenter = newLatLng;
    _suggestions = []; 
    _searchCtrl.clear(); 
  });
}

  LatLng? _tryParseLatLng(String s) {
    final m = RegExp(r'^\s*([+-]?\d+(\.\d+)?)[\s,]+([+-]?\d+(\.\d+)?)\s*$').firstMatch(s);
    if (m == null) return null;
    final lat = double.tryParse(m.group(1)!);
    final lng = double.tryParse(m.group(3)!);
    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return LatLng(lat, lng);
  }

Future<void> _searchAndGo() async {
    final text = _searchCtrl.text.trim();
    if (text.isEmpty) return;

    // محاولة التعرف إذا كان المدخل إحداثيات مباشرة
    final coord = _tryParseLatLng(text);
    if (coord != null) {
      _mapController.move(coord, 15);
      setState(() => _currentCenter = coord);
      return;
    }

try {
      // نطلب الإحداثيات من MapTiler بناءً على النص المدخل
      final url = 'https://api.maptiler.com/geocoding/$text.json?key=${Secrets.mapTilerKey}&country=sa&language=ar';
      
      // أضيفي كلمة await هنا ليختفي اللون الأصفر
      final res = await http.get(Uri.parse(url)); 
      
      final data = jsonDecode(res.body);
      
      if (data['features'] != null && data['features'].isNotEmpty) {
        final coords = data['features'][0]['center']; // [longitude, latitude]
        final newLatLng = LatLng(coords[1], coords[0]);
        
        _mapController.move(newLatLng, 15);
        setState(() {
          _currentCenter = newLatLng;
        });
      }
    } catch (e) {
      debugPrint('MapTiler Search error: $e');
      _snack('تعذر العثور على الموقع المطلوب', error: true);
    }
  }
  
  // ======== تحليل وخدمات ========

  // تشغيل التحليل على Cloud Run
  Future<void> _startAnalysis(String farmId) async {
    try {
      final uri = Uri.parse('https://saaf-analyzer-new-120954850101.us-central1.run.app/analyze');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'farmId': farmId}),
      );
      if (res.statusCode != 200) {
        _snack('تم إرسال التحديث والتحليل سيبدأ، لكن وردت استجابة غير متوقعة.', warn: true);
      }
    } catch (e) {
      debugPrint('startAnalysis error: $e');
    }
  }

  void _snack(String msg, {bool error = false, bool warn = false}) {
    if (!mounted) return;
    final bg = error ? const Color(0xFFB00020) : (warn ? const Color(0xFF5E5E5E) : primaryColor);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bg,
        content: Text(msg, style: GoogleFonts.almarai(color: Colors.white)),
      ),
    );
  }

  // ======== Helpers للتحقق من المنطقة ========

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
    if (_polygonPoints.isEmpty) return null;
    final c = _centroid(_polygonPoints);
    
    // نطلب اسم المنطقة من MapTiler باستخدام الإحداثيات
    final url = 'https://api.maptiler.com/geocoding/${c.longitude},${c.latitude}.json?key=${Secrets.mapTilerKey}&language=ar';
    
    final res = await http.get(Uri.parse(url));
    final data = jsonDecode(res.body);
    
    if (data['features'] != null && data['features'].isNotEmpty) {
      for (var feature in data['features']) {
        // نبحث عن التصنيف الذي يمثل المنطقة (province) أو الإقليم (region)
        if (feature['place_type'].contains('province') || feature['place_type'].contains('region')) {
          return feature['text_ar'] ?? feature['text'];
        }
      }
      return data['features'][0]['text_ar'] ?? data['features'][0]['text'];
    }
    return null;
  } catch (e) {
    debugPrint('MapTiler Reverse  error: $e');
    return null;
  }
}
  String _normalize(String s) {
    if (s.isEmpty) return s;
    final noTashkeel = s.replaceAll(RegExp(r'[\u064B-\u0652]'), '');
    var t = noTashkeel
        .replaceAll('منطقة', '')
        .replaceAll('امارة', '')
        .replaceAll('إمارة', '')
        .replaceAll('مدينة', '')
        .replaceAll('محافظة', '')
        .replaceAll('السعودية', '')
        .replaceAll('المملكةالعربيةالسعودية', '')
        .replaceAll('ال', '')
        .replaceAll('ـ', '')
        .replaceAll(' ', '')
        .toLowerCase();

    final map = {
      'مكهالمكرمه': 'مكةالمكرمة','مكه': 'مكةالمكرمة','الرياض': 'الرياض','الشرقيه': 'الشرقية',
      'المدينهالمنوره': 'المدينةالمنورة','تبوك': 'تبوك','حايل': 'حائل','جازان': 'جازان',
      'نجران': 'نجران','الجوف': 'الجوف','الباحه': 'الباحة','عسير': 'عسير','القصيم': 'القصيم',
      'الحدودالشماليه': 'الحدودالشمالية',
      'riyadh': 'الرياض','abha': 'عسير','asir': 'عسير','makkah': 'مكةالمكرمة','mecca': 'مكةالمكرمة',
      'easternprovince': 'الشرقية','alqassim': 'القصيم','qassim': 'القصيم','madinah': 'المدينةالمنورة',
      'medina': 'المدينةالمنورة','aljawf': 'الجوف','jawf': 'الجوف','hail': 'حائل','tabuk': 'تبوك',
      'jazan': 'جازان','gazaan': 'جازان','najran': 'نجران','albaha': 'الباحة','baha': 'الباحة',
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
          backgroundColor: const Color(0xFF042C25), // ← الخلفية المطلوبة
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.almarai(
              color: const Color(0xFFFFF6E0), // ← لون النص البيج
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.almarai(
              color: const Color(0xFFFFF6E0), // ← لون النص البيج
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
                  color: const Color(0xFFFFF6E0), // ← بيج
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
                style: GoogleFonts.almarai(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ) ??
      false;
}

  // ======== حفظ التعديلات ========
  Future<void> _updateFarm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_polygonPoints.length < 3) {
      _snack('حدد 3 نقاط على الأقل لحدود المزرعة.', error: true);
      return;
    }

    // تحقق المنطقة
    if (_selectedRegion != null && _selectedRegion!.trim().isNotEmpty) {
      try {
        final detected = await _reverseRegionFromCentroid();
        if (detected != null && detected.isNotEmpty) {
          final a = _normalize(_selectedRegion!);
          final b = _normalize(detected);
          final match = a.contains(b) || b.contains(a);
          if (!match) {
            final ok = await _confirmDialog(
              'تحذير عدم تطابق المنطقة',
              'المنطقة المختارة: "${_selectedRegion!}"\n'
              'إحداثيات الخريطة تشير إلى: "$detected"\n\n'
              'هل تريد المتابعة رغم عدم التطابق؟',
            );
            if (!ok) return;
          }
        }
      } catch (e) {
        debugPrint('region check error: $e');
      }
    }

    setState(() => _isSaving = true);
    try {
      final user = _auth.currentUser!;
      final polygonData = _polygonPoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();

      final polygonChanged = _isPolygonChanged();

      final baseUpdate = <String, dynamic>{
        'farmName': _farmNameController.text.trim(),
        'ownerName': _ownerNameController.text.trim(),
        'farmSize': _farmSizeController.text.trim(),
        'region': _selectedRegion,
        'notes': _notesController.text.trim(),
        'polygon': polygonData,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (polygonChanged) {
        await _db.collection('farms').doc(farmId).update({
          ...baseUpdate,
          'status': 'pending',
          'finalCount': 0,
          'finalQuality': 0.0,
          'errorMessage': null,
          'reanalysisRequestedAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          '/analysis',
          arguments: {'farmId': farmId},
        );

        // رفع الصورة (إن تغيّرت) + بدء التحليل (بدون انتظار)
        Future(() async {
          try {
            String? imageUrl = _currentImageUrl;

            if (_imageBytes != null || _farmImage != null) {
              final ref = _storage.ref().child(
                'farm_images/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg',
              );
              final meta = SettableMetadata(contentType: 'image/jpeg');

              if (kIsWeb && _imageBytes != null) {
                await ref.putData(_imageBytes!, meta);
              } else if (_farmImage != null) {
                await ref.putFile(_farmImage!, meta);
              }
              imageUrl = (await ref.getDownloadURL()).replaceAll(RegExp(r'\s+'), '');
              await _db.collection('farms').doc(farmId).update({'imageURL': imageUrl});
            }

            await _startAnalysis(farmId);
          } catch (e) {
            debugPrint('post-nav upload/analyze error: $e');
          }
        });

        return;
      } else {
        String? imageUrl = _currentImageUrl;

        if (_imageBytes != null || _farmImage != null) {
          final ref = _storage.ref().child(
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

        await _db.collection('farms').doc(farmId).update({
          ...baseUpdate,
          'imageURL': imageUrl,
        });

        if (!mounted) return;
        _snack('تم حفظ التعديلات.');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      _snack('تعذر التعديل: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: darkBackground,

        appBar: AppBar(
          backgroundColor: darkBackground,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.only(right: 7, left: 14),
                  child: Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
            ),
          ),
          title: Text('تعديل المزرعة', style: saafPageTitle),
          actions: const [SizedBox(width: 56)],
        ),

        body: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + kBottomNavigationBarHeight + MediaQuery.of(context).viewPadding.bottom + 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Icon(Icons.agriculture_rounded, color: secondaryColor, size: 50),
                ),
                const SizedBox(height: 10),
                _form(),
                const SizedBox(height: 16),
                _imagePreview(),
                const SizedBox(height: 24),
                _mapWithSearch(), // ✅ الخريطة مع شريط بحث + اقتراحات
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
            _buildReadonlyContract(),   // ← أضيفي هذا السطر هنا بالضبط

            const SizedBox(height: 16),
            _tf(_farmSizeController, 'مساحة المزرعة (م²)', Icons.straighten, keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            _region(),
            const SizedBox(height: 16),
            
            _tf(_notesController, 'ملاحظات (اختياري)', Icons.notes, optional: true, maxLines: 3),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.add_photo_alternate_rounded, color: secondaryColor),
              label: const Text('تغيير الصورة', style: TextStyle(color: secondaryColor)),
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
    final hasOldUrl = (_currentImageUrl != null && _currentImageUrl!.isNotEmpty);

    if (!hasNewBytes && !hasNewFile && !hasOldUrl) return const SizedBox.shrink();

    Widget img;
    if (hasNewBytes) {
      img = Image.memory(_imageBytes!, height: 150, fit: BoxFit.cover);
    } else if (hasNewFile) {
      img = Image.file(_farmImage!, height: 150, fit: BoxFit.cover);
    } else {
      img = Image.network(_currentImageUrl!, height: 150, fit: BoxFit.cover);
    }

    return ClipRRect(borderRadius: BorderRadius.circular(15), child: img);
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
      initialValue: _selectedRegion,
      isExpanded: true,
      hint: Text('اختر منطقة', style: GoogleFonts.almarai(color: Colors.white54)),
      onChanged: (v) => setState(() => _selectedRegion = v),
      items: _saudiRegions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
      validator: (v) => v == null ? 'الرجاء اختيار منطقة' : null,
    );
  }

  Widget _buildReadonlyContract() {
  final contract = (init['contractNumber'] ?? '').toString().trim();

  if (contract.isEmpty) return const SizedBox.shrink();

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    decoration: BoxDecoration(
      color: const Color.fromARGB(25, 255, 255, 255),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color.fromARGB(76, 253, 203, 110)),
    ),
    child: Row(
      children: [
        const Icon(Icons.confirmation_number, color: secondaryColor),
        const SizedBox(width: 10),

        // رقم العقد
        Expanded(
          child: Text(
            'رقم العقد: $contract',
            style: GoogleFonts.almarai(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),

        // زر النسخ
        IconButton(
          icon: const Icon(Icons.copy, color: secondaryColor),
          tooltip: 'نسخ رقم العقد',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: contract));

            if (!mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'تم نسخ رقم العقد',
                  style: GoogleFonts.almarai(color: Colors.white),
                ),
                backgroundColor: primaryColor,
              ),
            );
          },
        ),
      ],
    ),
  );
}


Widget _mapWithSearch() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        height: 380, // نفس ارتفاع خريطة صفحة الإضافة
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: Stack(
            children: [
              // 1. الخريطة الأساسية (MapTiler)
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _polygonPoints.isNotEmpty ? _polygonPoints.first : _currentCenter,
                  initialZoom: 15.0,
                  onTap: (tapPosition, point) => _onMapTap(point),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://api.maptiler.com/maps/hybrid/{z}/{x}/{y}.jpg?key=${Secrets.mapTilerKey}',
                    userAgentPackageName: 'com.saaf.app',
                  ),
                  if (_polygons.isNotEmpty) PolygonLayer(polygons: _polygons),
                  MarkerLayer(markers: _markers),
                ],
              ),
              Positioned(
                bottom: 20,
                left: 15, 
                child: Column(
                  children: [
                    _buildCustomMapButton(
                      icon: Icons.add,
                      onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1),
                    ),
                    _buildCustomMapButton(
                      icon: Icons.remove,
                      onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1),
                    ),
                    _buildCustomMapButton(
                      icon: Icons.explore_outlined,
                      onPressed: () => _mapController.rotate(0), 
                    ),
                  ],
                ),
              ),

              // 3. شريط البحث  
              Positioned(
                top: 15,
                left: 15,
                right: 15,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(30),
                  color: Colors.white,
                  child: Row(
                    children: [
                      const SizedBox(width: 15),
                      const Icon(Icons.search, color: primaryColor), 
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: _onSearchChanged,
                          onSubmitted: (_) => _searchAndGo(),
                          decoration: InputDecoration(
                            hintText: 'ابحث عن موقع المزرعة...',
                            hintStyle: GoogleFonts.almarai(color: Colors.black45, fontSize: 14),
                            border: InputBorder.none,
                          ),
                          style: GoogleFonts.almarai(color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 4. قائمة الاقتراحات (Autocomplete)
              if (_suggestions.isNotEmpty || _loadingSuggest)
                Positioned(
                  top: 70,
                  left: 20,
                  right: 20,
                  child: Material(
                    elevation: 10,
                    borderRadius: BorderRadius.circular(15),
                    color: Colors.white,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: _loadingSuggest
                          ? const Padding(
                              padding: EdgeInsets.all(15),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: _suggestions.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final s = _suggestions[i];
                                return ListTile(
                                  leading: const Icon(Icons.location_on, color: secondaryColor),
                                  title: Text(
                                    s['primary'] ?? '',
                                    style: GoogleFonts.almarai(fontSize: 14, color: Colors.black87),
                                  ),
                                  subtitle: Text(
                                    s['secondary'] ?? '',
                                    style: GoogleFonts.almarai(fontSize: 12, color: Colors.black54),
                                  ),
onTap: () {
  final coords = s['center']; 
  setState(() {
    _suggestions = [];
    _loadingSuggest = false;
  });
  _moveToMapTilerLocation(coords); 
  FocusScope.of(context).unfocus(); 
},                              
                                );
                              },
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
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
          gradient: const LinearGradient(colors: [Color(0xFFEBB974), Color(0xFFFFF6E0)]),
          borderRadius: BorderRadius.circular(35),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _isSaving ? null : _updateFarm,
            child: Center(
              child: _isSaving
                  ? const CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF042C25))
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
  Widget _buildCustomMapButton({required IconData icon, required VoidCallback onPressed}) {
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    child: Material(
      color: Colors.white.withValues(alpha: 0.9), 
      borderRadius: BorderRadius.circular(12),
      elevation: 4,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 44, height: 44,
          child: Icon(icon, color: darkBackground, size: 26),
        ),
      ),
    ),
  );
}

}
