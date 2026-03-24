// lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart'; 
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  String _pin = '';
  final int _pinLength = 4;
  String? _errorMessage;
  bool _isLoading = false;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400), 
      vsync: this,
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 15), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 15, end: -15), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -15, end: 15), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 15, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onKeypadTap(String value) {
    if (_isLoading) return;
    
    HapticFeedback.lightImpact();
    setState(() {
      _errorMessage = null;
      if (value == 'backspace') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < _pinLength) {
        _pin += value;
        if (_pin.length == _pinLength) {
          _handleLogin();
        }
      }
    });
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await AuthService.login(_pin);

    if (!mounted) return;

    if (result['success'] == true) {
      HapticFeedback.heavyImpact();
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const DashboardScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation, 
              child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)), child: child)
            );
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    } else {
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0); 
      setState(() {
        _isLoading = false;
        _pin = ''; 
        _errorMessage = result['message'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    
    final bgColor = isDark ? const Color(0xFF0F1115) : const Color(0xFFF4F6F9);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final brandOrange = const Color(0xFFF28C38);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2), // 👉 Empurra o conteúdo suavemente para baixo

            // 1. LOGO E CABEÇALHO
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1D24) : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: brandOrange.withOpacity(0.15), blurRadius: 40, spreadRadius: 5, offset: const Offset(0, 10)),
                ],
              ),
              child: Image.asset(
                'assets/logo.png',
                height: 60,
                width: 60,
                fit: BoxFit.contain,
                errorBuilder: (ctx, err, stack) => Icon(Icons.two_wheeler_rounded, size: 60, color: brandOrange),
              ),
            ),
            const SizedBox(height: 32),
            
            Text(
              'Portal do Entregador',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -1.0),
            ),
            const SizedBox(height: 8),
            Text(
              'Digite seu PIN de acesso',
              style: TextStyle(fontSize: 16, color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
            ),
            
            const Spacer(flex: 1), // 👉 Espaço flexível

            // 2. INDICADORES DO PIN (Bolinhas)
            AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_shakeAnimation.value, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength, (index) {
                  final isFilled = index < _pin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    height: isFilled ? 20 : 16, 
                    width: isFilled ? 20 : 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled 
                          ? brandOrange 
                          : (isDark ? const Color(0xFF2C2F36) : const Color(0xFFE2E8F0)),
                      border: isFilled ? null : Border.all(color: isDark ? Colors.transparent : Colors.grey.shade300, width: 1.5),
                      boxShadow: isFilled ? [
                        BoxShadow(color: brandOrange.withOpacity(0.4), blurRadius: 12, spreadRadius: 2, offset: const Offset(0, 4))
                      ] : [],
                    ),
                  );
                }),
              ),
            ),

            // 3. ÁREA DE MENSAGENS (Loading ou Erro com altura fixa pra não pular)
            const SizedBox(height: 24),
            SizedBox(
              height: 40, 
              child: Center(
                child: _isLoading
                    ? SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: brandOrange, strokeWidth: 3))
                    : _errorMessage != null
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                            child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700, fontSize: 14)),
                          )
                        : const SizedBox(),
              ),
            ),

            const Spacer(flex: 2), // 👉 Empurra o teclado para o fundo

            // 4. O NOVO NUMPAD (Clean, sem caixas e sem bordas)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (var j = 1; j <= 3; j++)
                          _buildNumpadButton('${i * 3 + j}', textColor, isDark),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const SizedBox(width: 75, height: 75), // Alinhamento fantasma
                      _buildNumpadButton('0', textColor, isDark),
                      _buildNumpadButton('backspace', textColor, isDark),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32), // Respiro final da tela
          ],
        ),
      ),
    );
  }

  // 👉 BOTÕES DO TECLADO: Flutuantes e minimalistas
  Widget _buildNumpadButton(String value, Color textColor, bool isDark) {
    final isBackspace = value == 'backspace';
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onKeypadTap(value),
        customBorder: const CircleBorder(), // Deixa o splash arredondado
        splashColor: const Color(0xFFF28C38).withOpacity(0.2),
        highlightColor: const Color(0xFFF28C38).withOpacity(0.1),
        child: Container(
          width: 75, 
          height: 75,
          alignment: Alignment.center,
          child: isBackspace
              ? Icon(Icons.backspace_rounded, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), size: 28)
              : Text(
                  value,
                  // Fonte um pouco mais fina (w400 ou w500) para dar o tom "Apple"
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w500, color: textColor),
                ),
        ),
      ),
    );
  }
}