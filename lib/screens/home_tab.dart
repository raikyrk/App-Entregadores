import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/pulse_avatar.dart';
import '../widgets/premium_bento_card.dart';

class HomeTab extends StatelessWidget {
  final bool isDark;
  final Color textColor;
  final bool isTracking;
  final String entregadorName;
  final String? fotoPerfilLocal;
  final String? fotoPerfilUrl;
  final String labelPeriodo;
  final double saldoDoPeriodo;
  final int entregasPendentes;
  final int entregasConcluidas;
  final int tempoMedioMinutos;
  final bool isLoadingDados;
  final VoidCallback onToggleTracking;
  final VoidCallback onShowFilter;
  final VoidCallback onShowExtrato;
  final VoidCallback onAvatarTap;

  const HomeTab({
    super.key,
    required this.isDark,
    required this.textColor,
    required this.isTracking,
    required this.entregadorName,
    this.fotoPerfilLocal,
    this.fotoPerfilUrl,
    required this.labelPeriodo,
    required this.saldoDoPeriodo,
    required this.entregasPendentes,
    required this.entregasConcluidas,
    required this.tempoMedioMinutos,
    required this.isLoadingDados,
    required this.onToggleTracking,
    required this.onShowFilter,
    required this.onShowExtrato,
    required this.onAvatarTap,
  });

  Map<String, dynamic> _getSaudacao() {
    var hora = DateTime.now().hour;
    if (hora >= 5 && hora < 12) return {'texto': 'Bom dia,', 'icone': Icons.wb_sunny_rounded, 'cor': Colors.amber};
    if (hora >= 12 && hora < 18) return {'texto': 'Boa tarde,', 'icone': Icons.wb_sunny_rounded, 'cor': Colors.orange};
    return {'texto': 'Boa noite,', 'icone': Icons.nightlight_round, 'cor': Colors.indigo.shade300};
  }

  String _getInitials() {
    String nameToUse = entregadorName.isNotEmpty ? entregadorName : 'E';
    List<String> parts = nameToUse.trim().split(' ');
    if (parts.length > 1) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0][0].toUpperCase();
  }

  Widget _buildTempoMedioCard(Color brandOrange) {
    String tempoText = tempoMedioMinutos > 0 ? '${tempoMedioMinutos}m' : '--';
    Color kpiColor = brandOrange;

    if (tempoMedioMinutos > 0) {
      if (tempoMedioMinutos <= 45) {
        kpiColor = const Color(0xFF10B981);
      } else if (tempoMedioMinutos > 60) {
        kpiColor = const Color(0xFFEF4444);
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D24) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kpiColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.speed_rounded, color: kpiColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tempo Médio',
                    style: TextStyle(
                        fontSize: 15, color: isDark ? Colors.white : const Color(0xFF0F172A), fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 2),
                Text('Das entregas de $labelPeriodo',
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[500] : const Color(0xFF64748B), fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          isLoadingDados
              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 3))
              : Text(tempoText, style: TextStyle(fontSize: 26, color: kpiColor, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mainText = isTracking ? 'Buscando\ncorridas...' : 'Pronto para\ncomeçar?';
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final brandOrange = const Color(0xFFF28C38);
    final cardBgColor = isDark ? const Color(0xFF1A1D24) : Colors.white;
    final saudacao = _getSaudacao();

    String nomeFormatado = entregadorName.isNotEmpty
        ? '${entregadorName[0].toUpperCase()}${entregadorName.substring(1).toLowerCase()}'
        : 'Entregador';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      saudacao['texto'],
                      style: TextStyle(
                          fontSize: 14, color: isDark ? Colors.grey[400] : const Color(0xFF64748B), fontWeight: FontWeight.w600, letterSpacing: 0.2),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Image.asset('assets/logo.png', height: 28, width: 28, fit: BoxFit.contain),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            nomeFormatado,
                            style: TextStyle(fontSize: 24, color: textColor, fontWeight: FontWeight.w900, letterSpacing: -1.0, height: 1.0),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              PulseAvatar(
                initials: _getInitials(),
                isOnline: isTracking,
                isDark: isDark,
                localPath: fotoPerfilLocal,
                remoteUrl: fotoPerfilUrl,
                onTap: onAvatarTap,
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: isTracking ? const Color(0xFF10B981).withOpacity(0.08) : const Color(0xFF0F172A).withOpacity(0.04),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      )
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned(
                        right: -15,
                        top: -10,
                        child: Image.asset(
                          'assets/go-laranja.png',
                          height: 120,
                          width: 120,
                          fit: BoxFit.contain,
                          opacity: const AlwaysStoppedAnimation(0.05),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mainText,
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: textColor, height: 1.1, letterSpacing: -1.0),
                            ),
                            const SizedBox(height: 20),
                            InkWell(
                              onTap: onToggleTracking,
                              borderRadius: BorderRadius.circular(20),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  gradient: isTracking
                                      ? null
                                      : LinearGradient(colors: [brandOrange, const Color(0xFFE87A24)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                  color: isTracking ? Colors.red.withOpacity(0.1) : null,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: isTracking
                                      ? []
                                      : [
                                          BoxShadow(
                                            color: brandOrange.withOpacity(0.35),
                                            blurRadius: 16,
                                            offset: const Offset(0, 8),
                                          )
                                        ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.power_settings_new_rounded, color: isTracking ? Colors.red.shade600 : Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      isTracking ? 'Ficar Off-line' : 'Iniciar Corridas',
                                      style: TextStyle(color: isTracking ? Colors.red.shade600 : Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: onShowExtrato,
                  child: Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      gradient: isDark
                          ? const LinearGradient(colors: [Color(0xFF222224), Color(0xFF161618)])
                          : const LinearGradient(colors: [Color(0xFF059669), Color(0xFF10B981)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: (isDark ? Colors.black : const Color(0xFF10B981)).withOpacity(0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        )
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: 35,
                          bottom: -15,
                          child: Transform.rotate(
                            angle: -0.15,
                            child: Text(
                              r'$',
                              style: TextStyle(
                                fontSize: 120,
                                fontWeight: FontWeight.w900,
                                color: Colors.white.withOpacity(0.08),
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.account_balance_wallet_rounded, color: Colors.white.withOpacity(0.8), size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Saldo: $labelPeriodo',
                                        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  InkWell(
                                    onTap: onShowFilter,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              isLoadingDados
                                  ? const SizedBox(
                                      height: 34,
                                      child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))))
                                  : Text(
                                      formatoMoeda.format(saldoDoPeriodo),
                                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.2),
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: PremiumBentoCard(
                        title: 'Pendentes',
                        value: '$entregasPendentes',
                        icon: Icons.inventory_2_rounded,
                        iconColor: brandOrange,
                        isDark: isDark,
                        isLoading: isLoadingDados,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PremiumBentoCard(
                        title: labelPeriodo == 'Hoje' ? 'Hoje' : 'Concluídas',
                        value: '$entregasConcluidas',
                        icon: Icons.check_circle_rounded,
                        iconColor: const Color(0xFF10B981),
                        isDark: isDark,
                        isLoading: isLoadingDados,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTempoMedioCard(brandOrange),
                const SizedBox(height: 110),
              ],
            ),
          ),
        ),
      ],
    );
  }
}