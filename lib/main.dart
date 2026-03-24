import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart'; 
import 'firebase_options.dart';

import 'screens/splash_screen.dart';

// 👉 Se no futuro você usar o botão animado em outras telas, 
// o ideal é mover ele pra uma pasta 'widgets', mas por enquanto pode ficar aqui!

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Conecta no Firebase da Ao Gosto
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  ); 
  
  // Carrega as chaves secretas
  await dotenv.load(fileName: ".env");
  
  // 👉 Agora sim! Roda o app na classe correta
  runApp(const AoGostoApp());
}

class AoGostoApp extends StatelessWidget {
  const AoGostoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ao Gosto Delivery',
      debugShowCheckedModeBanner: false,
      // Força o tema escuro/slate que desenhamos pro app inteiro
      themeMode: ThemeMode.dark, 
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: const Color(0xFF121212), // Fundo principal Slate Dark
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFF28C38), // Nosso Laranja
          secondary: Color(0xFF10B981), // Nosso Verde de Sucesso
          surface: Color(0xFF1E1E1E), // Cor dos Cards/Bento Grid
        ),
      ),
      // 👉 MÁGICA: A primeira tela que abre agora é a animação do Lottie!
      home: const SplashScreen(), 
    );
  }
}

// =========================================================================
// WIDGET GLOBAL: Botão Animado (Legado, mas funcional)
// =========================================================================
class AnimatedScaleButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;

  const AnimatedScaleButton({required this.onPressed, required this.child, super.key});

  @override
  State<AnimatedScaleButton> createState() => _AnimatedScaleButtonState();
}

class _AnimatedScaleButtonState extends State<AnimatedScaleButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.95),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        transform: Matrix4.identity()..scale(_scale),
        child: ElevatedButton(
          onPressed: widget.onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF28C38),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 5,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}