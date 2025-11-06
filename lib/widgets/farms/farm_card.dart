import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saafapp/constant.dart';

class FarmCard extends StatelessWidget {
  final int farmIndex;
  final String title;
  final String subtitle;
  final String? sizeText;
  final String? imageURL;
  final DateTime? createdAt;

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const FarmCard({
    super.key,
    required this.farmIndex,
    required this.title,
    required this.subtitle,
    this.sizeText,
    this.imageURL,
    this.createdAt,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      debugPrint('[FarmCard][$farmIndex] imageURL = ${imageURL ?? "<null>"}');
    }

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: defaultPadding,
        vertical: defaultPadding / 2,
      ),
      decoration: BoxDecoration(
        color: beige,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(offset: Offset(0, 8), blurRadius: 18, color: Colors.black26),
        ],
      ),
      child: Row(
        children: [
          // صورة المزرعة
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              bottomLeft: Radius.circular(22),
            ),
            child: SizedBox(
              width: 200,
              height: 160,
              child: (imageURL != null && imageURL!.isNotEmpty)
                  ? _FarmImage(
                      url: imageURL!,
                      width: 200,
                      height: 160,
                      key: ValueKey('farm-$farmIndex-${imageURL!}'),
                    )
                  : const ColoredBox(
                      color: Colors.black26,
                      child: Center(
                        child: Icon(
                          Icons.image_not_supported,
                          color: Colors.white70,
                          size: 36,
                        ),
                      ),
                    ),
            ),
          ),

          // معلومات
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(defaultPadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // نصوص
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: darkGreenColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 16, color: darkGreenColor),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: darkGreenColor),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (sizeText != null) ...[
                              const Icon(Icons.straighten, size: 16, color: darkGreenColor),
                              const SizedBox(width: 4),
                              Text(sizeText!, style: const TextStyle(color: darkGreenColor)),
                              const SizedBox(width: 12),
                            ],
                            if (createdAt != null) ...[
                              const Icon(Icons.schedule, size: 16, color: darkGreenColor),
                              const SizedBox(width: 4),
                              Text(_formatDate(createdAt!), style: const TextStyle(color: darkGreenColor)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // أكشن
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: onEdit,
                        tooltip: 'تعديل',
                        icon: const Icon(Icons.edit, color: lightGreenColor),
                        splashRadius: 18,
                      ),
                      IconButton(
                        onPressed: onDelete,
                        tooltip: 'حذف',
                        icon: const Icon(Icons.delete_outline, color: prownColor),
                        splashRadius: 18,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }
}

class _FarmImage extends StatelessWidget {
  final String url;
  final double width;
  final double height;

  const _FarmImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
  });

  String _fixUrl(String raw) {
 // في هذه الحالة، نكتفي بالـ cleanup الأساسي لتفادي أي مشاكل ترميز (URI encoding)
var u = raw.replaceAll(RegExp(r'\s+'), '');
if (u.contains('%252F')) u = Uri.decodeFull(u);
return u;
}

  @override
  Widget build(BuildContext context) {
    final fixed = _fixUrl(url);
    final uri = Uri.parse(fixed);

    return Image.network(
      uri.toString(),
      width: width,
      height: height,
      fit: BoxFit.cover,
      loadingBuilder: (ctx, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.black12,
          alignment: Alignment.center,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: progress.expectedTotalBytes != null
                ? progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1)
                : null,
          ),
        );
      },
      errorBuilder: (ctx, error, stack) {
        if (kDebugMode) {
          debugPrint('[FarmCard][_FarmImage] load error -> $error\nTried URL:\n$fixed');
        }
        return const ColoredBox(
          color: Colors.black26,
          child: Center(
            child: Icon(Icons.broken_image, color: Colors.white70, size: 36),
          ),
        );
      },
    );
  }
}
