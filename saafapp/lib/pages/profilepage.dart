import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../widgets/profile_field.dart';
import '../../saaf_landing_screen.dart'; // <-- ADD: للوصول لصفحة اللاندنق
import 'package:google_fonts/google_fonts.dart'; // <<< ADD

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // بيانات مبدئية
  String name = ' ولاء المطيري ';
  String phone = '+9665XXXXXXX';
  String email = 'wala@example.com';
  String region = 'الرياض';

  // Controllers
  late final TextEditingController _nameCtrl = TextEditingController(
    text: name,
  );
  late final TextEditingController _phoneCtrl = TextEditingController(
    text: phone,
  );
  late final TextEditingController _emailCtrl = TextEditingController(
    text: email,
  );
  late final TextEditingController _regionCtrl = TextEditingController(
    text: region,
  );

  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _regionFocus = FocusNode();

  bool _editName = false,
      _editPhone = false,
      _editEmail = false,
      _editRegion = false;

  // الأفاتار
  final ImagePicker _picker = ImagePicker();
  String? avatarPath;

  // مشتقات الحالة
  bool get _isEditing => _editName || _editPhone || _editEmail || _editRegion;
  bool get _hasTextChanges =>
      _nameCtrl.text.trim() != name ||
      _phoneCtrl.text.trim() != phone ||
      _emailCtrl.text.trim() != email ||
      _regionCtrl.text.trim() != region;
  bool get _hasChanges => _isEditing || _hasTextChanges || avatarPath != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _regionCtrl.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    _regionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderIdleColor =
        Theme.of(context).inputDecorationTheme.enabledBorder
            is OutlineInputBorder
        ? (Theme.of(context).inputDecorationTheme.enabledBorder
                  as OutlineInputBorder)
              .borderSide
              .color
        : Color(0xFFD8B74A);

    return Scaffold(
      // --- [REPLACE] AppBar كامل ---
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          textDirection:
              TextDirection.ltr, // نخلي الأيقونة في اليمين والعنوان بالنص
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(
              width: 48,
            ), // مكان فاضي بدال زر اليسار (عشان العنوان يبقى بالنص)
            Text(
              'الملف الشخصي',
              style: GoogleFonts.almarai(
                fontWeight: FontWeight.w700, // نفس السماكة المتوقعة
              ),
            ), // <<< CHANGED

            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'العودة لصفحة البداية',
              onPressed: _goToLanding, // <<< يستدعي الدالة أدناه
            ),
          ],
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          // بطاقة زجاجية
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.fromLTRB(16, 36, 16, 28),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(255, 255, 255, 0.08),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isEditing ? cs.primary : borderIdleColor,
                    width: _isEditing ? 2 : 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color.fromRGBO(0, 0, 0, 0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickFromGallery,
                      child: CircleAvatar(
                        radius: 52,
                        backgroundImage: _avatarImageProvider(),
                        backgroundColor: cs.surface.withAlpha(
                          (255 * 0.35).round(),
                        ),
                        child: avatarPath == null
                            ? const Icon(Icons.camera_alt_rounded, size: 26)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 24),

                    ProfileField(
                      controller: _nameCtrl,
                      focusNode: _nameFocus,
                      hint: 'الاسم الكامل',
                      icon: Icons.person,
                      isEditing: _editName,
                      onToggle: () =>
                          _toggle(_nameFocus, _editName, (v) => _editName = v),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),

                    ProfileField(
                      controller: _phoneCtrl,
                      focusNode: _phoneFocus,
                      hint: 'رقم الجوال',
                      icon: Icons.phone,
                      keyboardType: TextInputType.phone,
                      isEditing: _editPhone,
                      onToggle: () => _toggle(
                        _phoneFocus,
                        _editPhone,
                        (v) => _editPhone = v,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),

                    ProfileField(
                      controller: _emailCtrl,
                      focusNode: _emailFocus,
                      hint: 'البريد الإلكتروني',
                      icon: Icons.email,
                      keyboardType: TextInputType.emailAddress,
                      isEditing: _editEmail,
                      onToggle: () => _toggle(
                        _emailFocus,
                        _editEmail,
                        (v) => _editEmail = v,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),

                    ProfileField(
                      controller: _regionCtrl,
                      focusNode: _regionFocus,
                      hint: 'المنطقة',
                      icon: Icons.location_on,
                      isEditing: _editRegion,
                      onToggle: () => _toggle(
                        _regionFocus,
                        _editRegion,
                        (v) => _editRegion = v,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 100),

          // --- [NEW] زر حفظ التعديلات بنفس ستايل "ابدأ الآن" ---
          Opacity(
            opacity: _hasChanges ? 1.0 : 0.5, // تعتيم عند التعطيل
            child: SizedBox(
              height: 54, // نفس ارتفاع زر "ابدأ الآن"
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFEBB974), // kOrange
                      Color(0xFFFFF6E0), // kLightBeige
                    ],
                  ),
                  borderRadius: BorderRadius.circular(35),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _hasChanges
                        ? _save
                        : null, // نفس منطق التفعيل/التعطيل
                    child: Center(
                      child: Text(
                        'حفظ التعديلات',
                        style: GoogleFonts.almarai(
                          color: Color(0xFF042C25),
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ), // <<< CHANGED
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggle(FocusNode node, bool current, void Function(bool) setFlag) {
    setState(() {
      final next = !current;
      setFlag(next);
      next ? node.requestFocus() : node.unfocus();
    });
  }

  ImageProvider _avatarImageProvider() {
    final path = avatarPath;
    if (path == null) return const AssetImage('assets/saaf_logo.jpg');
    if (path.startsWith('http')) return NetworkImage(path);
    return FileImage(File(path));
  }

  Future<void> _pickFromGallery() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (x == null) return;
      setState(() => avatarPath = x.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطأ أثناء اختيار الصورة: $e',
            style: GoogleFonts.almarai(),
          ),
        ),
      );
    }
  }

  void _save() {
    FocusScope.of(context).unfocus();
    setState(() {
      name = _nameCtrl.text.trim();
      phone = _phoneCtrl.text.trim();
      email = _emailCtrl.text.trim();
      region = _regionCtrl.text.trim();
      _editName = _editPhone = _editEmail = _editRegion = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ التعديلات', style: GoogleFonts.almarai())),
    );
  }

  // --- [ADD] الذهاب لصفحة اللاندنق وقفل الستاك
  void _goToLanding() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SaafLandingScreen()),
      (route) => false,
    );
  }
}
