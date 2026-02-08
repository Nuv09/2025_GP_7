// import 'package:flutter/foundation.dart' show kIsWeb;
// import 'package:web/web.dart' as web;

// // لجلب المفاتيح من index.html للويب
// String _webSecret(String name) {
//   return web.document
//           .querySelector('meta[name="$name"]')
//           ?.getAttribute('content') ??
//       '';
// }

// // المفتاح الموحد للويب والموبايل
// class Secrets {
//   // API KEY
//   static String get placesKey {
//     if (kIsWeb) {
//       return _webSecret("PLACES_KEY");
//     }
//     return _mobilePlacesKey; // سرّي للجوال
//   }

//   // هنا نحط مفاتيح الجوال فقط
//   static const String _mobilePlacesKey = "AIzaSyCEU204FgpLDPx_XvogBcnrMVQ6wCQdu30";
// }

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;

String _webSecret(String name) {
  if (!kIsWeb) return '';

  try {
    final el = html.document.querySelector('meta[name="$name"]');
    return el?.getAttribute('content') ?? '';
  } catch (_) {
    return '';
  }
}

class Secrets {
  static String get placesKey {
    if (kIsWeb) {
      return _webSecret("PLACES_KEY");
    }
    // مفتاح الجوال
    return _mobilePlacesKey;
  }

  // مفتاح الجوال فقط
  static const String _mobilePlacesKey =
      "AIzaSyCEU204FgpLDPx_XvogBcnrMVQ6wCQdu30";

  static const String weatherApiKey = "c20bf6e172ae4184888190817260702";
  static const String mapTilerKey = 'zVvvWEVIvVWnFKBfB4Co';
}
