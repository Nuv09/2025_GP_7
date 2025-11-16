// // lib/widgets/saaf_image_web.dart
// import 'package:flutter/material.dart';
// import 'package:web/web.dart' as web;
// import 'dart:ui_web' as ui_web;

// /// عرض صورة شبكة على الويب باستخدام عنصر <img> لتفادي CORS/CanvasKit
// Widget saafNetworkImage(
//   String url, {
//   double? width,
//   double? height,
//   BoxFit fit = BoxFit.cover,
//   Key? key,
// }) {
//   final viewType = 'saaf-img-${DateTime.now().microsecondsSinceEpoch}';

//   ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
//     final img = web.HTMLImageElement();
//     img.src = url;
//     img.style.objectFit = (fit == BoxFit.cover) ? 'cover' : 'contain';
//     img.style.width = '100%';
//     img.style.height = '100%';
//     img.style.pointerEvents = 'none';
//     img.onError.listen((_) {
//       // ignore: avoid_print
//       print('IMG LOAD ERROR for $url');
//     });
//     return img;
//   });

//   return SizedBox(
//     key: key,
//     width: width,
//     height: height,
//     child: HtmlElementView(viewType: viewType),
//   );
// }

import 'package:flutter/material.dart';

Widget saafNetworkImage(
  String url, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  Key? key,
}) {
  return Image.network(
    url,
    key: key,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (_, __, ___) {
      return const Icon(Icons.broken_image, color: Colors.white70);
    },
  );
}

