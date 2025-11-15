import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web/web.dart' as web;

// لجلب المفاتيح من index.html للويب
String _webSecret(String name) {
  return web.document
          .querySelector('meta[name="$name"]')
          ?.getAttribute('content') ??
      '';
}

// المفتاح الموحد للويب والموبايل
class Secrets {
  // API KEY
  static String get placesKey {
    if (kIsWeb) {
      return _webSecret("PLACES_KEY");
    }
    return _mobilePlacesKey; // سرّي للجوال
  }

  // هنا نحط مفاتيح الجوال فقط
  static const String _mobilePlacesKey = "AIzaSyCEU204FgpLDPx_XvogBcnrMVQ6wCQdu30";
}
