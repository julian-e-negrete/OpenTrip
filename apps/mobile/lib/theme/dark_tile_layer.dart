import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Esri's Dark Gray Canvas — a basemap actually drawn dark (fills, roads,
/// labels all styled for a dark UI), not a bright map darkened after the
/// fact. Free and keyless, same ArcGIS REST family this app already uses
/// for the satellite layer (see trip_detail_screen.dart).
///
/// This app used to point street-mode tiles at CARTO's Dark Matter
/// basemap (`basemaps.cartocdn.com`) instead, on the assumption that
/// service was free and keyless like OSM's. It no longer is — CARTO now
/// requires an API key for every basemap style, including that one. The
/// interim fix (tinting plain OSM tiles with a dark multiply filter) read
/// as a washed-out, transparent skin over an otherwise bright map rather
/// than an actual dark map, so this replaces it with a basemap that's
/// dark by design instead of dark by filter.
///
/// Esri splits this style into two tile sets — a solid-fill base and a
/// transparent roads/labels overlay — composited here as two stacked
/// TileLayers.
class DarkTileLayer extends StatelessWidget {
  const DarkTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'co.opentrip.opentrip_mobile',
        ),
        TileLayer(
          urlTemplate:
              'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'co.opentrip.opentrip_mobile',
        ),
      ],
    );
  }
}
