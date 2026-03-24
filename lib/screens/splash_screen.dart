import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen.dart';
import 'dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _lottieCtrl;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _lottieCtrl = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _lottieCtrl.dispose();
    super.dispose();
  }

  void _checkAuthAndNavigate() async {
    final prefs = await SharedPreferences.getInstance();
    final entregadorName = prefs.getString('entregador');

    if (!mounted) return;

    if (entregadorName != null && entregadorName.isNotEmpty) {
      Navigator.pushReplacement(context, PageRouteBuilder(
        pageBuilder: (c, a, sa) => const DashboardScreen(),
        transitionsBuilder: (c, a, sa, child) => FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 1000), 
      ));
    } else {
      Navigator.pushReplacement(context, PageRouteBuilder(
        pageBuilder: (c, a, sa) => const LoginScreen(),
        transitionsBuilder: (c, a, sa, child) => FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 1000),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // =========================================================================
    // 👉 O SEGREDO DO ENQUADRAMENTO CINEMATOGRÁFICO
    // =========================================================================
    
    // Nossa cor Slate Dark do design (baseada no design de Big Tech)
    const brandDarkColor = Color(0xFF121212); 

    return Scaffold(
      backgroundColor: Colors.white, // Fundo base (não visível após o overlay)
      body: Stack(
        children: [
          // Camada 1: A Animação Lottie (Com Zoom/Fill)
          Positioned.fill(
            child: Lottie.asset(
              'assets/animations/splash_animation.json', 
              controller: _lottieCtrl,
              // 👉 MUDANÇA CRUCIAL: Preenche toda a tela (zumbido e corta as laterais)
              fit: BoxFit.cover, 
              onLoaded: (composition) {
                _lottieCtrl..duration = composition.duration..forward().then((_) {
                  _checkAuthAndNavigate();
                });
              },
            ),
          ),
          
          // Camada 2: A Sobreposição de Camada (Overlay)
          // Preenche toda a tela com o Slate Dark e 85% de opacidade
          Positioned.fill(
            child: Container(
              color: brandDarkColor.withOpacity(0.85),
            ),
          ),
          
          // Camada 3: A Logo 'Ao Gosto' (No Destaque)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 👉 Pegamos a sua logo escrita "Ao Gosto"
                Image.asset(
                  'assets/logo-nome.png',
                  height: 100, // Tamanho imponente
                  // 👉 A MÁGICA: Força a logo a branco!
                  color: Colors.white,
                  colorBlendMode: BlendMode.srcIn, 
                ),
                const SizedBox(height: 16),
                // Mantemos o texto 'Entregador' sutil
                Text(
                  'Entregador',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3.0, // Mais espaçado e premium
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}