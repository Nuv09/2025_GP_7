import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:saafapp/constant.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:image_picker/image_picker.dart';
// import 'package:uuid/uuid.dart'; // ✅ لِـ session token

// Firebase
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:saafapp/secrets.dart';
import 'dart:ui';



// ألوان
const Color primaryColor = Color(0xFF1E8D5F);
const Color secondaryColor = Color(0xFFEBB974); 
const Color darkBackground = Color(0xFF042C25);

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
  final _contractNumberController = TextEditingController(); // رقم العقد


  // بحث الخريطة
  final _searchCtrl = TextEditingController();

  String? _selectedRegion;

  // صورة (ويب/موبايل)
  File? _farmImage; 
  Uint8List? _imageBytes; // للويب

final MapController _mapController = MapController();
LatLng _currentCenter = const LatLng(24.774265, 46.738586);

final List<LatLng> _polygonPoints = [];
List<Polygon> _polygons = [];
List<Marker> _markers = [];
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

  // === Google Places (Autocomplete + Details) ===
  // ⚠️ ملاحظة أمنية: يفضّل تمرير المفتاح عبر dart-define وليس هاردكود.
  // مثال تشغيل: flutter run --dart-define=PLACES_KEY=AIza... (وشيّكي قيود المفتاح في Google Cloud)
// final String _placesKey = Secrets.placesKey;

//   final _uuid = const Uuid();
//   String _sessionToken = '';
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  bool _loadingSuggest = false;




  // === أداة تنظيف روابط الصور (إزالة فراغات/أسطر + فك %252F) ===
  String _cleanUrl(String? raw) {
    if (raw == null) return '';
    var u = raw.replaceAll(RegExp(r'\s+'), '');
    if (u.contains('%252F')) u = Uri.decodeFull(u);
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
    _contractNumberController.dispose();
    _debounce?.cancel(); // ✅ ألغِ الـ debounce
    super.dispose();
  }

  // =================== الموقع الحالي ===================

  Future<void> _centerToMyLocation() async {
  try {
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    // تحديث الإحداثيات المركزية
    setState(() {
      _currentCenter = LatLng(pos.latitude, pos.longitude);
    });
    // تحريك خريطة MapTiler للموقع الجديد
    _mapController.move(_currentCenter, 15); 
    
    if (mounted) setState(() {});
  } catch (e) {
    debugPrint('location error: $e');
  }
}

  // =================== البحث (Geocoding احتياطي) ===================
Future<void> _searchAndGo() async {
  final text = _searchCtrl.text.trim();
  if (text.isEmpty) return;

  try {
    // نطلب الإحداثيات من MapTiler بناءً على النص المدخل
    final url = 'https://api.maptiler.com/geocoding/$text.json?key=${Secrets.mapTilerKey}&country=sa&language=ar';
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
  }
}

  // =================== Helpers للبحث ===================
  // ignore: unused_element
  LatLng? _tryParseLatLng(String s) {
    final m = RegExp(r'^\s*([+-]?\d+(\.\d+)?)[\s,]+([+-]?\d+(\.\d+)?)\s*$')
        .firstMatch(s);
    if (m == null) return null;
    final lat = double.tryParse(m.group(1)!);
    final lng = double.tryParse(m.group(3)!);
    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return LatLng(lat, lng);
  }
  
// ignore: unused_element
  double _dist2(LatLng a, LatLng b) {
    final dx = a.latitude - b.latitude;
    final dy = a.longitude - b.longitude;
    return dx * dx + dy * dy; // مسافة تربيعية كافية للمقارنة
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
    if (_polygonPoints.isEmpty) return null;
    final c = _centroid(_polygonPoints);
    
    // نطلب اسم المنطقة من MapTiler باستخدام الإحداثيات
    final url = 'https://api.maptiler.com/geocoding/${c.longitude},${c.latitude}.json?key=${Secrets.mapTilerKey}&language=ar';
    
    final res = await http.get(Uri.parse(url));
    final data = jsonDecode(res.body);
    
    if (data['features'] != null && data['features'].isNotEmpty) {
      for (var feature in data['features']) {
        // نبحث عن التصنيف الذي يمثل المنطقة أو المحافظة
        if (feature['place_type'].contains('province') || feature['place_type'].contains('region')) {
          return feature['text_ar'] ?? feature['text'];
        }
      }
      return data['features'][0]['text_ar'] ?? data['features'][0]['text'];
    }
    return null;
  } catch (e) {
    debugPrint('MapTiler Reverse Geocoding error: $e');
    return null;
  }
}

  String _normalize(String s) {
    if (s.isEmpty) return s;
    // إزالة تشكيل
    final noTashkeel = s.replaceAll(RegExp(r'[\u064B-\u0652]'), '');
    // إزالة كلمات عامة والتعريف وبعض الرموز
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

    // خرائط لأسماء شائعة
    final map = {
      // عربي -> موحّد
      'مكهالمكرمه': 'مكةالمكرمة',
      'مكه': 'مكةالمكرمة',
      'الرياض': 'الرياض',
      'الشرقيه': 'الشرقية',
      'المدينهالمنوره': 'المدينةالمنورة',
      'تبوك': 'تبوك',
      'حايل': 'حائل',
      'جازان': 'جازان',
      'نجران': 'نجران',
      'الجوف': 'الجوف',
      'الباحه': 'الباحة',
      'عسير': 'عسير',
      'القصيم': 'القصيم',
      'الحدودالشماليه': 'الحدودالشمالية',

      // إنجليزي -> عربي موحّد
      'riyadh': 'الرياض',
      'abha': 'عسير', // أبها مدينة ضمن عسير
      'asir': 'عسير',
      'makkah': 'مكةالمكرمة',
      'mecca': 'مكةالمكرمة',
      'easternprovince': 'الشرقية',
      'alqassim': 'القصيم',
      'qassim': 'القصيم',
      'madinah': 'المدينةالمنورة',
      'medina': 'المدينةالمنورة',
      'aljawf': 'الجوف',
      'jawf': 'الجوف',
      'hail': 'حائل',
      'tabuk': 'تبوك',
      'jazan': 'جازان',
      'gazaan': 'جازان',
      'najran': 'نجران',
      'albaha': 'الباحة',
      'baha': 'الباحة',
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
        builder: (ctx) => BackdropFilter(
  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
  child: AlertDialog(
          backgroundColor: const Color(0xFF042C25), 
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.almarai(
              color: const Color(0xFFFFF6E0), 
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.almarai(
              color: const Color(0xFFFFF6E0), 
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
                  color: const Color(0xFFFFF6E0), 
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
                  color: const Color(0xFF042C25),
                ),
              ),
            ),
          ],
        ),
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
  // 🔧 ننشئ الوثيقة أولاً، ننتقل لصفحة الانتظار، ثم نرفع الصورة ونستدعي التحليل بشكل غير منتظر.
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
      DocumentReference<Map<String, dynamic>>? contractRef;

      try {
        final user = _auth.currentUser;
        if (user == null) {
          _showSnackBar('يجب تسجيل الدخول أولاً.', isError: true);
          if (mounted) setState(() => _isSaving = false);
          return;
        }
        final contract = _contractNumberController.text
    .replaceAll(RegExp(r'\s+'), '') // removes ALL spaces/newlines, not just ends
    .trim();

// ✅ تحقق أن رقم العقد 10 إلى 12 رقم
final isValidContract = RegExp(r'^[0-9]{10,12}$').hasMatch(contract); // matches rules expectations
if (!isValidContract) {
  _showSnackBar('Contract must be 10–12 digits (0-9).', isError: true);
  if (mounted) setState(() => _isSaving = false);
  return;
}

contractRef = _db.collection('contracts').doc(contract);

try {
  await _db.runTransaction((tx) async {
    final snap = await tx.get(contractRef!);
    if (snap.exists) {
      throw 'contract-taken'; // نحن نحدد هذا الخطأ يدوياً
    }
    tx.set(contractRef, {
      'ownerUid': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  });
}  catch (e) {
  if (e == 'contract-taken') {
    _showSnackBar('هذه المزرعة مضافة مسبقًا', isError: true);
  } else if (e is FirebaseException) {
    debugPrint('🔥 FirebaseException code=${e.code} message=${e.message}');
    _showSnackBar('Firestore error: ${e.code}', isError: true);
  } else {
    debugPrint('🔥 Unknown error: $e');
    _showSnackBar('Unexpected error.', isError: true);
  }
  if (mounted) setState(() => _isSaving = false);
  return;
}






        final polygonData = _polygonPoints
            .map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();

        // ✅ ننشئ الوثيقة أولاً بدون انتظار
        final docRef = await _db.collection('farms').add({
          'farmName': _farmNameController.text.trim(),
          'ownerName': _ownerNameController.text.trim(),
          'farmSize': _farmSizeController.text.trim(),
          'region': _selectedRegion,
          'notes': _notesController.text.trim(),
          'polygon': polygonData,
          'imageURL': null,
          'imagePath': null,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': user.uid,
          'contractNumber': contract,


          // حالة التحليل والنتيجة الابتدائية
          'status': 'pending',
          'finalCount': 0,
          'finalQuality': 0.0,
          'errorMessage': null,
        });

        // ✅ ننتقل فورًا لصفحة الانتظار/التحليل
        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          '/analysis',
          arguments: {'farmId': docRef.id},
        );

        // ⬇️ بعد التنقل: نرفع الصورة (إن وُجدت) ونحدّث الوثيقة — لا ننتظر
        Future(() async {
          try {
            String? imageUrl;
            String? imagePath;

            if (_imageBytes != null || _farmImage != null) {
              final ref = _storage.ref().child(
                  'farm_images/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg');
              final meta = SettableMetadata(contentType: 'image/jpeg');

              UploadTask task = (kIsWeb && _imageBytes != null)
                  ? ref.putData(_imageBytes!, meta)
                  : ref.putFile(_farmImage!, meta);

              await task.timeout(const Duration(seconds: 90));
              imageUrl = _cleanUrl(await ref.getDownloadURL());
              imagePath = ref.fullPath;

              await docRef.update({
                'imageURL': imageUrl,
                'imagePath': imagePath,
              });
            }
          } catch (e) {
            debugPrint('post-nav image upload/update error: $e');
          }
        });

        // ⬇️ إطلاق خدمة التحليل — لا ننتظر
        Future(() async {
          try {
            final response = await http.post(
              Uri.parse(
                  'https://saaf-analyzer-new-120954850101.us-central1.run.app/analyze'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'farmId': docRef.id}),
            );
            if (response.statusCode != 200) {
              debugPrint('Analyzer non-200: ${response.statusCode} ${response.body}');
            }
          } catch (e) {
            debugPrint('خطأ في بدء التحليل: $e');
          }
        });

        // لا مزيد من setState هنا لأننا غادرنا الصفحة
      } catch (e) {
        

        _showSnackBar('حدث خطأ أثناء حفظ البيانات: $e', isError: true);
        if (mounted) setState(() => _isSaving = false);
      } finally {
        // لو ما تنقلنا لأي سبب، أعد الحالة
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

  // =================== Autocomplete & Details ===================

void _onSearchChanged(String value) {
  if (_debounce?.isActive ?? false) _debounce!.cancel();

  _debounce = Timer(const Duration(milliseconds: 500), () async {
    if (value.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    // لم نعد بحاجة لـ sessionToken هنا لأننا نستخدم MapTiler
    await _fetchMapTilerSuggestions(value);
  });
}

Widget _buildLuxBackground() {
  return Positioned.fill(
    child: Stack(
      children: [
        // Base gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Color(0xFF05352D),
                Color(0xFF042C25),
                Color(0xFF031E1A),
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),

        // Gold glow
        Positioned(
          top: -120,
          right: -80,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  secondaryColor.withValues(alpha: 0.25),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),

        // Teal glow
        Positioned(
          bottom: -140,
          left: -120,
          child: Container(
            width: 360,
            height: 360,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF0C6B5C).withValues(alpha: 0.18),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),

        // Vignette
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.18),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.25),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
      ],
    ),
  );
}

  // =================== واجهة المستخدم ===================
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: darkBackground,

        appBar: AppBar(
  backgroundColor: const Color(0xFF042C25).withValues(alpha: 0.7),
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
          leading: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: Material(
              color: Colors.white.withValues(alpha: 0.08),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context)
                    .pushNamedAndRemoveUntil('/main', (route) => false),
                child: const Padding(
                  padding: EdgeInsets.only(right: 7, left: 14),
                  child: Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
            ),
          ),
          title: Text('إضافة مزرعة جديدة', style: saafPageTitle),
        ),

        body: Stack(
  children: [
    _buildLuxBackground(),
    SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16 + kToolbarHeight + MediaQuery.of(context).padding.top,
          16,
          16 +
              kBottomNavigationBarHeight +
              MediaQuery.of(context).viewPadding.bottom +
              40,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            const SizedBox(height: 10),
            Center(
              child: Icon(
                Icons.agriculture_rounded,
                color: secondaryColor,
                size: 50,
              ),
            ),
            const SizedBox(height: 10),

            _buildFarmForm(),
            const SizedBox(height: 30),
            _buildMapSection(),
            const SizedBox(height: 20),
            _buildSubmitButton(),
          ],
        ),
      ),
    ),
  ],
),
      ),
    );
  }

  Widget _buildFarmForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
  color: Colors.white.withValues(alpha: 0.06),
  borderRadius: BorderRadius.circular(25),
  border: Border.all(
    color: secondaryColor.withValues(alpha: 0.25),
    width: 1,
  ),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.28),
      blurRadius: 24,
      offset: const Offset(0, 16),
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
  controller: _contractNumberController,
  label: 'رقم العقد',
  icon: Icons.confirmation_number_rounded,
  keyboardType: TextInputType.number,
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
          // ✅ تحقق خاص لرقم العقد (10-12 رقم)
  if (controller == _contractNumberController) {
    final v = value?.trim() ?? '';
    if (!RegExp(r'^\d{10,12}$').hasMatch(v)) {
      return 'رقم العقد يجب ان يتكون من 10 إلى 12 خانة';
    }
  }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.almarai(color: Colors.white70),
        prefixIcon: Icon(icon, color: secondaryColor),
        filled: true,
fillColor: Colors.white.withValues(alpha: 0.06),

enabledBorder: OutlineInputBorder(
  borderRadius: BorderRadius.circular(15.0),
  borderSide: BorderSide(color: secondaryColor.withValues(alpha: 0.25)),
),

focusedBorder: OutlineInputBorder(
  borderRadius: const BorderRadius.all(Radius.circular(15.0)),
  borderSide: BorderSide(color: secondaryColor.withValues(alpha: 0.55), width: 2),
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
        fillColor: Colors.white.withValues(alpha: 0.06),
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
          backgroundColor: Colors.white.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: secondaryColor),
          ),
        ),
      ),
    );
  }
  // 1. دالة البحث الجديدة باستخدام MapTiler
Future<void> _fetchMapTilerSuggestions(String input) async {
  if (input.isEmpty) {
    setState(() => _suggestions = []);
    return;
  }
  setState(() => _loadingSuggest = true);

  // نستخدم الرابط الخاص بـ MapTiler للبحث في السعودية وبالعربي
  final url = 'https://api.maptiler.com/geocoding/$input.json?key=${Secrets.mapTilerKey}&country=sa&language=ar';

  try {
    final res = await http.get(Uri.parse(url));
    final data = jsonDecode(res.body);
    final List features = data['features'] ?? [];

    setState(() {
      _suggestions = features.map((e) => {
        'primary': e['text_ar'] ?? e['text'], // الاسم بالعربي
        'secondary': e['place_name_ar'] ?? e['place_name'], // العنوان الكامل
        'center': e['center'], // الإحداثيات [lng, lat]
      }).toList();
    });
  } catch (e) {
    debugPrint('MapTiler Geocoding Error: $e');
  } finally {
    setState(() => _loadingSuggest = false);
  }
}

// 2. دالة الانتقال للموقع المختار من البحث
void _moveToMapTilerLocation(List<dynamic> center) {
  
  final newLatLng = LatLng(center[1], center[0]);
  
  _mapController.move(newLatLng, 15); 

  setState(() {
    _currentCenter = newLatLng;
    _suggestions = []; 
    _searchCtrl.clear(); 
  });
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
      const SizedBox(height: 12),
  
      Container(
        height: 380, 
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
                  initialCenter: _currentCenter,
                  initialZoom: 15.0,
                  onTap: (tapPosition, point) => _onMapTap(point),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://api.maptiler.com/maps/hybrid/{z}/{x}/{y}.jpg?key=${Secrets.mapTilerKey}',
                    userAgentPackageName: 'com.saaf.app',
                  ),
                  // رسم المضلع (الحدود)
                  if (_polygonPoints.isNotEmpty)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: _polygonPoints,
                          color: const Color.fromARGB(75, 215, 172, 92),
                          borderColor: const Color.fromARGB(255, 2, 79, 25),
                          borderStrokeWidth: 3,
                        ),
                      ],
                    ),
                  // رسم النقاط
                  MarkerLayer(
                    markers: _polygonPoints.map((p) => Marker(
                      point: p,
                      child: const Icon(Icons.location_on, color: Colors.green, size: 30),
                    )).toList(),
                  ),
                ],
              ),
              
              // 2. أزرار التحكم اليدوية (الزوم والبوصلة)
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
                      onPressed: () => _mapController.rotate(0), // إعادة توجيه الشمال
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
      style: GoogleFonts.almarai(
        fontSize: 14,
        color: Colors.black87, 
      ),
    ),
    subtitle: Text(
      s['secondary'] ?? '',
      style: GoogleFonts.almarai(
        fontSize: 12,
        color: Colors.black54,
      ),
    ),
    onTap: () => _moveToMapTilerLocation(s['center']),
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
      const SizedBox(height: 15),
      // أزرار التحكم السفلية (تراجع ومسح)
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _mapActionButton(
            label: 'تراجع',
            icon: Icons.undo,
            color: secondaryColor,
            textColor: darkBackground,
            onTap: _undoLastPoint,
          ),
          _mapActionButton(
            label: 'مسح الكل',
            icon: Icons.delete_sweep,
            color: primaryColor,
            textColor: Colors.white,
            onTap: _clearPolygon,
          ),
        ],
      ),
    ],
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
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: secondaryColor.withValues(alpha: 0.5), width: 1),
          ),
          child: Icon(
            icon,
            color: darkBackground, 
            size: 26,
          ),
        ),
      ),
    ),
  );
} 
Widget _mapActionButton({required String label, required IconData icon, required Color color, required Color textColor, required VoidCallback onTap}) {
  return ElevatedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, color: textColor, size: 20),
    label: Text(label, style: GoogleFonts.almarai(color: textColor, fontWeight: FontWeight.bold)),
    style: ElevatedButton.styleFrom(
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    ),
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
            borderRadius: BorderRadius.circular(35),
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
