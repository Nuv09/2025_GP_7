import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saafapp/constant.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FarmCard extends StatelessWidget {
  final int farmIndex;
  final String title;
  final String subtitle;
  final String? sizeText;
  final String? imageURL;
  final DateTime? createdAt;
  final String? lastAnalysisText;

  final String?
  analysisStatus; 
  final int? analysisCount; 
  final double? analysisQuality; 
  final String? analysisError; 

  final double? healthyPct;
  final double? monitorPct;
  final double? criticalPct;
  final Widget? healthRing;
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
    this.lastAnalysisText,
    this.analysisStatus,
    this.analysisCount,
    this.analysisQuality,
    this.analysisError,
    this.healthyPct,
    this.monitorPct,
    this.criticalPct,
    this.onEdit,
    this.onDelete,
    this.healthRing,
  });

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      debugPrint('[FarmCard][$farmIndex] imageURL = ${imageURL ?? "<null>"}');
    }

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 1,
        vertical: defaultPadding / 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            offset: Offset(0, 10),
            blurRadius: 26,
            color: Colors.black38,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            const Positioned.fill(child: _CardLuxBackground()),
            SizedBox(
              height: 160,
              child: Row(
                textDirection: TextDirection.rtl,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    flex: 3,
                    child: _ImagePane(imageURL: imageURL, farmIndex: farmIndex),
                  ),

                  Expanded(
                    flex: 8,
                    child: _InfoPane(
                      title: title,
                      subtitle: subtitle,
                      sizeText: sizeText,
                      createdAt: createdAt,
                      lastAnalysisText: lastAnalysisText,
                      analysisStatus: analysisStatus,
                      analysisCount: analysisCount,
                      analysisQuality: analysisQuality,
                      analysisError: analysisError,
                      healthyPct: healthyPct,
                      monitorPct: monitorPct,
                      criticalPct: criticalPct,
                      healthRing: healthRing,
                      onEdit: onEdit,
                      onDelete: onDelete,
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              left: 10,
              top: 6,
              child: _ActionButtons(onEdit: onEdit, onDelete: onDelete),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisBadge extends StatelessWidget {
  final String status; 
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
            const Icon(Icons.check_circle, size: 16, color: Color(0xFF1E8D5F)),
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
            const Icon(Icons.error_outline, size: 16, color: Color(0xFFB00020)),
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
        bg = darkGreenColor.withValues(alpha: 0.08);
        fg = darkGreenColor;
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 5,
              height: 5,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              'جاري التحليل…',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

class _CardLuxBackground extends StatelessWidget {
  const _CardLuxBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFFFF8E6), Color(0xFFF5E6C8), Color(0xFFEAD8B0)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.10,
              child: CustomPaint(painter: _DotPatternPainter()),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topRight,
                  radius: 1.2,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.06),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = darkGreenColor.withValues(alpha: 0.22);
    const step = 14.0;

    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        if (((x + y).toInt() % 4) == 0) {
          canvas.drawCircle(Offset(x, y), 1.2, p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ImagePane extends StatelessWidget {
  final String? imageURL;
  final int farmIndex;

  const _ImagePane({required this.imageURL, required this.farmIndex});

  @override
  Widget build(BuildContext context) {
    final hasImg = imageURL != null && imageURL!.trim().isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasImg)
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(22),
              bottomRight: Radius.circular(22),
            ),
            child: _FarmImage(
              url: imageURL!,
              width: double.infinity,
              height: 195,
              key: ValueKey('farm-$farmIndex-${imageURL!}'),
            ),
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF0B3A31), Color(0xFF062A23)],
              ),
            ),
            child: Center(
              child: Center(
                child: Image.asset(
                  'assets/images/PalmIcon.png', 
                  width: 72,
                  height: 72,
                  fit: BoxFit.contain,
                  colorBlendMode: BlendMode.srcIn,
                ),
              ),
            ),
          ),

        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [
                  Colors.black.withValues(alpha: 0.00),
                  Colors.black.withValues(alpha: 0.35),
                ],
              ),
            ),
          ),
        ),

        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: goldColor.withValues(alpha: 0.28),
                  width: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoPane extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? sizeText;
  final DateTime? createdAt;
  final String? lastAnalysisText;

  final String? analysisStatus;
  final int? analysisCount;
  final double? analysisQuality;
  final String? analysisError;

  final double? healthyPct;
  final double? monitorPct;
  final double? criticalPct;
  final Widget? healthRing;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _InfoPane({
    required this.title,
    required this.subtitle,
    required this.sizeText,
    required this.createdAt,
    required this.lastAnalysisText,
    required this.analysisStatus,
    required this.analysisCount,
    required this.analysisQuality,
    required this.analysisError,
    required this.healthyPct,
    required this.monitorPct,
    required this.criticalPct,
    required this.healthRing,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final safeTitle = title.isEmpty ? 'مزرعة بدون اسم' : title;

    return Padding(
      padding: const EdgeInsets.only(
        right: defaultPadding,
        left: 6,
        top: 12,
        bottom: 12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  safeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: darkGreenColor,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),

                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 14,
                      color: darkGreenColor,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        subtitle.isEmpty ? '—' : subtitle,

                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: darkGreenColor.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 0),

                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (sizeText != null) ...[
                      const Icon(
                        Icons.straighten,
                        size: 14,
                        color: darkGreenColor,
                      ),
                      Text(
                        sizeText!,
                        style: const TextStyle(color: darkGreenColor),
                      ),
                    ],
                  ],
                ),

                if (createdAt != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 14,
                        color: darkGreenColor,
                      ),
                      const SizedBox(width: 6),

                      SizedBox(
                        width: 70,
                        child: Text(
                          'تاريخ الإضافة:',
                          style: const TextStyle(
                            color: darkGreenColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),

                      const SizedBox(width: 6),

                      SizedBox(
                        width: 33,
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            _formatDate(createdAt!),
                            textAlign: TextAlign.left,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: darkGreenColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                if (lastAnalysisText != null &&
                    lastAnalysisText!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.analytics_outlined,
                        size: 14,
                        color: darkGreenColor,
                      ),
                      const SizedBox(width: 6),

                      const SizedBox(
                        width: 70,
                        child: Text(
                          'آخر تحليل:',
                          style: TextStyle(
                            color: darkGreenColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),

                      const SizedBox(width: 6),

                      SizedBox(
                        width: 33,
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            lastAnalysisText!,
                            textAlign: TextAlign.left,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: darkGreenColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 6),
                Builder(
                  builder: (context) {
                    final s = (analysisStatus ?? '').toLowerCase().trim();

                    if (s == 'pending' || s == 'running' || s == 'processing') {
                      return _AnalysisBadge(
                        status: s,
                        count: analysisCount,
                        quality: analysisQuality,
                        error: analysisError,
                      );
                    }

                    if (s == 'done') {
                      return const SizedBox.shrink();
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),

          if (healthRing != null) ...[
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: healthRing!,
            ),
            const SizedBox(width: 6),
          ] else
            const SizedBox(width: 8),
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

class _ActionButtons extends StatelessWidget {
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ActionButtons({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onEdit,
          tooltip: 'تعديل',
          icon: const Icon(Icons.edit, color: lightGreenColor, size: 24),
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          padding: EdgeInsets.zero,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
        ),
        const SizedBox(width: 2),
        IconButton(
          onPressed: onDelete,
          tooltip: 'حذف',
          icon: const Icon(Icons.delete_outline, color: prownColor, size: 24),
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          padding: EdgeInsets.zero,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
        ),
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

    return CachedNetworkImage(
      imageUrl: uri.toString(),
      width: width,
      height: height,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (ctx, _) => Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
      errorWidget: (ctx, _, __) => const ColoredBox(
        color: Colors.black26,
        child: Center(
          child: Icon(Icons.broken_image, color: Colors.white70, size: 36),
        ),
      ),
    );
  }
}
