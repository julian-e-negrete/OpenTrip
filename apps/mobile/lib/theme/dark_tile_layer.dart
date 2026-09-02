import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'app_theme.dart';

/// OpenStreetMap's standard tile server, darkened toward Nocturne's
/// palette with a multiply blend — no API key, no signup, same "free at
/// this scale" posture as the rest of this app's map usage.
///
/// This app used to point street-mode tiles at CARTO's Dark Matter
/// basemap (`basemaps.cartocdn.com`) instead, on the assumption that
/// service was free and keyless like OSM's. It no longer is — CARTO now
/// requires an API key for every basemap style, including that one
/// (confirmed live: it serves a small "API KEY REQUIRED" watermark tile,
/// not a map, without one). Reverting to bare OSM tiles would bring back
/// the original problem this was meant to fix — a bright, colorful
/// basemap clashing with Nocturne's dark palette — so this multiplies
/// every tile by a dark, near-opaque tint instead: free, no key, and
/// dark enough to sit naturally next to the rest of the app. It won't
/// look as considered as a real dark-styled basemap; it's the honest
/// tradeoff for staying key-free.
class DarkTileLayer extends StatelessWidget {
  const DarkTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(Noct.bg.withValues(alpha: 0.82), BlendMode.multiply),
      child: TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'co.opentrip.opentrip_mobile',
      ),
    );
  }
}
