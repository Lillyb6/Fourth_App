import 'package:flutter/material.dart';

class BerryLogo extends StatelessWidget {
  const BerryLogo({super.key, this.size = 72});
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/Berry_logo.webp',
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: 'Blueberry sprout',
  );
}

class BerryWordmark extends StatelessWidget {
  const BerryWordmark({super.key});
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/Berry_Daily_logo.webp',
    width: 110,
    height: 82,
    fit: BoxFit.contain,
    semanticLabel: 'Berry Daily',
  );
}
