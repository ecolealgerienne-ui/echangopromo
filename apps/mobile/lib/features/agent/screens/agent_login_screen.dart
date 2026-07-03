import 'package:flutter/material.dart';

class AgentLoginScreen extends StatelessWidget {
  const AgentLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Espace agent terrain')),
      body: const Center(child: Text('Connexion email + mot de passe')),
    );
  }
}
