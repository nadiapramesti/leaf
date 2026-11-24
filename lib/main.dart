import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'fonts.dart';
import 'home.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  await Fonts.loadAll();
  runApp(const LeafApp());
}

class LeafApp extends StatelessWidget {
  const LeafApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: Store.themeMode,
      builder: (_, mode, __) => MaterialApp(
        title: 'Leaf',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: leafTheme(Brightness.light),
        darkTheme: leafTheme(Brightness.dark),
        home: const SplashPage(),
      ),
    );
  }
}

// ------------------------------------------------------------------ splash

const _splashBg = Color(0xFF123A25);
const _cream = Color(0xFFF5EFDF);

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() async {
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, __, ___) => const HomePage(),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _splashBg,
      body: Stack(
        children: [
          Positioned(
            left: -90,
            bottom: -120,
            child: Transform.rotate(
                angle: 0.3, child: const _LeafShape(size: 420, color: Color(0xFF16462D))),
          ),
          Positioned(
            right: -130,
            top: -110,
            child: Transform.rotate(
                angle: -0.5, child: const _LeafShape(size: 360, color: Color(0xFF154129))),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) {
                final t = Curves.easeOutCubic.transform(_c.value);
                final wobble = math.sin(_c.value * math.pi) * -0.14;
                final fold = ((_c.value - 0.4) / 0.6).clamp(0.0, 1.0);
                final word = ((_c.value - 0.55) / 0.45).clamp(0.0, 1.0);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: (t * 2).clamp(0.0, 1.0),
                      child: Transform.rotate(
                        angle: wobble,
                        child: Transform.scale(
                          scale: 0.9 + 0.1 * t,
                          child: _LeafMark(fold: Curves.easeOut.transform(fold)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Opacity(
                      opacity: word,
                      child: Transform.translate(
                        offset: Offset(0, 10 * (1 - word)),
                        child: Text('Leaf',
                            style: GoogleFonts.fraunces(
                                fontSize: 44,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1,
                                color: _cream)),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

const _leafRadius = BorderRadius.only(
  topLeft: Radius.circular(6),
  topRight: Radius.circular(110),
  bottomRight: Radius.circular(6),
  bottomLeft: Radius.circular(110),
);

class _LeafShape extends StatelessWidget {
  const _LeafShape({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(size),
            bottomLeft: Radius.circular(size),
          ),
        ),
      );
}

/// Logo: daun yang juga selembar halaman, sudutnya terlipat seperti dibalik.
class _LeafMark extends StatelessWidget {
  const _LeafMark({required this.fold});
  final double fold;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: _cream,
              borderRadius: _leafRadius,
              boxShadow: [
                BoxShadow(color: Colors.black38, blurRadius: 40, offset: Offset(0, 18))
              ],
            ),
          ),
          const Positioned.fill(child: CustomPaint(painter: _VeinPainter())),
          Positioned.fill(
            child: ClipPath(
              clipper: _FoldClipper(fold),
              child: Container(
                decoration: const BoxDecoration(
                  borderRadius: _leafRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [Color(0xFF8FD6A6), Color(0xFFD9EFE0)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VeinPainter extends CustomPainter {
  const _VeinPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final main = Paint()
      ..color = const Color(0xFF2F7A4F)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final side = Paint()
      ..color = const Color(0xFF9DC9AC)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(s.width * .16, s.height * .84),
        Offset(s.width * .84, s.height * .16), main);
    for (final f in [0.34, 0.48, 0.62]) {
      final o = Offset(s.width * f, s.height * (1 - f));
      canvas.drawLine(o, o + const Offset(-4, -22), side);
      canvas.drawLine(o, o + const Offset(22, 4), side);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FoldClipper extends CustomClipper<Path> {
  _FoldClipper(this.t);
  final double t;

  @override
  Path getClip(Size s) {
    final d = s.width * 0.42 * t;
    return Path()
      ..moveTo(s.width, 0)
      ..lineTo(s.width - d, 0)
      ..lineTo(s.width, d)
      ..close();
  }

  @override
  bool shouldReclip(covariant _FoldClipper old) => old.t != t;
}
