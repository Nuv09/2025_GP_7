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
    errorBuilder: (_, __, ___) =>
        const Icon(Icons.broken_image, color: Colors.white70),
  );
}
