// Turning a map pin into an address somebody can read.
//
// The apps could already find where you are, and both put the pin in the
// right place -- and then left you to type your own street name, area, city
// and pincode into four boxes underneath a map that already knew all four.
// On a phone, for an older user, that is the difference between finishing the
// form and abandoning it.
//
// Nominatim, not Google
// ---------------------
// OpenStreetMap's own geocoder. No account, no key, no card on file, and the
// map tiles in these apps already come from OSM, so the address and the map
// agree with each other. Google's Geocoding API would be $5 per 1000 lookups
// and needs a billing account attached to a key that would then be sitting in
// an APK.
//
// Its terms ask for two things, and both are honoured here: an identifying
// User-Agent (so a misbehaving client can be contacted rather than banned),
// and at most one request a second. This is only ever called when somebody
// taps "use my location", so the rate limit is not a real constraint -- but
// [_lastCall] enforces it anyway, because a double tap should not put the
// project's address on a block list.
//
// Everything about this is best-effort. A failed lookup leaves the fields
// exactly as they were and says nothing: the pin is already correct, and the
// person can still type. Nothing in the app depends on the result.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A postal address worked out from a pair of coordinates.
class PlaceAddress {
  /// House number, road, neighbourhood -- what goes on the first line.
  final String line1;
  final String city;
  final String state;
  final String pincode;

  const PlaceAddress({
    this.line1 = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
  });

  bool get isEmpty => line1.isEmpty && city.isEmpty && pincode.isEmpty;

  /// "12 MG Road, Indiranagar, Bengaluru 560038"
  String get oneLine => [
        if (line1.isNotEmpty) line1,
        if (city.isNotEmpty) city,
        if (pincode.isNotEmpty) pincode,
      ].join(', ');
}

class Geocode {
  Geocode._();

  static const _endpoint = 'https://nominatim.openstreetmap.org/reverse';

  /// Identifies this client to Nominatim, as its terms require.
  static const _userAgent = 'Sathiyaa/1.0 (in.sathiyaa.customer)';

  static DateTime? _lastCall;

  /// The address at [lat],[lng], or null if it cannot be worked out.
  ///
  /// Never throws. A timeout, no connection, a rate limit and a coordinate in
  /// the middle of the sea all come back the same way -- as null -- because
  /// the caller does the same thing in every one of those cases.
  static Future<PlaceAddress?> reverse(
    double lat,
    double lng, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // One request a second, as the usage policy asks.
    final since = _lastCall == null ? null : DateTime.now().difference(_lastCall!);
    if (since != null && since < const Duration(seconds: 1)) {
      await Future<void>.delayed(const Duration(seconds: 1) - since);
    }
    _lastCall = DateTime.now();

    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'lat': '$lat',
      'lon': '$lng',
      'format': 'jsonv2',
      // 18 is roughly building level. Lower numbers give a suburb, which is
      // not an address.
      'zoom': '18',
      'addressdetails': '1',
      // Devanagari and Gujarati street names are correct but are not what the
      // rest of these forms are in, and an address half in one script is
      // harder to read than one entirely in either.
      'accept-language': 'en',
    });

    try {
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent, 'Accept': 'application/json'})
          .timeout(timeout);
      if (res.statusCode != 200) {
        debugPrint('[geocode] ${res.statusCode} from Nominatim');
        return null;
      }
      final body = jsonDecode(res.body);
      if (body is! Map || body['address'] is! Map) return null;
      return _fromNominatim(Map<String, dynamic>.from(body['address'] as Map));
    } catch (e) {
      debugPrint('[geocode] $e');
      return null;
    }
  }

  /// Nominatim's address object is a bag of optional keys whose names depend
  /// on what kind of place it is, so each line is assembled from the first of
  /// several that is present rather than from one fixed field.
  static PlaceAddress _fromNominatim(Map<String, dynamic> a) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = a[k];
        if (v != null && '$v'.trim().isNotEmpty) return '$v'.trim();
      }
      return '';
    }

    final house = pick(['house_number']);
    final road = pick(['road', 'pedestrian', 'footway', 'residential']);
    final area = pick(['neighbourhood', 'suburb', 'quarter', 'village', 'hamlet']);
    final building = pick(['building', 'amenity', 'shop', 'office']);

    // "12 MG Road, Indiranagar". The building name is only used when there is
    // no road, which is common for apartment complexes off a named lane.
    final street = [if (house.isNotEmpty) house, if (road.isNotEmpty) road].join(' ');
    final line1 = [
      if (street.isNotEmpty) street else if (building.isNotEmpty) building,
      if (area.isNotEmpty && area != street) area,
    ].join(', ');

    return PlaceAddress(
      line1: line1,
      // town and municipality matter here: much of India's urban population
      // lives somewhere Nominatim does not label `city`.
      city: pick(['city', 'town', 'municipality', 'state_district', 'county']),
      state: pick(['state']),
      pincode: pick(['postcode']),
    );
  }
}
