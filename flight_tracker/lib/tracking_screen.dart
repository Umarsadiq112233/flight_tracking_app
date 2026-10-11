import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'airport_database.dart';
import 'app_theme.dart';
import 'flight_service.dart';
import 'models.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key, required this.flightNumber});

  final String flightNumber;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with SingleTickerProviderStateMixin {
  static const _refreshEvery = Duration(seconds: 10);

  final _service = FlightService();
  final _map = MapController();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  FlightRoute? _route;
  LivePosition? _live;
  FlightSchedule? _schedule;
  AircraftInfo? _aircraft;
  List<LatLng> _trail = [];
  FlightStatus _status = const FlightStatus(phase: FlightPhase.noSignal);
  DateTime? _updatedAt;
  bool _loading = true;
  bool _refreshing = false;
  bool _mapReady = false;
  bool _follow = false;
  bool _didFit = false;
  bool _isSatellite = true; // Default to real HDR Satellite Imagery map
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final route = await _service.lookupRoute(widget.flightNumber);
      if (!mounted) return;
      setState(() {
        _route = route;
        if (route != null && route.origin != null && route.destination != null) {
          _schedule = _service.computeSchedule(route);
        }
      });
      await _refresh(initial: true);
      _timer = Timer.periodic(_refreshEvery, (_) => _refresh());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh({bool initial = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (mounted) setState(() {});
    try {
      final callsign = _route?.callsignIcao.isNotEmpty == true
          ? _route!.callsignIcao
          : FlightService.normalize(widget.flightNumber);
      final live = await _service.fetchLive(callsign, route: _route) ??
          await _service.fetchLive(FlightService.normalize(widget.flightNumber), route: _route);
      if (!mounted) return;

      final hexChanged = live != null && live.hex != _live?.hex;

      // If route lacks origin/destination, resolve them from live position
      if (live != null && (_route?.origin == null || _route?.destination == null)) {
        final orig = live.originIata != null ? AirportDatabase.getByIata(live.originIata!) : null;
        final dest = live.destIata != null ? AirportDatabase.getByIata(live.destIata!) : null;
        if (orig != null || dest != null) {
          _route = FlightRoute(
            callsignIcao: _route?.callsignIcao ?? live.callsign,
            callsignIata: _route?.callsignIata ?? widget.flightNumber,
            airlineName: _route?.airlineName ?? 'Airline',
            airlineIata: _route?.airlineIata ?? '',
            airlineIcao: _route?.airlineIcao ?? '',
            origin: _route?.origin ?? orig,
            destination: _route?.destination ?? dest,
          );
        }
      }

      setState(() {
        _live = live;
        _status = FlightStatus.compute(_route, live);
        _updatedAt = DateTime.now();
        if (_route != null && _route!.origin != null && _route!.destination != null) {
          _schedule = _service.computeSchedule(_route!, live: live);
        }
        if (live != null &&
            (_trail.isEmpty || const Distance().as(LengthUnit.Meter, _trail.last, live.latLng) > 50)) {
          _trail = [..._trail, live.latLng];
        }
      });

      if (hexChanged) {
        // Load flown path + aircraft details once per aircraft.
        final results = await Future.wait([
          _service.fetchTrack(live.hex),
          _service.fetchAircraft(live.hex),
        ]);
        if (!mounted) return;
        final track = results[0] as List<TrackPoint>;
        setState(() {
          _aircraft = results[1] as AircraftInfo?;
          if (track.length > 1) _trail = [...track.map((t) => t.pos), live.latLng];
        });
      }

      if (!_didFit) _fitAll();
      if (_follow && live != null && _mapReady) {
        _map.move(live.latLng, _map.camera.zoom);
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() {});
    }
  }

  void _fitAll() {
    if (!_mapReady) return;
    final pts = <LatLng>[
      if (_route?.origin != null) _route!.origin!.latLng,
      if (_route?.destination != null) _route!.destination!.latLng,
      if (_live != null) _live!.latLng,
    ];
    if (pts.isEmpty) return;
    _didFit = true;
    if (pts.length == 1) {
      _map.move(pts.first, 7);
      return;
    }
    _map.fitCamera(CameraFit.coordinates(
      coordinates: pts,
      padding: const EdgeInsets.fromLTRB(60, 150, 60, 340),
      maxZoom: 9,
    ));
  }

  void _focusPlane() {
    if (_live == null) return;
    setState(() => _follow = true);
    _map.move(_live!.latLng, 8);
  }

  // ───────────────────────────── UI ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          _buildTopBar(),
          _buildMapButtons(),
          _buildSheet(),
          if (_loading) _buildLoader(),
        ],
      ),
    );
  }

  Widget _buildLoader() => Container(
        color: AppColors.bg.withValues(alpha: 0.85),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 46,
              height: 46,
              child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.amber),
            ),
            const SizedBox(height: 20),
            Text('Searching ${widget.flightNumber}…',
                style: const TextStyle(color: AppColors.textDim, fontSize: 15)),
          ],
        ),
      );

  Widget _buildMap() {
    final o = _route?.origin, d = _route?.destination;
    final livePos = _live?.latLng;

    // 1. Full airway corridor between Origin and Destination (routed via plane if live)
    final airway = (o != null && d != null)
        ? buildAirwayPath(o.latLng, d.latLng, currentPosition: livePos)
        : <LatLng>[];

    // 2. Flown path from Origin up to active plane position
    final flownSegment = <LatLng>[
      if (o != null) o.latLng,
      ..._trail,
      ?livePos,
    ];

    // 3. Remaining planned path from Plane to Destination
    final remainingSegment = (livePos != null && d != null)
        ? greatCircle(livePos, d.latLng, segments: 40)
        : airway;

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: const LatLng(25, 55),
        initialZoom: 3,
        minZoom: 2,
        maxZoom: 16,
        backgroundColor: AppColors.bg,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () {
          _mapReady = true;
          if (!_loading) _fitAll();
        },
        onPositionChanged: (_, hasGesture) {
          if (hasGesture && _follow) setState(() => _follow = false);
        },
      ),
      children: [
        if (_isSatellite) ...[
          // Ultra-crisp World Imagery (Real High-Res Satellite HDR Earth)
          TileLayer(
            key: const ValueKey('sat_base'),
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.mc.flight_tracker',
            maxZoom: 18,
          ),
          // Clean geopolitical borders and city labels over satellite
          TileLayer(
            key: const ValueKey('sat_ref'),
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.mc.flight_tracker',
            maxZoom: 18,
          ),
        ] else ...[
          // Sleek Night Radar Canvas
          TileLayer(
            key: const ValueKey('dark_base'),
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.mc.flight_tracker',
            maxZoom: 16,
          ),
          TileLayer(
            key: const ValueKey('dark_ref'),
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.mc.flight_tracker',
            maxZoom: 16,
          ),
        ],
        PolylineLayer(polylines: [
          // Remaining route corridor to destination (Cyan dashed airway)
          if (remainingSegment.isNotEmpty)
            Polyline(
              points: remainingSegment,
              color: const Color(0xFF00E5FF).withValues(alpha: 0.95),
              strokeWidth: 3.2,
              pattern: StrokePattern.dashed(segments: const [9, 8]),
            ),
          // Already flown path from origin to plane (Flightradar24 solid amber/violet trail)
          if (flownSegment.length > 1)
            Polyline(
              points: flownSegment,
              strokeWidth: 4.5,
              gradientColors: const [
                Color(0xFF8B5CF6), // Violet at departure
                Color(0xFF06B6D4), // Cyan midway
                Color(0xFFFFB800), // Amber at plane
              ],
              borderStrokeWidth: 7,
              borderColor: const Color(0xFFFFB800).withValues(alpha: 0.25),
            ),
        ]),
        MarkerLayer(markers: [
          if (o != null) _airportMarker(o, isOrigin: true),
          if (d != null) _airportMarker(d, isOrigin: false),
        ]),
        if (_live != null)
          TweenAnimationBuilder<LatLng>(
            tween: _LatLngTween(begin: _live!.latLng, end: _live!.latLng),
            duration: const Duration(milliseconds: 1500),
            curve: Curves.easeInOut,
            builder: (_, pos, _) => MarkerLayer(markers: [
              Marker(
                point: pos,
                width: 70,
                height: 70,
                child: _PlaneMarker(track: _live!.track ?? 0, pulse: _pulse),
              ),
            ]),
          ),
        RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [
            TextSourceAttribution(_isSatellite
                ? 'Esri World Imagery (Satellite HDR) • Maxar • Earthstar'
                : 'Esri Dark Canvas • OpenStreetMap contributors'),
            const TextSourceAttribution('adsb.lol • OpenSky Network'),
          ],
        ),
      ],
    );
  }

  Marker _airportMarker(Airport a, {required bool isOrigin}) => Marker(
        point: a.latLng,
        width: 80,
        height: 50,
        alignment: Alignment.topCenter,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surfaceHi,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isOrigin ? AppColors.cyan : AppColors.amber),
              ),
              child: Text(a.code,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(height: 4),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isOrigin ? AppColors.cyan : AppColors.amber,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
            ),
          ],
        ),
      );

  Widget _buildTopBar() {
    final isLive = _live != null && _status.phase != FlightPhase.signalLost;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            _roundButton(Icons.arrow_back_ios_new, () => Navigator.pop(context),
                key: const Key('back_button')),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LiveDot(active: isLive, pulse: _pulse),
                  const SizedBox(width: 10),
                  Text(
                    _route?.callsignIata.isNotEmpty == true
                        ? _route!.callsignIata
                        : widget.flightNumber,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 1),
                  ),
                  const SizedBox(width: 8),
                  Text(isLive ? 'LIVE' : 'OFFLINE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: isLive ? AppColors.green : AppColors.textDim,
                      )),
                ],
              ),
            ),
            const Spacer(),
            _roundButton(
              Icons.refresh,
              _refreshing ? null : () => _refresh(),
              key: const Key('refresh_button'),
              child: _refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapButtons() => SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 72, right: 16),
            child: Column(
              children: [
                _roundButton(
                  _isSatellite ? Icons.satellite_alt : Icons.map_outlined,
                  () => setState(() => _isSatellite = !_isSatellite),
                  key: const Key('map_layer_button'),
                  highlighted: _isSatellite,
                ),
                const SizedBox(height: 10),
                _roundButton(Icons.my_location, _live == null ? null : _focusPlane,
                    key: const Key('follow_button'),
                    highlighted: _follow),
                const SizedBox(height: 10),
                _roundButton(Icons.zoom_out_map, () {
                  setState(() => _follow = false);
                  _fitAll();
                }, key: const Key('fit_button')),
              ],
            ),
          ),
        ),
      );

  Widget _roundButton(IconData icon, VoidCallback? onTap,
          {Key? key, Widget? child, bool highlighted = false}) =>
      Material(
        key: key,
        color: highlighted ? AppColors.amber : AppColors.surface.withValues(alpha: 0.92),
        shape: const CircleBorder(side: BorderSide(color: AppColors.stroke)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Center(
              child: child ??
                  Icon(icon,
                      size: 20,
                      color: highlighted
                          ? AppColors.bg
                          : (onTap == null ? AppColors.textDim : AppColors.text)),
            ),
          ),
        ),
      );

  Widget _buildSheet() => DraggableScrollableSheet(
        initialChildSize: 0.35,
        minChildSize: 0.15,
        maxChildSize: 0.88,
        snap: true,
        snapSizes: const [0.15, 0.35, 0.88],
        builder: (context, scroll) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: AppColors.stroke),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, -6)),
            ],
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.stroke,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (!_loading && _route == null && _live == null)
                _notFound()
              else ...[
                _header(),
                const SizedBox(height: 18),
                _routeCard(),
                const SizedBox(height: 14),
                if (_live != null) _statsGrid() else _noSignalCard(),
                if (_aircraft != null || _live?.aircraftType != null) ...[
                  const SizedBox(height: 14),
                  _aircraftCard(),
                ],
                const SizedBox(height: 18),
                _footer(),
              ],
            ],
          ),
        ),
      );

  Widget _notFound() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            const Icon(Icons.travel_explore, size: 48, color: AppColors.textDim),
            const SizedBox(height: 14),
            Text('${widget.flightNumber} nahi mili',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              _error ??
                  'Flight number check karein (jaise EK600, PK301). '
                      'Ho sakta hai flight abhi operate na ho rahi ho.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textDim, height: 1.4),
            ),
          ],
        ),
      );

  Widget _header() {
    final color = _phaseColor(_status.phase);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _route?.airlineName.isNotEmpty == true ? _route!.airlineName : 'Unknown airline',
                style: const TextStyle(color: AppColors.textDim, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _route?.callsignIata.isNotEmpty == true
                        ? _route!.callsignIata
                        : widget.flightNumber,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                  if (_route?.callsignIcao.isNotEmpty == true) ...[
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(_route!.callsignIcao,
                          style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_phaseIcon(_status.phase), size: 16, color: color),
              const SizedBox(width: 6),
              Text(_status.phase.label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _routeCard() {
    final o = _route?.origin, d = _route?.destination;
    final p = _status.progress;
    final sched = _schedule;
    final depLeg = sched?.departure;
    final arrLeg = sched?.arrival;
    final distKm = _status.totalKm ??
        (o != null && d != null
            ? const Distance().as(LengthUnit.Kilometer, o.latLng, d.latLng)
            : null);
    final durationMinutes = distKm != null ? (distKm / 780 * 60 + 25).round() : null;

    return GlassCard(
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _airportBlock(
                  o,
                  CrossAxisAlignment.start,
                  AppColors.cyan,
                  isOrigin: true,
                  scheduledTime: depLeg?.scheduled,
                  estimatedTime: depLeg?.actual ?? depLeg?.revised,
                ),
              ),
              if (durationMinutes != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHi,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.stroke),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 12, color: AppColors.textDim),
                        const SizedBox(width: 4),
                        Text(
                          _duration(Duration(minutes: durationMinutes)),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: _airportBlock(
                  d,
                  CrossAxisAlignment.end,
                  AppColors.amber,
                  isOrigin: false,
                  scheduledTime: arrLeg?.scheduled,
                  estimatedTime: _status.eta ?? arrLeg?.revised ?? arrLeg?.actual,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            final progressVal = p ?? (_live != null ? 0.05 : 0.0);
            final x = (progressVal * (w - 28)).clamp(0.0, w - 28);
            return SizedBox(
              height: 28,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.stroke,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    width: x + 14,
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.amber]),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    left: x,
                    child: Transform.rotate(
                      angle: 1.5708,
                      child: Icon(
                        Icons.flight,
                        color: _live != null ? AppColors.amber : AppColors.textDim,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _status.totalKm != null && _status.remainingKm != null
                    ? '${_fmtNum(_status.totalKm! - _status.remainingKm!)} km flown'
                    : (distKm != null ? '${_fmtNum(distKm)} km total' : ''),
                style: const TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
              if (_live == null)
                const Text('Awaiting Takeoff',
                    style: TextStyle(
                        color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.w700))
              else
                Text(
                  _status.remainingKm != null
                      ? '${_fmtNum(_status.remainingKm!)} km left'
                      : (p != null ? '${(p * 100).round()}%' : ''),
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _airportBlock(
    Airport? a,
    CrossAxisAlignment align,
    Color color, {
    required bool isOrigin,
    DateTime? scheduledTime,
    DateTime? estimatedTime,
  }) =>
      Column(
        crossAxisAlignment: align,
        children: [
          Text(a?.code ?? '---',
              style: TextStyle(
                  fontSize: 32, fontWeight: FontWeight.w900, color: color, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(
            a?.city.isNotEmpty == true ? a!.city : (a?.name ?? 'Unknown'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align == CrossAxisAlignment.end ? TextAlign.end : TextAlign.start,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          Text(
            a?.country ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bg.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.stroke.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: align,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SCHEDULED',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDim.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  scheduledTime != null ? _hhmm(scheduledTime) : '—',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isOrigin ? (_live != null ? 'ACTUAL' : 'ESTIMATED') : 'ESTIMATED',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: (isOrigin ? AppColors.cyan : AppColors.amber).withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  estimatedTime != null ? _hhmm(estimatedTime) : '—',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: isOrigin ? AppColors.cyan : AppColors.amber,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _statsGrid() {
    final l = _live!;
    final eta = _status.eta;
    final stats = <(IconData, String, String, String?)>[
      (
        Icons.height,
        'Altitude',
        l.onGround ? 'Ground' : (l.altitudeFt != null ? '${_fmtNum(l.altitudeFt!.toDouble())} ft' : '—'),
        l.altitudeFt != null && !l.onGround ? '${_fmtNum(l.altitudeFt! * 0.3048)} m' : null,
      ),
      (
        Icons.speed,
        'Ground speed',
        l.groundSpeedKt != null ? '${l.groundSpeedKt!.round()} kt' : '—',
        l.groundSpeedKt != null ? '${(l.groundSpeedKt! * 1.852).round()} km/h' : null,
      ),
      (
        Icons.explore_outlined,
        'Heading',
        l.track != null ? '${l.track!.round()}°' : '—',
        l.track != null ? _compass(l.track!) : null,
      ),
      (
        Icons.trending_up,
        'Vertical rate',
        l.verticalRateFpm != null ? '${l.verticalRateFpm! > 0 ? '+' : ''}${l.verticalRateFpm} fpm' : '—',
        null,
      ),
      (
        Icons.schedule,
        'ETA (local)',
        eta != null ? _hhmm(eta) : '—',
        eta != null ? 'in ${_duration(eta.difference(DateTime.now()))}' : null,
      ),
      (Icons.wifi_tethering, 'Squawk', l.squawk ?? '—', l.squawk == '7700' ? 'EMERGENCY' : null),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: stats
          .map((s) => GlassCard(
                padding: const EdgeInsets.all(14),
                radius: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(children: [
                      Icon(s.$1, size: 14, color: AppColors.textDim),
                      const SizedBox(width: 6),
                      Text(s.$2, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
                    ]),
                    const SizedBox(height: 6),
                    Text(s.$3,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    if (s.$4 != null)
                      Text(s.$4!,
                          maxLines: 1,
                          style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _noSignalCard() {
    final o = _route?.origin;
    final d = _route?.destination;
    final distKm = _status.totalKm ??
        (o != null && d != null
            ? const Distance().as(LengthUnit.Kilometer, o.latLng, d.latLng)
            : null);
    final durationMinutes = distKm != null ? (distKm / 780 * 60 + 25).round() : null;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.schedule, color: AppColors.amber, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Scheduled • Awaiting Pushback',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      o != null && d != null
                          ? '${o.city} (${o.code}) ➔ ${d.city} (${d.code})'
                          : 'Planned route active on map',
                      style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Aircraft transponder is offline while parked at the gate or awaiting takeoff. '
            'The planned airway route is drawn on the map above. '
            'Live radar tracking engages automatically as soon as the flight powers up and takes off.',
            style: const TextStyle(color: AppColors.textDim, height: 1.45, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceHi,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.stroke),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Active Radar Monitor • Auto-refreshing every ${_refreshEvery.inSeconds}s',
                    style: const TextStyle(
                        color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                if (durationMinutes != null)
                  Text(
                    'Est. ${_duration(Duration(minutes: durationMinutes))}',
                    style: const TextStyle(
                        color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aircraftCard() {
    final a = _aircraft;
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (a?.photoUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  a!.photoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.surface),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AIRCRAFT',
                    style: TextStyle(
                        color: AppColors.textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4)),
                const SizedBox(height: 6),
                Text(
                  a != null ? '${a.manufacturer} ${a.type}'.trim() : (_live?.aircraftType ?? ''),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                _kv('Registration', a?.registration ?? _live?.registration ?? '—'),
                if (a?.owner.isNotEmpty == true) _kv('Operator', a!.owner),
                _kv('Mode-S hex', _live?.hex.toUpperCase() ?? '—'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(k, style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
            ),
            Expanded(
              child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ],
        ),
      );

  Widget _footer() => Text(
        [
          if (_updatedAt != null) 'Updated ${_hhmm(_updatedAt!, seconds: true)}',
          if (_live != null) 'Source: ${_live!.source}',
          'Auto-refresh ${_refreshEvery.inSeconds}s',
        ].join('  •  '),
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textDim, fontSize: 11),
      );

  // ─────────────────────────── helpers ───────────────────────────

  Color _phaseColor(FlightPhase p) => switch (p) {
        FlightPhase.climbing || FlightPhase.cruising || FlightPhase.enRoute => AppColors.green,
        FlightPhase.descending => AppColors.cyan,
        FlightPhase.landed => AppColors.violet,
        FlightPhase.atGate => AppColors.amber,
        FlightPhase.signalLost => AppColors.red,
        FlightPhase.noSignal => AppColors.textDim,
      };

  IconData _phaseIcon(FlightPhase p) => switch (p) {
        FlightPhase.climbing => Icons.flight_takeoff,
        FlightPhase.descending => Icons.flight_land,
        FlightPhase.landed => Icons.check_circle,
        FlightPhase.atGate => Icons.local_parking,
        FlightPhase.signalLost => Icons.signal_wifi_off,
        FlightPhase.noSignal => Icons.schedule,
        _ => Icons.flight,
      };

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _hhmm(DateTime t, {bool seconds = false}) =>
      '${_two(t.hour)}:${_two(t.minute)}${seconds ? ':${_two(t.second)}' : ''}';

  static String _duration(Duration d) {
    if (d.isNegative) return '0m';
    final h = d.inHours, m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  static String _fmtNum(double v) {
    final s = v.round().toString();
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }

  static String _compass(double deg) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return dirs[((deg % 360) / 45).round() % 8];
  }
}

class _LatLngTween extends Tween<LatLng> {
  _LatLngTween({required LatLng begin, required LatLng end}) : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) => LatLng(
        begin!.latitude + (end!.latitude - begin!.latitude) * t,
        begin!.longitude + (end!.longitude - begin!.longitude) * t,
      );
}

class _PlaneMarker extends StatelessWidget {
  const _PlaneMarker({required this.track, required this.pulse});

  final double track;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, child) => Stack(
        alignment: Alignment.center,
        children: [
          // ADS-B radar beacon ping circle
          Container(
            width: 24 + 36 * pulse.value,
            height: 24 + 36 * pulse.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFFB800).withValues(alpha: 0.6 * (1 - pulse.value)),
                width: 1.5,
              ),
              color: const Color(0xFFFFB800).withValues(alpha: 0.18 * (1 - pulse.value)),
            ),
          ),
          child!,
        ],
      ),
      child: Transform.rotate(
        angle: track * 3.141592653589793 / 180,
        child: const Icon(
          Icons.flight,
          size: 34,
          color: Color(0xFFFFB800), // Flightradar24 iconic yellow
          shadows: [
            Shadow(color: Color(0xDD000000), blurRadius: 4, offset: Offset(0, 1)),
            Shadow(color: Color(0xAA000000), blurRadius: 8),
          ],
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.active, required this.pulse});

  final bool active;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.green : AppColors.textDim;
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (active)
              Container(
                width: 6 + 8 * pulse.value,
                height: 6 + 8 * pulse.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.5 * (1 - pulse.value)),
                ),
              ),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
