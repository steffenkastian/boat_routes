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
