import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // <<< ADD

class ProfileField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool isEditing;
  final VoidCallback onToggle;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const ProfileField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    required this.isEditing,
    required this.onToggle,
    this.focusNode,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      readOnly: !isEditing,
      keyboardType: keyboardType,
      textAlign: TextAlign.right,
      onChanged: onChanged,
      style: GoogleFonts.almarai(color: cs.onSurface),

      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.almarai(
          // <<< CHANGED
          color: cs.onSurface.withAlpha((255 * 0.6).round()),
        ),

        // ← بديل inputDecorationTheme (محلي داخل الودجت)
        filled: true,
        fillColor: const Color.fromRGBO(255, 255, 255, 0.08),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),

        prefixIcon: Icon(icon, color: Color(0xFFD8B74A)),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            isEditing ? Icons.check_rounded : Icons.edit_rounded,
            color: cs.primary,
          ),
          tooltip: isEditing ? 'تم' : 'تعديل',
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD8B74A), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Color(0xFFD8B74A), width: 2),
        ),
      ),
    );
  }
}
