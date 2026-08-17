import '../data/models/trip.dart';
import '../data/models/trip_point.dart';
import '../data/repositories/gamification_repository.dart';
import '../data/repositories/trip_repository.dart';
import 'territory.dart';
import 'trophies.dart';

/// Runs right after a trip finishes (see trip/recording_screen.dart's
/// _stop): records any newly-explored map cells, then re-evaluates the
/// trophy catalog against updated all-time stats and awards anything
/// newly earned. Both territory_cells and trophies are just two more
/// locally-stored, sync-tracked tables — sync/sync_service.dart pushes
/// them the same way it already pushes vehicles/trips.
class GamificationService {
  GamificationService._();

  static Future<List<TrophyDefinition>> processFinishedTrip({
    required String userId,
    required Trip trip,
    required List<TripPoint> points,
  }) async {
    final repo = GamificationRepository.instance;

    final newCells = cellsForTrip(points);
    if (newCells.isNotEmpty) {
      await repo.addTerritoryCells(userId, newCells);
    }

    final stats = await _currentStats(userId, trip);
    final alreadyEarned = await repo.earnedTrophyKeys(userId);

    final newlyEarned = <TrophyDefinition>[];
    for (final trophy in trophyCatalog) {
      if (alreadyEarned.contains(trophy.key)) continue;
      if (trophy.isEarned(stats)) {
        await repo.awardTrophy(userId, trophy.key);
        newlyEarned.add(trophy);
      }
    }
    return newlyEarned;
  }

  static Future<RiderStats> _currentStats(String userId, Trip justFinished) async {
    final trips = await TripRepository.instance.listForUser(userId);
    final totalDistance = trips.fold<double>(0, (sum, t) => sum + t.distanceMeters);
    final longest = trips.fold<double>(0, (max, t) => t.distanceMeters > max ? t.distanceMeters : max);
    final territoryCount = await GamificationRepository.instance.territoryCellCount(userId);

    return RiderStats(
      totalDistanceMeters: totalDistance,
      longestTripMeters: longest,
      tripCount: trips.length,
      territoryCellCount: territoryCount,
      lastTripStartedAt: justFinished.startedAt,
    );
  }
}
