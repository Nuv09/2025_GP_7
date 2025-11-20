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

  final String? analysisStatus;   // "pending" | "processing" | "done" | "failed" | "error"
  final int? analysisCount;       // يظهر عند الانتهاء
  final double? analysisQuality;  // إن وجد
  final String? analysisError;    // إن وجد

  // 🩺 نسب صحة النخيل
  final double? healthyPct;
  final double? monitorPct;
  final double? criticalPct;

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
    this.analysisStatus,
    this.analysisCount,
    this.analysisQuality,
    this.analysisError,
    this.healthyPct,
    this.monitorPct,
    this.criticalPct,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 195, // زودنا شوي عشان الهيلث
          child: Row(
            textDirection: TextDirection.rtl,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ==== الصورة (يمين) ====
              SizedBox(
                width: 150,
                child: (imageURL != null && imageURL!.isNotEmpty)
                    ? ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(22),
                          bottomRight: Radius.circular(22),
                        ),
                        child: _FarmImage(
                          url: imageURL!,
                          width: 150,
                          height: 195,
                          key: ValueKey('farm-$farmIndex-${imageURL!}'),
                        ),
                      )
                    : const ColoredBox(
                        color: Colors.black26,
                        child: Center(
                          child: Icon(Icons.image_not_supported,
                              color: Colors.white70, size: 30),
                        ),
                      ),
              ),

              // ==== المعلومات + الأكشن ====
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: defaultPadding,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      // النصوص
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
                                fontSize: 16,
                                color: darkGreenColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: const [
                                Icon(Icons.location_on,
                                    size: 14, color: darkGreenColor),
                                SizedBox(width: 4),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 20.0),
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: darkGreenColor),
                              ),
                            ),
                            const SizedBox(height: 6),

                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (sizeText != null) ...[
                                  const Icon(Icons.straighten,
                                      size: 14, color: darkGreenColor),
                                  Text(
                                    sizeText!,
                                    style:
                                        const TextStyle(color: darkGreenColor),
                                  ),
                                ],
                                if (createdAt != null) ...[
                                  const Icon(Icons.schedule,
                                      size: 14, color: darkGreenColor),
                                  Text(
                                    _formatDate(createdAt!),
                                    style:
                                        const TextStyle(color: darkGreenColor),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),

                            if (analysisStatus != null &&
                                analysisStatus!.isNotEmpty) ...[
                              _AnalysisBadge(
                                status: analysisStatus!,
                                count: analysisCount,
                                quality: analysisQuality,
                                error: analysisError,
                              ),
                              const SizedBox(height: 6),

                              // 🩺 ملخّص صحة النخيل تحت عدد النخيل
                              _HealthSummary(
                                status: analysisStatus!,
                                healthyPct: healthyPct,
                                monitorPct: monitorPct,
                                criticalPct: criticalPct,
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(width: 8),

                      // أزرار الأكشن
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: onEdit,
                            tooltip: 'تعديل',
                            icon: const Icon(Icons.edit,
                                color: lightGreenColor, size: 20),
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            padding: EdgeInsets.zero,
                            splashRadius: 18,
                          ),
                          const SizedBox(height: 6),
                          IconButton(
                            onPressed: onDelete,
                            tooltip: 'حذف',
                            icon: const Icon(Icons.delete_outline,
                                color: prownColor, size: 20),
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            padding: EdgeInsets.zero,
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
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }
}

class _AnalysisBadge extends StatelessWidget {
  final String status; // pending | processing | done | failed | error
  final int? count;
  final double? quality;
  final String? error;

  const _AnalysisBadge({
    required this.status,
    this.count,
    this.quality,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final Widget content;

    switch (status) {
      case 'done':
        bg = const Color(0xFFE6F4EA);
        fg = const Color(0xFF1E8D5F);
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle,
                size: 16, color: Color(0xFF1E8D5F)),
            const SizedBox(width: 6),
            Text(
              (count != null) ? 'عدد النخيل: $count' : 'التحليل مكتمل',
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
        break;

      case 'failed':
      case 'error':
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFB00020);
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 16, color: Color(0xFFB00020)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                (error == null || error!.isEmpty) ? 'فشل التحليل' : error!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
        break;

      case 'processing':
      case 'running':
      default:
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFF8D6E63);
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('جاري التحليل…',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: fg),
        child: content,
      ),
    );
  }
}

// 🩺 ملخّص صحة النخيل تحت البادج
class _HealthSummary extends StatelessWidget {
  final String status;
  final double? healthyPct;
  final double? monitorPct;
  final double? criticalPct;

  const _HealthSummary({
    required this.status,
    this.healthyPct,
    this.monitorPct,
    this.criticalPct,
  });

  double _clampPct(double? v) {
    if (v == null || v.isNaN) return 0;
    if (v < 0) return 0;
    if (v > 100) return 100;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    // نعرض الهيلث فقط إذا التحليل مكتمل وفيه بيانات
    if (status != 'done') return const SizedBox.shrink();
    if (healthyPct == null && monitorPct == null && criticalPct == null) {
      return const SizedBox.shrink();
    }

    final h = _clampPct(healthyPct);
    final m = _clampPct(monitorPct);
    final c = _clampPct(criticalPct);

    Widget chip(Color color, String label, double? value) {
      final String text =
          (value == null || value.isNaN) ? '--%' : '${value.toStringAsFixed(1)}%';

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: darkGreenColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                color: darkGreenColor,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        chip(const Color(0xFF1E8D5F), 'سليم', h),
        chip(const Color(0xFFF9A825), 'تحت المراقبة', m),
        chip(const Color(0xFFB00020), 'حرِج', c),
      ],
    );
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
                ? progress.cumulativeBytesLoaded /
                    (progress.expectedTotalBytes ?? 1)
                : null,
          ),
        );
      },
      errorBuilder: (ctx, error, stack) {
        if (kDebugMode) {
          debugPrint(
              '[FarmCard][_FarmImage] load error -> $error\nTried URL:\n$fixed');
        }
        return const ColoredBox(
          color: Colors.black26,
          child: Center(
            child: Icon(Icons.broken_image,
                color: Colors.white70, size: 36),
          ),
        );
      },
    );
  }
}
