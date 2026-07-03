import 'package:flutter/material.dart';

class PromoListScreen extends StatelessWidget {
  const PromoListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('echango Promo')),
      body: const Center(child: Text('Liste des promos actives')),
    );
  }
}
