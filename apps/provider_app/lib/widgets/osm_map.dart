// A real map, drawn from OpenStreetMap tiles.
//
// Free, no account, no API key. The attribution in the corner is required by
// the tile-usage policy, so do not remove it.
//
// Two modes. Inline (the default) is a non-interactive thumbnail that opens
// full screen when tapped — a small map that pans and zooms inside a scrolling
// form fights the scroll. Full screen is interactive and carries the locate
// button.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';
import '../i18n/l10n.dart';

const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgent = 'in.sathiyaa.provider';

class OsmMap extends StatefulWidget {
  final double lat;
  final double lng;
  final String label;
  final double height;
  final double zoom;

  /// A second pin — the provider on their way, or the other end of a trip.
  final double? secondaryLat;
  final double? secondaryLng;
  final String? secondaryLabel;

  final bool interactive;

  /// Shown on interactive maps. Centres on the device's own position and
  /// drops a blue dot with its accuracy ring.
  final bool showLocateButton;

  /// Called when the locate button finds a position, so a form can copy the
  /// coordinates into the address it is editing.
  final void Function(double lat, double lng)? onLocated;

  const OsmMap({
    super.key,
    required this.lat,
    required this.lng,
    required this.label,
    this.height = 140,
    this.zoom = 14,
    this.secondaryLat,
    this.secondaryLng,
    this.secondaryLabel,
    this.interactive = false,
    this.showLocateButton = true,
    this.onLocated,
  });

  @override
  State<OsmMap> createState() => _OsmMapState();
}

class _OsmMapState extends State<OsmMap> {
  final MapController _controller = MapController();
  LatLng? _me;
  double? _accuracy;
  bool _locating = false;

  /// The controller throws if it is driven before the map has laid itself out,
  /// so nothing moves the camera until FlutterMap says it is ready.
  bool _ready = false;

  bool get _hasSecond => widget.secondaryLat != null && widget.secondaryLng != null;

  /// `initialCenter` is read once and never again, so a parent that moved the
  /// pin — the address form after "Use my current location" — moved the marker
  /// and left the camera where it was. The pin would slide off the edge of a
  /// map still showing the old neighbourhood. Follow it.
  @override
  void didUpdateWidget(covariant OsmMap old) {
    super.didUpdateWidget(old);
    if (!_ready) return;
    if (old.lat == widget.lat && old.lng == widget.lng) return;
    _controller.move(LatLng(widget.lat, widget.lng), _controller.camera.zoom);
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);

    final r = await LocationService.current();
    if (!mounted) return;

    if (!r.isOk) {
      setState(() => _locating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.error ?? 'Could not get your location.'),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    final here = LatLng(r.lat!, r.lng!);
    setState(() {
      _me = here;
      _accuracy = r.accuracyMetres;
      _locating = false;
    });
    _controller.move(here, 16);
    widget.onLocated?.call(r.lat!, r.lng!);

    final acc = r.accuracyMetres;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(acc == null
            ? 'Showing your location.'
            : 'Showing your location — accurate to about ${acc.round()} m.'),
      ),
    );
  }

  List<Marker> _markers(BuildContext context) => [
        Marker(
          point: LatLng(widget.lat, widget.lng),
          width: 40,
          height: 40,
          alignment: Alignment.topCenter,
          child: _Pin(color: Theme.of(context).colorScheme.primary, icon: Icons.place),
        ),
        if (_hasSecond)
          Marker(
            point: LatLng(widget.secondaryLat!, widget.secondaryLng!),
            width: 40,
            height: 40,
            alignment: Alignment.topCenter,
            child: const _Pin(color: Color(0xFF1D4ED8), icon: Icons.directions_walk),
          ),
        if (_me != null)
          Marker(
            point: _me!,
            width: 26,
            height: 26,
            child: const _MeDot(),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final map = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: LatLng(widget.lat, widget.lng),
                initialZoom: widget.zoom,
                onMapReady: () => _ready = true,
                interactionOptions: InteractionOptions(
                  flags: widget.interactive ? InteractiveFlag.all : InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: _tileUrl,
                  userAgentPackageName: _userAgent,
                  // Tiles come over the network. Offline, or on a phone that
                  // has wandered off Wi-Fi, this leaves a plain panel rather
                  // than a wall of broken-image boxes.
                  errorTileCallback: (_, __, ___) {},
                ),
                // The accuracy ring sits under the pins so it never hides one.
                if (_me != null && _accuracy != null && _accuracy! > 0)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: _me!,
                        radius: _accuracy!,
                        useRadiusInMeter: true,
                        color: const Color(0x221D4ED8),
                        borderColor: const Color(0x551D4ED8),
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
                MarkerLayer(markers: _markers(context)),
              ],
            ),
            if (widget.interactive && widget.showLocateButton)
              Positioned(
                right: 10,
                bottom: 28,
                child: _LocateButton(busy: _locating, onTap: _locate),
              ),
            const Positioned(
              right: 0,
              bottom: 0,
              child: _Attribution(),
            ),
          ],
        ),
      ),
    );

    if (widget.interactive) return map;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _FullScreenMap(
                lat: widget.lat,
                lng: widget.lng,
                label: widget.label,
                secondaryLat: widget.secondaryLat,
                secondaryLng: widget.secondaryLng,
                secondaryLabel: widget.secondaryLabel,
                onLocated: widget.onLocated,
              ),
            ),
          ),
          child: map,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 2),
          child: Text(
            t('Tap the map to open it full screen'),
            style: const TextStyle(fontSize: 11.5, color: Colors.black54),
          ),
        ),
      ],
    );
  }
}

/// The round "find me" control. Deliberately large: it is pressed one-handed,
/// often by somebody older, and often in a hurry.
class _LocateButton extends StatelessWidget {
  const _LocateButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: t('Show my location'),
      button: true,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: Colors.black38,
        child: InkWell(
          onTap: busy ? null : onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Icon(
                    Icons.my_location_rounded,
                    size: 23,
                    color: Theme.of(context).colorScheme.primary,
                  ),
          ),
        ),
      ),
    );
  }
}

/// The familiar blue dot: a white ring around a solid centre, so it reads on
/// both pale streets and dark parkland.
class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: const Color(0xFF1D4ED8),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(color: Color(0x551D4ED8), blurRadius: 8, spreadRadius: 1),
          ],
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  final Color color;
  final IconData icon;
  const _Pin({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Icon(icon, color: color, size: 34, shadows: const [
        Shadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
      ]);
}

class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      color: Colors.white70,
      child: Text(
        t('© OpenStreetMap'),
        style: const TextStyle(fontSize: 9, color: Colors.black87),
      ),
    );
  }
}

class _FullScreenMap extends StatefulWidget {
  final double lat;
  final double lng;
  final String label;
  final double? secondaryLat;
  final double? secondaryLng;
  final String? secondaryLabel;
  final void Function(double lat, double lng)? onLocated;

  const _FullScreenMap({
    required this.lat,
    required this.lng,
    required this.label,
    this.secondaryLat,
    this.secondaryLng,
    this.secondaryLabel,
    this.onLocated,
  });

  @override
  State<_FullScreenMap> createState() => _FullScreenMapState();
}

class _FullScreenMapState extends State<_FullScreenMap> {
  double? _meLat;
  double? _meLng;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.label)),
      body: Column(
        children: [
          Expanded(
            child: OsmMap(
              lat: widget.lat,
              lng: widget.lng,
              label: widget.label,
              height: double.infinity,
              zoom: 15,
              secondaryLat: widget.secondaryLat,
              secondaryLng: widget.secondaryLng,
              secondaryLabel: widget.secondaryLabel,
              interactive: true,
              onLocated: (la, ln) {
                setState(() {
                  _meLat = la;
                  _meLng = ln;
                });
                widget.onLocated?.call(la, ln);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '${widget.lat.toStringAsFixed(5)}, ${widget.lng.toStringAsFixed(5)}'
              '${widget.secondaryLabel != null ? '  ·  blue pin: ${widget.secondaryLabel}' : ''}'
              '${_meLat != null ? '  ·  you: ${_meLat!.toStringAsFixed(5)}, ${_meLng!.toStringAsFixed(5)}' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}
