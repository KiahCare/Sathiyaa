import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Getting the device's real position, and asking permission properly.
///
/// The apps used to declare ACCESS_FINE_LOCATION in the manifest and then
/// never request it, which on Android 6 and later means the permission is
/// never granted and the app simply has no location. Declaring a permission
/// is not the same as asking for one.
///
/// Every failure comes back as a sentence that says what to do about it:
/// "location unavailable" is useless when the real problem is that the
/// phone's location switch is off.
class LocationService {
  /// A place on the map, or a reason there isn't one.
  static Future<LocationResult> current({Duration timeout = const Duration(seconds: 12)}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationResult.error(
          'Location is switched off on this device. Turn it on in Settings and try again.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // This is the prompt that was never being shown.
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return LocationResult.error('Sathiyaa needs location access to do this. You can allow it and try again.');
      }
      if (permission == LocationPermission.deniedForever) {
        return LocationResult.error(
          "Location access is blocked for Sathiyaa. Allow it in the phone's app settings to use this.",
        );
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeout),
      );
      return LocationResult.ok(pos.latitude, pos.longitude, pos.accuracy);
    } catch (e) {
      debugPrint('[location] $e');
      return LocationResult.error('Could not get a location fix just now. Try again in a moment.');
    }
  }

  /// Whether permission is already granted, without prompting for it.
  static Future<bool> hasPermission() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }
}

class LocationResult {
  final double? lat;
  final double? lng;
  final double? accuracyMetres;
  final String? error;

  const LocationResult._(this.lat, this.lng, this.accuracyMetres, this.error);
  factory LocationResult.ok(double lat, double lng, double accuracy) =>
      LocationResult._(lat, lng, accuracy, null);
  factory LocationResult.error(String message) => LocationResult._(null, null, null, message);

  bool get isOk => error == null && lat != null && lng != null;
}
