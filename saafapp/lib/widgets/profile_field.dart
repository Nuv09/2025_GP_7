import 'package:flutter/material.dart';

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
      onChanged: onChanged,
      style: TextStyle(color: cs.onSurface),

      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: cs.onSurface.withOpacity(.6)),

        // ← بديل inputDecorationTheme (محلي داخل الودجت)
        filled: true,
        fillColor: Colors.white.withOpacity(.08),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),

        prefixIcon: Icon(icon, color: cs.primary),
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
          borderSide: BorderSide(color: Colors.white.withOpacity(.15), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
      ),
    );
  }
}

