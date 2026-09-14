import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A dependency-free PNG encoder, so the mock media service can serve real
/// images instead of 404s.
///
/// The app renders photography through `cached_network_image`, which decodes
/// actual bitmaps - an SVG or a placeholder service would not exercise the same
/// code path (memory cache sizing, decode cost, fade-in). Generating a genuine
/// PNG per asset keeps the demo honest about what the image pipeline does.
Uint8List gradientPng({
  required int width,
  required int height,
  required int seed,
}) {
  final int w = width.clamp(16, 1400).toInt();
  final int h = height.clamp(16, 1400).toInt();

  // Two deterministic anchor colours derived from the seed, so a given asset id
  // always renders the same image across restarts.
  final int hueA = seed % 360;
  final int hueB = (hueA + 40 + (seed % 60)) % 360;
  final List<int> a = _hslToRgb(hueA, 0.34, 0.42);
  final List<int> b = _hslToRgb(hueB, 0.30, 0.72);

  final Uint8List raw = Uint8List(h * (w * 3 + 1));
  int p = 0;
  for (int y = 0; y < h; y++) {
    raw[p++] = 0; // filter type: none
    final double fy = y / (h - 1);
    for (int x = 0; x < w; x++) {
      final double fx = x / (w - 1);
      // Diagonal blend plus a soft vignette; enough structure that scaling
      // artefacts are visible if the rendition maths is wrong.
      final double t = (fx * 0.55 + fy * 0.45);
      final double vignette =
          1 - 0.18 * (((fx - 0.5) * (fx - 0.5) + (fy - 0.5) * (fy - 0.5)) * 2);
      raw[p++] = ((a[0] + (b[0] - a[0]) * t) * vignette)
          .round()
          .clamp(0, 255)
          .toInt();
      raw[p++] = ((a[1] + (b[1] - a[1]) * t) * vignette)
          .round()
          .clamp(0, 255)
          .toInt();
      raw[p++] = ((a[2] + (b[2] - a[2]) * t) * vignette)
          .round()
          .clamp(0, 255)
          .toInt();
    }
  }

  final BytesBuilder out = BytesBuilder();
  out.add(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
  _chunk(out, 'IHDR', <int>[
    ..._be32(w),
    ..._be32(h),
    8, // bit depth
    2, // colour type: truecolour
    0, // compression
    0, // filter
    0, // interlace
  ]);
  _chunk(out, 'IDAT', zlib.encode(raw));
  _chunk(out, 'IEND', const <int>[]);
  return out.takeBytes();
}

void _chunk(BytesBuilder out, String type, List<int> data) {
  out.add(_be32(data.length));
  final List<int> payload = <int>[...ascii.encode(type), ...data];
  out.add(payload);
  out.add(_be32(_crc32(payload)));
}

List<int> _be32(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int>? _crcTable;

int _crc32(List<int> bytes) {
  final List<int> table = _crcTable ??= List<int>.generate(256, (int n) {
    int c = n;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    return c;
  });
  int crc = 0xFFFFFFFF;
  for (final int byte in bytes) {
    crc = table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

List<int> _hslToRgb(int hDeg, double s, double l) {
  final double h = hDeg / 360;
  double hue(double p, double q, double t) {
    double tt = t;
    if (tt < 0) tt += 1;
    if (tt > 1) tt -= 1;
    if (tt < 1 / 6) return p + (q - p) * 6 * tt;
    if (tt < 1 / 2) return q;
    if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
    return p;
  }

  if (s == 0) {
    final int v = (l * 255).round();
    return <int>[v, v, v];
  }
  final double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final double p = 2 * l - q;
  return <int>[
    (hue(p, q, h + 1 / 3) * 255).round(),
    (hue(p, q, h) * 255).round(),
    (hue(p, q, h - 1 / 3) * 255).round(),
  ];
}

/// Deterministic seed from any string id.
int seedFrom(String value) {
  int hash = 7;
  for (int i = 0; i < value.length; i++) {
    hash = (hash * 31 + value.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return hash;
}
