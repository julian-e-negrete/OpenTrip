import 'package:flutter/material.dart';

import '../theme/ph_icons.dart';

/// Snapshot of a rider's all-time stats, used to evaluate which trophies
/// they've earned. Deliberately not speed-based — see
/// /packages/kawasaki_rideology_ble and README.md's "why this exists":
/// this mirrors TripRank's four ranked categories (distance, longest
/// drive, territory, trophies), none of which reward going fast.
class RiderStats {
  final double totalDistanceMeters;
  final double longestTripMeters;
  final int tripCount;
  final int territoryCellCount;
  final DateTime? lastTripStartedAt;

  const RiderStats({
    required this.totalDistanceMeters,
    required this.longestTripMeters,
    required this.tripCount,
    required this.territoryCellCount,
    this.lastTripStartedAt,
  });
}

class TrophyDefinition {
  final String key;
  final String name;
  final String description;
  final IconData icon;
  final bool Function(RiderStats stats) isEarned;

  const TrophyDefinition({
    required this.key,
    required this.name,
    required this.description,
    required this.icon,
    required this.isEarned,
  });
}

/// A starter set — small and easy to extend (add an entry here; nothing
/// else needs to change, gamification/gamification_service.dart
/// re-evaluates this whole list against current stats after every trip).
final List<TrophyDefinition> trophyCatalog = [
  TrophyDefinition(
    key: 'first_trip',
    name: 'First Trip',
    description: 'Record your first trip.',
    icon: Ph.flagCheckered,
    isEarned: (s) => s.tripCount >= 1,
  ),
  TrophyDefinition(
    key: 'five_trips',
    name: 'Regular',
    description: 'Record 5 trips.',
    icon: Ph.repeat,
    isEarned: (s) => s.tripCount >= 5,
  ),
  TrophyDefinition(
    key: 'fifty_trips',
    name: 'Creature of Habit',
    description: 'Record 50 trips.',
    icon: Ph.arrowsClockwise,
    isEarned: (s) => s.tripCount >= 50,
  ),
  TrophyDefinition(
    key: 'century',
    name: 'Century',
    description: 'A single trip of 100 km or more.',
    icon: Ph.gauge,
    isEarned: (s) => s.longestTripMeters >= 100000,
  ),
  TrophyDefinition(
    key: 'distance_1000km',
    name: 'Road Warrior',
    description: '1,000 km all-time.',
    icon: Ph.path,
    isEarned: (s) => s.totalDistanceMeters >= 1000000,
  ),
  TrophyDefinition(
    key: 'distance_10000km',
    name: 'Odometer Breaker',
    description: '10,000 km all-time.',
    icon: Ph.globeHemisphereWest,
    isEarned: (s) => s.totalDistanceMeters >= 10000000,
  ),
  TrophyDefinition(
    key: 'explorer_100',
    name: 'Explorer',
    description: '100 unique map areas explored.',
    icon: Ph.compass,
    isEarned: (s) => s.territoryCellCount >= 100,
  ),
  TrophyDefinition(
    key: 'explorer_1000',
    name: 'Cartographer',
    description: '1,000 unique map areas explored.',
    icon: Ph.mapTrifold,
    isEarned: (s) => s.territoryCellCount >= 1000,
  ),
  TrophyDefinition(
    key: 'night_rider',
    name: 'Night Rider',
    description: 'Start a trip between 10 PM and 5 AM.',
    icon: Ph.moonStars,
    isEarned: (s) {
      final hour = s.lastTripStartedAt?.hour;
      if (hour == null) return false;
      return hour >= 22 || hour < 5;
    },
  ),
];
