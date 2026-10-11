import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'tracking_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _recent = <String>[];
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  static const _examples = ['9P683', 'PF720', 'PK301', 'EK600', 'PA200', 'QR604', 'BA117'];

  @override
  void dispose() {
    _controller.dispose();
    _float.dispose();
    super.dispose();
  }

  void _track([String? value]) {
    final flight = (value ?? _controller.text).trim().toUpperCase();
    if (flight.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flight number daalein, jaise 9P683, EK600')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _recent
        ..remove(flight)
        ..insert(0, flight);
      if (_recent.length > 6) _recent.removeLast();
    });
    Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, a, _) => FadeTransition(
        opacity: a,
        child: TrackingScreen(flightNumber: flight),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.8, -0.9),
            radius: 1.4,
            colors: [Color(0xFF1C2550), AppColors.bg],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            children: [
              AnimatedBuilder(
                animation: _float,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, -6 * _float.value),
                  child: child,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: AppColors.accentGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.amber.withValues(alpha: 0.4),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Transform.rotate(
                      angle: 0.785,
                      child: const Icon(Icons.flight, color: Colors.white, size: 34),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Track any flight\nin real time',
                style: TextStyle(
                  fontSize: 34,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Flight number daalein aur live map par jahaz dekhein: '
                'route, altitude, speed aur ETA.',
                style: TextStyle(color: AppColors.textDim, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 32),
              _searchField(),
              const SizedBox(height: 16),
              _trackButton(),
              if (_recent.isNotEmpty) ...[
                const SizedBox(height: 32),
                _sectionTitle('Recent'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _recent.map((f) => _chip(f, Icons.history)).toList(),
                ),
              ],
              const SizedBox(height: 32),
              _sectionTitle('Try these'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _examples.map((f) => _chip(f, Icons.flight_takeoff)).toList(),
              ),
              const SizedBox(height: 40),
              const GlassCard(
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.cyan, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Live position sirf tab milti hai jab flight hawa mein ho '
                        '(ya ground par transponder on ho).',
                        style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField() => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.stroke),
        ),
        child: TextField(
          key: const Key('flight_input'),
          controller: _controller,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _track(),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 2),
          decoration: const InputDecoration(
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search, color: AppColors.textDim),
            hintText: 'e.g. EK600',
            hintStyle: TextStyle(
              color: AppColors.textDim,
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
            ),
            contentPadding: EdgeInsets.symmetric(vertical: 20),
          ),
        ),
      );

  Widget _trackButton() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('track_button'),
            borderRadius: BorderRadius.circular(18),
            onTap: _track,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.radar, color: Color(0xFF1A1206)),
                  SizedBox(width: 10),
                  Text(
                    'Track Flight',
                    style: TextStyle(
                      color: Color(0xFF1A1206),
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _sectionTitle(String t) => Text(
        t.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textDim,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      );

  Widget _chip(String flight, IconData icon) => Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.stroke),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            _controller.text = flight;
            _track(flight);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: AppColors.amber),
                const SizedBox(width: 8),
                Text(flight, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
}
