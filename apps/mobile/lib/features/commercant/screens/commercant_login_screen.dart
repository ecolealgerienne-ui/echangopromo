import 'package:flutter/material.dart';

class CommercantLoginScreen extends StatelessWidget {
  const CommercantLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Espace commerçant')),
      body: const Center(child: Text('Connexion téléphone + code PIN')),
    );
  }
}
