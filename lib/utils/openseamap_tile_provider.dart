import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

// Fetches OpenSeaMap's seamark tiles (buoys, lights, fairways, ...) to be
// shown as a transparent overlay on top of the Google base map — OpenSeaMap
// itself doesn't offer a full base map, only this marine-marks layer.
class OpenSeaMapTileProvider implements TileProvider {
  static const _tileSize = 256;

  @override
  Future<Tile> getTile(int x, int y, int? zoom) async {
    if (zoom == null) return TileProvider.noTile;

    final uri = Uri.parse(
      'https://tiles.openseamap.org/seamark/$zoom/$x/$y.png',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return TileProvider.noTile;
      return Tile(_tileSize, _tileSize, response.bodyBytes);
    } catch (_) {
      return TileProvider.noTile;
    }
  }
}

final openSeaMapOverlay = TileOverlay(
  tileOverlayId: const TileOverlayId('openseamap'),
  tileProvider: OpenSeaMapTileProvider(),
);

// EMODnet Bathymetry's "contours" layer (generalised depth isobaths) is
// only served as WMS, not tile-friendly WMTS — unlike OpenSeaMap's depth
// WMS, it does send CORS headers (Access-Control-Allow-Origin: *), so this
// bridges it to per-tile requests the same way: compute each tile's Web
// Mercator bounding box and ask the WMS server for exactly that extent.
class EmodnetContoursTileProvider implements TileProvider {
  static const _tileSize = 256;
  static const _earthCircumference = 40075016.685578488; // 2 * pi * 6378137
  static const _originShift = _earthCircumference / 2;

  @override
  Future<Tile> getTile(int x, int y, int? zoom) async {
    if (zoom == null) return TileProvider.noTile;

    final n = 1 << zoom;
    final tileSizeMeters = _earthCircumference / n;
    final minX = -_originShift + x * tileSizeMeters;
    final maxX = -_originShift + (x + 1) * tileSizeMeters;
    final maxY = _originShift - y * tileSizeMeters;
    final minY = _originShift - (y + 1) * tileSizeMeters;

    final uri = Uri.parse('https://ows.emodnet-bathymetry.eu/wms').replace(
      queryParameters: {
        'SERVICE': 'WMS',
        'VERSION': '1.3.0',
        'REQUEST': 'GetMap',
        'LAYERS': 'emodnet:contours',
        'STYLES': '',
        'FORMAT': 'image/png',
        'TRANSPARENT': 'true',
        'CRS': 'EPSG:3857',
        'BBOX': '$minX,$minY,$maxX,$maxY',
        'WIDTH': '$_tileSize',
        'HEIGHT': '$_tileSize',
      },
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return TileProvider.noTile;
      return Tile(_tileSize, _tileSize, response.bodyBytes);
    } catch (_) {
      return TileProvider.noTile;
    }
  }
}

final depthOverlay = TileOverlay(
  tileOverlayId: const TileOverlayId('depth'),
  tileProvider: EmodnetContoursTileProvider(),
);
