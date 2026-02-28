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
  // ✅ رابط الباك-إند
  static String get apiBaseUrl {
    if (kIsWeb) {
      // للويب نخليه يقرأ من meta في index.html (اختياري)
      final v = _webSecret("API_BASE_URL");
      if (v.isNotEmpty) return v;
    }
    // للموبايل/الإيموليتر
    return _mobileApiBaseUrl;
  }

  // ✅ غيريه حسب جهازك:
  // Android Emulator:
  static const String _mobileApiBaseUrl =
      "https://saaf-analyzer-us-120954850101.us-central1.run.app";
  // لو جهاز حقيقي (مثال):
  // static const String _mobileApiBaseUrl = "http://192.168.1.10:5000";

  // --- باقي مفاتيحك ---
  static String get placesKey {
    if (kIsWeb) return _webSecret("PLACES_KEY");
    return _mobilePlacesKey;
  }

  static const String _mobilePlacesKey =
      "AIzaSyCEU204FgpLDPx_XvogBcnrMVQ6wCQdu30";

  static const String weatherApiKey = "c20bf6e172ae4184888190817260702";
  static const String mapTilerKey = 'zVvvWEVIvVWnFKBfB4Co';
}
