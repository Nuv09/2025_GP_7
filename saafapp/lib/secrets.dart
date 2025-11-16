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
}
