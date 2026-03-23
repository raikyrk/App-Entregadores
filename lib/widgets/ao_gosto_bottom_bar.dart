// lib/widgets/ao_gosto_bottom_bar.dart

import 'dart:ui';
import 'package:flutter/material.dart';

class AoGostoBottomBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final VoidCallback onScanTap; 

  const AoGostoBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onScanTap,
  });

  @override
  State<AoGostoBottomBar> createState() => _AoGostoBottomBarState();
}

class _AoGostoBottomBarState extends State<AoGostoBottomBar> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    
    final barColor = isDark ? const Color(0xFF16181D).withOpacity(0.85) : Colors.white.withOpacity(0.9);
    final borderColor = isDark ? Colors.white.withOpacity(0.08) : const Color(0xFF0F172A).withOpacity(0.04);

    return SafeArea(
      bottom: true,
      child: Padding(
        // 👉 A MÁGICA: Reduzimos o bottom de 8 para ZERO para o dock assentar perfeitamente lá embaixo!
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: SizedBox(
          height: 85, // Altura total reservada para o botão "vazar"
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // 1. A BASE DE VIDRO FOSCO (O DOCK)
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    height: 65,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: borderColor, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 2. OS ÍCONES E O BOTÃO CENTRAL
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildNavItem(0, Icons.grid_view_rounded, isDark),
                  _buildNavItem(1, Icons.two_wheeler_rounded, isDark),
                  
                  _buildMainActionNode(isDark),
                  
                  _buildNavItem(2, Icons.map_outlined, isDark),
                  _buildNavItem(3, Icons.person_outline_rounded, isDark),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, bool isDark) {
    final isSelected = widget.currentIndex == index;
    final activeColor = const Color(0xFFF28C38);
    final inactiveColor = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onTap(index),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 65,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.all(isSelected ? 8 : 0),
                decoration: BoxDecoration(
                  color: isSelected ? activeColor.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon, 
                  color: isSelected ? activeColor : inactiveColor, 
                  size: isSelected ? 26 : 24
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 4,
                width: isSelected ? 16 : 0, 
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainActionNode(bool isDark) {
    // Cor da borda que faz o "recorte" visual. Precisa bater com o fundo do app!
    final strokeColor = isDark ? const Color(0xFF0F1115) : const Color(0xFFF4F6F9);

    return GestureDetector(
      onTap: widget.onScanTap,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Container(
            margin: const EdgeInsets.only(bottom: 15), // Faz ele flutuar pra cima da barra
            height: 66,
            width: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFF28C38), Color(0xFFE87A24)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: strokeColor, 
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF28C38).withOpacity(0.5 * _pulseAnimation.value),
                  blurRadius: 15 + (10 * _pulseAnimation.value),
                  spreadRadius: 2 + (4 * _pulseAnimation.value),
                ),
              ],
            ),
            child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 28),
          );
        },
      ),
    );
  }
}