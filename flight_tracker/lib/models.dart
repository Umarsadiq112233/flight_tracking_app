import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Airport info (from adsbdb route lookup).
class Airport {
  final String name;
  final String iata;
  final String icao;
  final String city;
  final String country;
  final double lat;
  final double lon;

  const Airport({
    required this.name,
    required this.iata,
    required this.icao,
    required this.city,
    required this.country,
    required this.lat,
    required this.lon,
  });

  LatLng get latLng => LatLng(lat, lon);
  String get code => iata.isNotEmpty ? iata : icao;

  factory Airport.fromJson(Map<String, dynamic> j) => Airport(
        name: (j['name'] ?? '').toString(),
        iata: (j['iata_code'] ?? '').toString(),
        icao: (j['icao_code'] ?? '').toString(),
        city: (j['municipality'] ?? '').toString(),
        country: (j['country_name'] ?? '').toString(),
        lat: (j['latitude'] as num).toDouble(),
        lon: (j['longitude'] as num).toDouble(),
      );
}

/// Flight route + airline for a flight number / callsign.
class FlightRoute {
  final String callsignIcao; // e.g. UAE600 (what aircraft transmit)
  final String callsignIata; // e.g. EK600 (what's on your ticket)
  final String airlineName;
  final String airlineIata;
  final String airlineIcao;
  final Airport? origin;
  final Airport? destination;

  const FlightRoute({
    required this.callsignIcao,
    required this.callsignIata,
    required this.airlineName,
    required this.airlineIata,
    required this.airlineIcao,
    this.origin,
    this.destination,
  });

  factory FlightRoute.fromJson(Map<String, dynamic> j) {
    final airline = (j['airline'] as Map?)?.cast<String, dynamic>() ?? {};
    return FlightRoute(
      callsignIcao: (j['callsign_icao'] ?? j['callsign'] ?? '').toString(),
      callsignIata: (j['callsign_iata'] ?? j['callsign'] ?? '').toString(),
      airlineName: (airline['name'] ?? '').toString(),
      airlineIata: (airline['iata'] ?? '').toString(),
      airlineIcao: (airline['icao'] ?? '').toString(),
      origin: j['origin'] is Map
          ? Airport.fromJson((j['origin'] as Map).cast<String, dynamic>())
          : null,
      destination: j['destination'] is Map
          ? Airport.fromJson((j['destination'] as Map).cast<String, dynamic>())
          : null,
    );
  }
}

/// Real-time aircraft position from ADS-B.
class LivePosition {
  final String hex; // ICAO 24-bit address
  final String callsign;
  final double lat;
  final double lon;
  final int? altitudeFt;
  final bool onGround;
  final double? groundSpeedKt;
  final double? track; // degrees
  final int? verticalRateFpm;
  final String? squawk;
  final String? registration;
  final String? aircraftType;
  final String? originIata;
  final String? destIata;
  final double seenSeconds; // how old the position is
  final String source;

  const LivePosition({
    required this.hex,
    required this.callsign,
    required this.lat,
    required this.lon,
    this.altitudeFt,
    required this.onGround,
    this.groundSpeedKt,
    this.track,
    this.verticalRateFpm,
    this.squawk,
    this.registration,
    this.aircraftType,
    this.originIata,
    this.destIata,
    this.seenSeconds = 0,
    required this.source,
  });

  LatLng get latLng => LatLng(lat, lon);
}

class AircraftInfo {
  final String type;
  final String manufacturer;
  final String registration;
  final String owner;
  final String? photoUrl;

  const AircraftInfo({
    required this.type,
    required this.manufacturer,
    required this.registration,
    required this.owner,
    this.photoUrl,
  });

  factory AircraftInfo.fromJson(Map<String, dynamic> j) => AircraftInfo(
        type: (j['type'] ?? '').toString(),
        manufacturer: (j['manufacturer'] ?? '').toString(),
        registration: (j['registration'] ?? '').toString(),
        owner: (j['registered_owner'] ?? '').toString(),
        photoUrl: (j['url_photo'] ?? j['url_photo_thumbnail'])?.toString(),
      );
}

/// One side (departure / arrival) of a scheduled flight.
class ScheduleLeg {
  final Airport? airport;
  final DateTime? scheduled; // local time at that airport (as wall-clock)
  final DateTime? revised; // estimated / updated
  final DateTime? actual; // runway / actual
  final String? terminal;
  final String? gate;
  final String? baggage;
  final String? utcOffset; // e.g. +05:00

  const ScheduleLeg({
    this.airport,
    this.scheduled,
    this.revised,
    this.actual,
    this.terminal,
    this.gate,
    this.baggage,
    this.utcOffset,
  });

  /// AeroDataBox local times look like "2026-10-11 23:45+05:00".
  static DateTime? _localWallClock(dynamic t) {
    if (t is! Map) return null;
    final s = (t['local'] ?? '').toString();
    final m = RegExp(r'^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2})').firstMatch(s);
    return m == null ? null : DateTime.tryParse('${m[1]}T${m[2]}:00');
  }

  static String? _offset(dynamic t) {
    if (t is! Map) return null;
    final m = RegExp(r'([+-]\d{2}:\d{2})$').firstMatch((t['local'] ?? '').toString());
    return m?[1];
  }

  factory ScheduleLeg.fromAeroDataBox(Map<String, dynamic> j) {
    Airport? airport;
    final a = j['airport'];
    if (a is Map) {
      final loc = a['location'];
      airport = Airport(
        name: (a['name'] ?? '').toString(),
        iata: (a['iata'] ?? '').toString(),
        icao: (a['icao'] ?? '').toString(),
        city: (a['municipalityName'] ?? a['shortName'] ?? '').toString(),
        country: (a['countryCode'] ?? '').toString(),
        lat: loc is Map ? (loc['lat'] as num?)?.toDouble() ?? 0 : 0,
        lon: loc is Map ? (loc['lon'] as num?)?.toDouble() ?? 0 : 0,
      );
    }
    return ScheduleLeg(
      airport: airport,
      scheduled: _localWallClock(j['scheduledTime']),
      revised: _localWallClock(j['revisedTime'] ?? j['predictedTime']),
      actual: _localWallClock(j['runwayTime']),
      terminal: j['terminal']?.toString(),
      gate: j['gate']?.toString(),
      baggage: j['baggageBelt']?.toString(),
      utcOffset: _offset(j['scheduledTime']),
    );
  }

  factory ScheduleLeg.fromFR24(Map<String, dynamic> airportJson, Map<String, dynamic> timeJson, bool isDeparture) {
    Airport? airport;
    final code = (airportJson['code'] as Map?)?.cast<String, dynamic>() ?? {};
    final pos = (airportJson['position'] as Map?)?.cast<String, dynamic>() ?? {};
    final country = (pos['country'] as Map?)?.cast<String, dynamic>() ?? {};
    final region = (pos['region'] as Map?)?.cast<String, dynamic>() ?? {};
    final iata = (code['iata'] ?? '').toString();
    final icao = (code['icao'] ?? '').toString();

    if (iata.isNotEmpty || icao.isNotEmpty) {
      airport = Airport(
        iata: iata,
        icao: icao,
        name: (airportJson['name'] ?? '').toString(),
        city: (region['city'] ?? '').toString(),
        country: (country['name'] ?? '').toString(),
        lat: (pos['latitude'] as num?)?.toDouble() ?? 0.0,
        lon: (pos['longitude'] as num?)?.toDouble() ?? 0.0,
      );
    }

    final key = isDeparture ? 'departure' : 'arrival';
    final schedTs = (timeJson['scheduled'] as Map?)?[key] as num?;
    final estTs = (timeJson['estimated'] as Map?)?[key] as num?;
    final realTs = (timeJson['real'] as Map?)?[key] as num?;

    return ScheduleLeg(
      airport: airport,
      scheduled: schedTs != null ? DateTime.fromMillisecondsSinceEpoch((schedTs * 1000).toInt()) : null,
      revised: estTs != null ? DateTime.fromMillisecondsSinceEpoch((estTs * 1000).toInt()) : null,
      actual: realTs != null ? DateTime.fromMillisecondsSinceEpoch((realTs * 1000).toInt()) : null,
    );
  }
}

/// Schedule & official status (like the left panel in Flightradar24).
class FlightSchedule {
  final String number;
  final String status; // Expected, Departed, EnRoute, Landed, Delayed, Canceled…
  final String? airlineName;
  final String? callSign;
  final String? aircraftModel;
  final String? registration;
  final String? modeS; // hex → used to find the plane live
  final ScheduleLeg departure;
  final ScheduleLeg arrival;
  final DateTime? departureUtc;

  const FlightSchedule({
    required this.number,
    required this.status,
    this.airlineName,
    this.callSign,
    this.aircraftModel,
    this.registration,
    this.modeS,
    required this.departure,
    required this.arrival,
    this.departureUtc,
  });

  factory FlightSchedule.fromFR24(Map<String, dynamic> j) {
    final ident = (j['identification'] as Map?)?.cast<String, dynamic>() ?? {};
    final statusMap = (j['status'] as Map?)?.cast<String, dynamic>() ?? {};
    final airportMap = (j['airport'] as Map?)?.cast<String, dynamic>() ?? {};
    final timeMap = (j['time'] as Map?)?.cast<String, dynamic>() ?? {};
    final aircraftMap = (j['aircraft'] as Map?)?.cast<String, dynamic>() ?? {};
    final airlineMap = (j['airline'] as Map?)?.cast<String, dynamic>() ?? {};

    final number = (ident['number'] as Map?)?['default']?.toString() ?? '';
    final callsign = ident['callsign']?.toString();
    final statusText = statusMap['text']?.toString() ?? 'Scheduled';

    final origMap = (airportMap['origin'] as Map?)?.cast<String, dynamic>() ?? {};
    final destMap = (airportMap['destination'] as Map?)?.cast<String, dynamic>() ?? {};

    final depLeg = ScheduleLeg.fromFR24(origMap, timeMap, true);
    final arrLeg = ScheduleLeg.fromFR24(destMap, timeMap, false);

    final modelMap = (aircraftMap['model'] as Map?)?.cast<String, dynamic>() ?? {};
    final modelText = modelMap['text']?.toString() ?? modelMap['code']?.toString();
    final reg = aircraftMap['registration']?.toString();
    final hex = aircraftMap['hex']?.toString();

    return FlightSchedule(
      number: number,
      status: statusText,
      airlineName: airlineMap['name']?.toString(),
      callSign: callsign,
      aircraftModel: modelText,
      registration: reg,
      modeS: hex,
      departure: depLeg,
      arrival: arrLeg,
      departureUtc: depLeg.scheduled,
    );
  }

  factory FlightSchedule.fromAeroDataBox(Map<String, dynamic> j) {
    final ac = (j['aircraft'] as Map?)?.cast<String, dynamic>() ?? {};
    final al = (j['airline'] as Map?)?.cast<String, dynamic>() ?? {};
    final dep = (j['departure'] as Map?)?.cast<String, dynamic>() ?? {};
    final arr = (j['arrival'] as Map?)?.cast<String, dynamic>() ?? {};
    final depUtc = (dep['scheduledTime'] as Map?)?['utc']?.toString();
    return FlightSchedule(
      number: (j['number'] ?? '').toString().replaceAll(' ', ''),
      status: (j['status'] ?? 'Unknown').toString(),
      airlineName: al['name']?.toString(),
      callSign: j['callSign']?.toString(),
      aircraftModel: ac['model']?.toString(),
      registration: ac['reg']?.toString(),
      modeS: ac['modeS']?.toString().toLowerCase(),
      departure: ScheduleLeg.fromAeroDataBox(dep),
      arrival: ScheduleLeg.fromAeroDataBox(arr),
      departureUtc: depUtc == null ? null : DateTime.tryParse(depUtc.replaceFirst(' ', 'T')),
    );
  }

  /// Human friendly status text, e.g. "Estimated departure 23:45".
  String get label => switch (status.toLowerCase()) {
        'expected' || 'unknown' => 'Scheduled',
        'checkin' => 'Check-in open',
        'boarding' => 'Boarding',
        'gateclosed' => 'Gate closed',
        'departed' => 'Departed',
        'enroute' => 'En route',
        'approaching' => 'Approaching',
        'arrived' || 'landed' => 'Landed',
        'delayed' => 'Delayed',
        'canceled' || 'cancelled' || 'canceleduncertain' => 'Cancelled',
        'diverted' => 'Diverted',
        _ => status,
      };
}

class TrackPoint {
  final DateTime time;
  final LatLng pos;
  final int? altitudeFt;

  const TrackPoint(this.time, this.pos, this.altitudeFt);
}

enum FlightPhase {
  noSignal,
  atGate,
  climbing,
  cruising,
  descending,
  enRoute,
  landed,
  signalLost,
}

extension FlightPhaseX on FlightPhase {
  String get label => switch (this) {
        FlightPhase.noSignal => 'Not airborne',
        FlightPhase.atGate => 'On ground',
        FlightPhase.climbing => 'Climbing',
        FlightPhase.cruising => 'Cruising',
        FlightPhase.descending => 'Descending',
        FlightPhase.enRoute => 'En route',
        FlightPhase.landed => 'Landed',
        FlightPhase.signalLost => 'Signal lost',
      };
}

/// Derived status computed from route + live position.
class FlightStatus {
  final FlightPhase phase;
  final double? progress; // 0..1
  final double? totalKm;
  final double? remainingKm;
  final DateTime? eta;

  const FlightStatus({
    required this.phase,
    this.progress,
    this.totalKm,
    this.remainingKm,
    this.eta,
  });

  static const _dist = Distance();

  factory FlightStatus.compute(FlightRoute? route, LivePosition? live) {
    final o = route?.origin, d = route?.destination;
    double? total, remaining, progress;
    if (o != null && d != null) {
      total = _dist.as(LengthUnit.Kilometer, o.latLng, d.latLng);
      if (live != null) {
        remaining = _dist.as(LengthUnit.Kilometer, live.latLng, d.latLng);
        progress = total > 0 ? (1 - remaining / total).clamp(0.0, 1.0) : null;
      }
    }

    if (live == null) {
      return FlightStatus(phase: FlightPhase.noSignal, totalKm: total);
    }

    FlightPhase phase;
    if (live.seenSeconds > 90) {
      phase = FlightPhase.signalLost;
    } else if (live.onGround || (live.altitudeFt ?? 99999) < 100) {
      phase = (remaining != null && remaining < 40)
          ? FlightPhase.landed
          : FlightPhase.atGate;
    } else {
      final vr = live.verticalRateFpm ?? 0;
      if (vr > 400) {
        phase = FlightPhase.climbing;
      } else if (vr < -400) {
        phase = FlightPhase.descending;
      } else if ((live.altitudeFt ?? 0) > 18000) {
        phase = FlightPhase.cruising;
      } else {
        phase = FlightPhase.enRoute;
      }
    }

    DateTime? eta;
    final gs = live.groundSpeedKt;
    if (remaining != null &&
        gs != null &&
        gs > 80 &&
        phase != FlightPhase.landed &&
        phase != FlightPhase.atGate) {
      final hours = remaining / (gs * 1.852);
      eta = DateTime.now().add(Duration(minutes: (hours * 60).round()));
    }

    return FlightStatus(
      phase: phase,
      progress: phase == FlightPhase.landed ? 1.0 : progress,
      totalKm: total,
      remainingKm: remaining,
      eta: eta,
    );
  }
}

/// Computes points along the great-circle arc between two coordinates.
List<LatLng> greatCircle(LatLng a, LatLng b, {int segments = 48}) {
  double rad(double d) => d * math.pi / 180;
  double deg(double r) => r * 180 / math.pi;
  final lat1 = rad(a.latitude), lon1 = rad(a.longitude);
  final lat2 = rad(b.latitude), lon2 = rad(b.longitude);
  final d = 2 *
      math.asin(math.sqrt(math.pow(math.sin((lat1 - lat2) / 2), 2) +
          math.cos(lat1) *
              math.cos(lat2) *
              math.pow(math.sin((lon1 - lon2) / 2), 2)));
  if (d <= 0.00001) return [a, b];
  final pts = <LatLng>[];
  for (var i = 0; i <= segments; i++) {
    final f = i / segments;
    final A = math.sin((1 - f) * d) / math.sin(d);
    final B = math.sin(f * d) / math.sin(d);
    final x = A * math.cos(lat1) * math.cos(lon1) +
        B * math.cos(lat2) * math.cos(lon2);
    final y = A * math.cos(lat1) * math.sin(lon1) +
        B * math.cos(lat2) * math.sin(lon2);
    final z = A * math.sin(lat1) + B * math.sin(lat2);
    pts.add(LatLng(
      deg(math.atan2(z, math.sqrt(x * x + y * y))),
      deg(math.atan2(y, x)),
    ));
  }
  return pts;
}

/// Generates a realistic airway flight corridor that passes precisely
/// through the active plane position, or directly between origin & destination.
List<LatLng> buildAirwayPath(LatLng origin, LatLng destination, {LatLng? currentPosition}) {
  if (currentPosition == null) {
    return greatCircle(origin, destination, segments: 64);
  }
  // Connect Origin -> Current Position -> Destination smoothly
  final leg1 = greatCircle(origin, currentPosition, segments: 36);
  final leg2 = greatCircle(currentPosition, destination, segments: 36);
  return [...leg1, ...leg2.skip(1)];
}
