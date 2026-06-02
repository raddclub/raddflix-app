import '../constants.dart';
import 'api_client.dart';
import '../../models/catalog_item.dart';

class CatalogApi {
  static final _client = ApiClient.instance;

  /// Returns the current catalog version number + total item count.
  /// Use this to check if a sync is needed before downloading everything.
  static Future<CatalogVersion> getVersion() async {
    final response = await _client.get(ApiPaths.catalogVersion);
    final data = response.data as Map<String, dynamic>;
    return CatalogVersion(
      version: data['version'] as int? ?? 0,
      count: data['count'] as int? ?? 0,
    );
  }

  /// Full catalog sync. Returns all published titles + their episodes.
  static Future<List<CatalogItem>> syncFull() async {
    final response = await _client.get(ApiPaths.catalogSync);
    final data = response.data as Map<String, dynamic>;
    final titles   = data['titles']   as List<dynamic>? ?? [];
    final episodes = data['episodes'] as List<dynamic>? ?? [];
    return _buildItemsWithEpisodes(titles, episodes);
  }

  /// Delta sync — only items changed since [sinceTimestamp].
  /// Pass the last sync time; server returns only new/updated items.
  static Future<List<CatalogItem>> syncDelta(int sinceTimestamp) async {
    final response = await _client.get(
      ApiPaths.catalogSync,
      params: {'since': sinceTimestamp.toString()},
    );
    final data = response.data as Map<String, dynamic>;
    final titles   = data['titles']   as List<dynamic>? ?? [];
    final episodes = data['episodes'] as List<dynamic>? ?? [];
    return _buildItemsWithEpisodes(titles, episodes);
  }

  /// Attaches episodes to their parent CatalogItems.
  static List<CatalogItem> _buildItemsWithEpisodes(
    List<dynamic> titles, List<dynamic> episodes) {
    final epsByTitle = <int, List<Map<String, dynamic>>>{};
    for (final ep in episodes) {
      final m = ep as Map<String, dynamic>;
      final tid = m['title_id'] as int? ?? 0;
      epsByTitle.putIfAbsent(tid, () => []).add(m);
    }
    return titles.map((e) {
      final item = CatalogItem.fromJson(e as Map<String, dynamic>);
      final eps = epsByTitle[item.id] ?? [];
      return eps.isEmpty ? item : item.copyWithEpisodes(eps);
    }).toList();
  }

  /// Fetch the JazzDrive share_url for a specific file from Oracle catalog.
  /// Called when the local SQLite DB doesn't have the share_url (e.g. after a
  /// fresh install or before BUG-009 fix was synced).
  /// Returns null if Oracle is unreachable or file not found.
  static Future<String?> getShareUrl(String fileId) async {
    try {
      final response = await _client.get(ApiPaths.fileShareUrl(fileId));
      final data = response.data as Map<String, dynamic>;
      return data['share_url'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Fetch TMDB-seeded recommendations — titles similar to the current library
  /// that are NOT yet available on RaddFlix.  Requires active JWT session.
  /// Returns raw JSON maps: {tmdb_id, title, media_type, year, rating, poster_url}.
  static Future<List<Map<String, dynamic>>> fetchRecommendations({int limit = 20}) async {
    try {
      final response = await _client.get(
        ApiPaths.recommend,
        params: {'limit': limit.toString()},
      );
      final data = response.data as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      // Server sends 'poster' but UI reads 'poster_url' — normalise here (BUG-A33)
      return results.map((e) {
        final m = Map<String, dynamic>.from(e as Map<String, dynamic>);
        if (!m.containsKey('poster_url') && m.containsKey('poster')) {
          m['poster_url'] = m['poster'];
        }
        return m;
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

class CatalogVersion {
  final int version;
  final int count;
  const CatalogVersion({required this.version, required this.count});
}
