import 'package:geolocator/geolocator.dart';

enum LocationFailure {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
}

class LocationResult {
  final Position? position;
  final LocationFailure? failure;

  const LocationResult._({this.position, this.failure});

  const LocationResult.success(Position position)
      : this._(position: position, failure: null);

  const LocationResult.failure(LocationFailure failure)
      : this._(position: null, failure: failure);

  bool get isSuccess => position != null;
}

class LocationService {
  static LocationService? _instance;
  LocationService._();

  static LocationService get instance {
    _instance ??= LocationService._();
    return _instance!;
  }

  Future<LocationResult> getCurrentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      return const LocationResult.failure(LocationFailure.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return const LocationResult.failure(LocationFailure.permissionDenied);
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationResult.failure(
        LocationFailure.permissionDeniedForever,
      );
    }

    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return LocationResult.success(last);
    } catch (_) {
      // Ignore and fall back to fresh fix.
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
      timeLimit: const Duration(seconds: 8),
    );
    return LocationResult.success(pos);
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
