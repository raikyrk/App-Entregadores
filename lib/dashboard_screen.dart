// lib/dashboard_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/login_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/profile_tab.dart';
import 'screens/corridas_tab.dart';
import 'screens/mapa_tab.dart';
import 'widgets/ao_gosto_bottom_bar.dart';
import 'services/location_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  int _currentTabIndex = 0;
  String? _cachedEntregadorName;
  String? _cachedCD;
  String? _fotoPerfilLocal;
  String? _fotoPerfilUrl;

  bool _isTracking = false;

  double _saldoDoPeriodo = 0.0;
  int _entregasPendentes = 0;
  int _entregasConcluidas = 0;
  List<Map<String, dynamic>> _extratoDoPeriodo = [];
  bool _isLoadingDados = true;

  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _endDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59);
  String _labelPeriodo = 'Hoje';

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('pt_BR', null);
    _isTracking = LocationService.isTracking;
    _loadUserData().then((_) => _fetchDashboardData());
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _cachedEntregadorName = prefs.getString('entregador');
      _cachedCD = prefs.getString('cd_entregador') ?? 'Central Ao Gosto';
      _fotoPerfilLocal = prefs.getString('foto_perfil_local');
      _fotoPerfilUrl = prefs.getString('foto_perfil_url');
    });
  }

  double _safeDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }

  DateTime? _safeDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<void> _fetchDashboardData() async {
    if (_cachedEntregadorName == null) return;
    setState(() => _isLoadingDados = true);

    try {
      double totalCorridas = 0.0;
      double totalExtras = 0.0;
      int countPendentes = 0;
      int countConcluidas = 0;
      List<Map<String, dynamic>> extrato = [];

      final pedidosQuery = await FirebaseFirestore.instance.collection('pedidos')
          .where('entregador', isEqualTo: _cachedEntregadorName)
          .get();

      for (var doc in pedidosQuery.docs) {
        try {
          final data = doc.data();
          final status = data['status']?.toString().toLowerCase() ?? '';

          if (status.contains('conclu') || status.contains('entregue')) {
            DateTime? dt = _safeDate(data['data_entrega']) ?? _safeDate(data['timestamp']) ?? _safeDate(data['created_at']);

            if (dt != null) {
              if (dt.isAfter(_startDate.subtract(const Duration(seconds: 1))) &&
                  dt.isBefore(_endDate.add(const Duration(seconds: 1)))) {
                countConcluidas++;
                double taxa = 0.0;
                if (data['pagamento'] is Map) {
                  taxa = _safeDouble(data['pagamento']['taxa_entrega']);
                } else {
                  taxa = _safeDouble(data['taxa_entrega']);
                }
                totalCorridas += taxa;
                extrato.add({
                  'tipo': 'corrida', 
                  'id': doc.id, 
                  'valor': taxa, 
                  'data': dt,
                  'desc': '#${doc.id}', 
                  'icone': Icons.two_wheeler_rounded, 
                  'cor': const Color(0xFF10B981)
                });
              }
            }
          } else if (status.contains('saiu') || status.contains('andamento')) {
            countPendentes++;
          }
        } catch (e) {
          debugPrint('⚠️ Erro ao calcular pedido ${doc.id} (Ignorado). Erro: $e');
        }
      }

      final extrasQuery = await FirebaseFirestore.instance.collection('entregadores_extras')
          .where('entregador_nome', isEqualTo: _cachedEntregadorName)
          .get();

      for (var doc in extrasQuery.docs) {
        try {
          final data = doc.data();
          DateTime? dt = _safeDate(data['data']) ?? _safeDate(data['created_at']);

          if (dt != null) {
            if (dt.isAfter(_startDate.subtract(const Duration(seconds: 1))) &&
                dt.isBefore(_endDate.add(const Duration(seconds: 1)))) {
              double valor = _safeDouble(data['valor']);
              totalExtras += valor;
              extrato.add({
                'tipo': 'extra', 'id': doc.id, 'valor': valor, 'data': dt,
                'desc': data['descricao'] ?? 'Bônus Extra', 'icone': Icons.star_rounded, 'cor': const Color(0xFFF28C38)
              });
            }
          }
        } catch (e) {
          debugPrint('⚠️ Erro ao calcular extra ${doc.id} (Ignorado). Erro: $e');
        }
      }

      extrato.sort((a, b) => (b['data'] as DateTime).compareTo(a['data'] as DateTime));

      if (mounted) {
        setState(() {
          _saldoDoPeriodo = totalCorridas + totalExtras;
          _entregasPendentes = countPendentes;
          _entregasConcluidas = countConcluidas;
          _extratoDoPeriodo = extrato;
          _isLoadingDados = false;
        });
      }
    } catch (e) {
      debugPrint('Erro fatal no motor de dados: $e');
      if (mounted) setState(() => _isLoadingDados = false);
    }
  }

  void _showFilterModal(bool isDark) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1D24) : Colors.white, 
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32))
          ),
          child: SafeArea( 
            child: SingleChildScrollView( 
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)))),
                  const SizedBox(height: 24),
                  Text('Ver ganhos de:', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF0F172A)), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  
                  _buildFilterOption(ctx, 'Hoje', isDark, () {
                    final now = DateTime.now();
                    _applyFilter('Hoje', DateTime(now.year, now.month, now.day), DateTime(now.year, now.month, now.day, 23, 59, 59));
                  }),
                  _buildFilterOption(ctx, 'Ontem', isDark, () {
                    final ontem = DateTime.now().subtract(const Duration(days: 1));
                    _applyFilter('Ontem', DateTime(ontem.year, ontem.month, ontem.day), DateTime(ontem.year, ontem.month, ontem.day, 23, 59, 59));
                  }),
                  _buildFilterOption(ctx, 'Esta Semana', isDark, () {
                    final now = DateTime.now();
                    int daysToSubtract = now.weekday - 1;
                    final start = now.subtract(Duration(days: daysToSubtract));
                    _applyFilter('Esta Semana', DateTime(start.year, start.month, start.day), DateTime(now.year, now.month, now.day, 23, 59, 59));
                  }),
                  _buildFilterOption(ctx, 'Este Mês', isDark, () {
                    final now = DateTime.now();
                    _applyFilter('Este Mês', DateTime(now.year, now.month, 1), DateTime(now.year, now.month, now.day, 23, 59, 59));
                  }),
                  
                  // 👉 CALENDÁRIO COM UX/UI PREMIUM INJETADO
                  _buildFilterOption(ctx, 'Personalizado...', isDark, () async {
                    Navigator.pop(ctx); 
                    HapticFeedback.lightImpact();
                    
                    final DateTimeRange? picked = await showDateRangePicker(
                      context: context,
                      // Se os delegados estiverem no main.dart, adicione a linha abaixo para forçar PT-BR:
                      // locale: const Locale('pt', 'BR'), 
                      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
                      firstDate: DateTime(2023),
                      lastDate: DateTime.now().add(const Duration(days: 1)), 
                      helpText: 'SELECIONE O PERÍODO',
                      cancelText: 'CANCELAR',
                      confirmText: 'CONFIRMAR',
                      saveText: 'SALVAR',
                      builder: (context, child) {
                        final brandOrange = const Color(0xFFF28C38);
                        
                        return Theme(
                          data: ThemeData(
                            useMaterial3: true,
                            colorScheme: isDark 
                                ? ColorScheme.dark(
                                    primary: brandOrange, 
                                    onPrimary: Colors.white, 
                                    surface: const Color(0xFF1A1D24), 
                                    onSurface: Colors.white, 
                                    // 👉 A MÁGICA AQUI: Força os textos do calendário a ficarem visíveis!
                                    onSurfaceVariant: Colors.grey.shade400, 
                                  )
                                : ColorScheme.light(
                                    primary: brandOrange, 
                                    onPrimary: Colors.white,
                                    surface: Colors.white,
                                    onSurface: const Color(0xFF0F172A),
                                    onSurfaceVariant: const Color(0xFF64748B),
                                  ),
                            textButtonTheme: TextButtonThemeData(
                              style: TextButton.styleFrom(
                                foregroundColor: brandOrange,
                                textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5), // Botões mais chamativos
                              ),
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );

                    if (picked != null) {
                      final finalDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
                      final DateFormat formatoLabel = DateFormat('dd/MM');
                      final String customLabel = '${formatoLabel.format(picked.start)} - ${formatoLabel.format(picked.end)}';
                      
                      _applyFilter(customLabel, picked.start, finalDate);
                    }
                  }),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _applyFilter(String label, DateTime start, DateTime end) {
    if (Navigator.canPop(context) && label != _labelPeriodo && !label.contains('-')) {
      Navigator.pop(context);
    }
    HapticFeedback.lightImpact();
    setState(() {
      _labelPeriodo = label;
      _startDate = start;
      _endDate = end;
      _isLoadingDados = true;
    });
    _fetchDashboardData();
  }

  Widget _buildFilterOption(BuildContext ctx, String label, bool isDark, VoidCallback onTap) {
    final isSelected = _labelPeriodo == label;
    final isCustom = label == 'Personalizado...';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
          decoration: BoxDecoration(
            gradient: isSelected ? const LinearGradient(colors: [Color(0xFFF28C38), Color(0xFFE87A24)]) : null,
            color: isSelected ? null : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected ? [BoxShadow(color: const Color(0xFFF28C38).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))] : [],
            border: Border.all(
              color: isSelected 
                  ? Colors.transparent 
                  : (isCustom ? const Color(0xFFF28C38).withOpacity(0.5) : (isDark ? Colors.grey.shade800 : Colors.grey.shade200))
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label, 
                style: TextStyle(
                  fontSize: 16, 
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, 
                  color: isSelected ? Colors.white : (isCustom ? const Color(0xFFF28C38) : (isDark ? Colors.white : const Color(0xFF0F172A)))
                )
              ),
              if (isSelected) const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22)
              else if (isCustom) Icon(Icons.calendar_month_rounded, color: const Color(0xFFF28C38).withOpacity(0.8), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  void _onTabTapped(int index) {
    HapticFeedback.lightImpact();
    _loadUserData();
    if (index == 0) _fetchDashboardData();
    setState(() => _currentTabIndex = index);
  }

  Map<String, dynamic> _getSaudacao() {
    var hora = DateTime.now().hour;
    if (hora >= 5 && hora < 12) return {'texto': 'Bom dia,', 'icone': Icons.wb_sunny_rounded, 'cor': Colors.amber};
    if (hora >= 12 && hora < 18) return {'texto': 'Boa tarde,', 'icone': Icons.wb_sunny_rounded, 'cor': Colors.orange};
    return {'texto': 'Boa noite,', 'icone': Icons.nightlight_round, 'cor': Colors.indigo.shade300};
  }

  String _getInitials() {
    String nameToUse = _cachedEntregadorName ?? 'E';
    List<String> parts = nameToUse.trim().split(' ');
    if (parts.length > 1) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0][0].toUpperCase();
  }

  void _handleScanTap() async {
    if (!_isTracking) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Row(children: [Icon(Icons.info_outline_rounded, color: Colors.white), SizedBox(width: 8), Expanded(child: Text('Fique On-line para escanear pedidos!'))]), backgroundColor: Colors.amber.shade800, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      );
      return;
    }

    final result = await Navigator.push(context, PageRouteBuilder(pageBuilder: (c, a, sa) => const ScannerScreen(), transitionsBuilder: (c, a, sa, child) => FadeTransition(opacity: a, child: child)));
    if (result == true && mounted) _onTabTapped(1);
  }

  Future<void> _toggleTracking() async {
    HapticFeedback.mediumImpact();
    if (_isTracking) {
      LocationService.stopTracking();
      setState(() => _isTracking = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Você está Off-line.'), backgroundColor: Colors.grey.shade800, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    } else {
      await LocationService.startTracking();
      setState(() => _isTracking = LocationService.isTracking);
      if (_isTracking) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Row(children: [Icon(Icons.battery_charging_full_rounded, color: Colors.white, size: 20), SizedBox(width: 8), Expanded(child: Text('Conectado! Modo econômico ativado 🔋'))]), backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F1115) : const Color(0xFFF4F6F9);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(bottom: false, child: _buildCurrentTab(isDark, textColor)),
      extendBody: true, 
      bottomNavigationBar: AoGostoBottomBar(currentIndex: _currentTabIndex, onTap: _onTabTapped, onScanTap: _handleScanTap),
    );
  }

  Widget _buildCurrentTab(bool isDark, Color textColor) {
    switch (_currentTabIndex) {
      case 0: return _buildHomeTab(isDark, textColor);
      case 1: return CorridasTab(entregadorName: _cachedEntregadorName ?? '');
      case 2: return const MapaTab();
      case 3: return ProfileTab(initialName: _cachedEntregadorName ?? 'Entregador', cdName: _cachedCD ?? 'Sem CD', isTracking: _isTracking);
      default: return _buildHomeTab(isDark, textColor);
    }
  }

  Widget _buildHomeTab(bool isDark, Color textColor) {
    final mainText = _isTracking ? 'Buscando novas\ncorridas...' : 'Pronto para\ncomeçar?';
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    final brandOrange = const Color(0xFFF28C38);
    final cardBgColor = isDark ? const Color(0xFF1A1D24) : Colors.white;
    final saudacao = _getSaudacao();

    String nomeCru = _cachedEntregadorName ?? 'Entregador';
    String nomeFormatado = nomeCru.isNotEmpty 
        ? '${nomeCru[0].toUpperCase()}${nomeCru.substring(1).toLowerCase()}'
        : 'Entregador';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16), 
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
                      style: TextStyle(fontSize: 14, color: isDark ? Colors.grey[400] : const Color(0xFF64748B), fontWeight: FontWeight.w600, letterSpacing: 0.2)
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/logo.png',
                          height: 30,
                          width: 30,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            nomeFormatado, 
                            style: TextStyle(fontSize: 26, color: textColor, fontWeight: FontWeight.w900, letterSpacing: -1.0, height: 1.0),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _PulseAvatar(initials: _getInitials(), isOnline: _isTracking, isDark: isDark, localPath: _fotoPerfilLocal, remoteUrl: _fotoPerfilUrl, onTap: () => _onTabTapped(3)),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 8),

                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(32), 
                    boxShadow: [
                      BoxShadow(
                        color: _isTracking ? const Color(0xFF10B981).withOpacity(0.08) : const Color(0xFF0F172A).withOpacity(0.04),
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
                          height: 130,
                          width: 130,
                          fit: BoxFit.contain,
                          opacity: const AlwaysStoppedAnimation(0.05),
                        ),
                      ),
                      
                      Padding(
                        padding: const EdgeInsets.all(28), 
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mainText, 
                              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: textColor, height: 1.1, letterSpacing: -1.0) 
                            ),
                            const SizedBox(height: 32), 
                            
                            InkWell(
                              onTap: _toggleTracking,
                              borderRadius: BorderRadius.circular(20),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: double.infinity, 
                                padding: const EdgeInsets.symmetric(vertical: 18), 
                                decoration: BoxDecoration(
                                  gradient: _isTracking 
                                      ? null 
                                      : LinearGradient(colors: [brandOrange, const Color(0xFFE87A24)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                  color: _isTracking ? Colors.red.withOpacity(0.1) : null,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: _isTracking ? [] : [
                                    BoxShadow(
                                      color: brandOrange.withOpacity(0.35), 
                                      blurRadius: 16, 
                                      offset: const Offset(0, 8)
                                    )
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(_isTracking ? Icons.power_settings_new_rounded : Icons.power_settings_new_rounded, color: _isTracking ? Colors.red.shade600 : Colors.white, size: 22),
                                    const SizedBox(width: 8),
                                    Text(
                                      _isTracking ? 'Ficar Off-line' : 'Iniciar Corridas', 
                                      style: TextStyle(color: _isTracking ? Colors.red.shade600 : Colors.white, fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.5)
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
                const SizedBox(height: 16),

                // 👉 O CIFRÃO ESTÁ DE VOLTA AQUI NO MEIO! (Como na image_28.png)
                GestureDetector(
                  onTap: () => _showExtratoModal(isDark),
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
                          offset: const Offset(0, 10)
                        )
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: 35, // Posição cravada pra dentro do card
                          bottom: -15,
                          child: Transform.rotate(
                            angle: -0.15, 
                            child: Text(
                              r'$', 
                              style: TextStyle(
                                fontSize: 130, 
                                fontWeight: FontWeight.w900, 
                                color: Colors.white.withOpacity(0.08), 
                                height: 1.0,
                              )
                            ),
                          ),
                        ),
                        // CONTEÚDO DO CARD
                        Padding(
                          padding: const EdgeInsets.all(22), 
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
                                        'Saldo: $_labelPeriodo', 
                                        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15, fontWeight: FontWeight.w600)
                                      ),
                                    ],
                                  ),
                                  InkWell(
                                    onTap: () => _showFilterModal(isDark),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.15), 
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _isLoadingDados 
                                  ? const SizedBox(height: 38, child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)))) 
                                  : Text(
                                      formatoMoeda.format(_saldoDoPeriodo), 
                                      style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.2) 
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: _PremiumBentoCard(
                        title: 'Pendentes', 
                        value: '$_entregasPendentes', 
                        icon: Icons.inventory_2_rounded, 
                        iconColor: brandOrange, 
                        isDark: isDark, 
                        isLoading: _isLoadingDados
                      )
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _PremiumBentoCard(
                        title: _labelPeriodo == 'Hoje' ? 'Hoje' : 'Concluídas', 
                        value: '$_entregasConcluidas', 
                        icon: Icons.check_circle_rounded, 
                        iconColor: const Color(0xFF10B981), 
                        isDark: isDark, 
                        isLoading: _isLoadingDados
                      )
                    ),
                  ],
                ),
                const SizedBox(height: 110), 
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showExtratoModal(bool isDark) {
    HapticFeedback.lightImpact();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoDataExtrato = DateFormat("dd/MM 'às' HH:mm", 'pt_BR');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85, 
        decoration: BoxDecoration(color: isDark ? const Color(0xFF0F1115) : const Color(0xFFF4F6F9), borderRadius: const BorderRadius.vertical(top: Radius.circular(36))),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
              decoration: BoxDecoration(color: isDark ? const Color(0xFF1A1D24) : Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(36)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))]),
              child: Column(
                children: [
                  Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)))),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Extrato', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A), letterSpacing: -0.5)),
                          const SizedBox(height: 4),
                          Text(_labelPeriodo, style: TextStyle(fontSize: 15, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      Text(formatoMoeda.format(_saldoDoPeriodo), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF10B981), letterSpacing: -0.5)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _extratoDoPeriodo.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.receipt_long_rounded, size: 70, color: Colors.grey.shade300), const SizedBox(height: 20), Text('Nenhuma transação no período.', style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w500))]))
                  : ListView.builder(
                      padding: const EdgeInsets.all(24),
                      physics: const BouncingScrollPhysics(),
                      itemCount: _extratoDoPeriodo.length,
                      itemBuilder: (context, index) {
                        final item = _extratoDoPeriodo[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1A1D24) : Colors.white, 
                            borderRadius: BorderRadius.circular(24), 
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14), 
                                decoration: BoxDecoration(color: (item['cor'] as Color).withOpacity(0.1), shape: BoxShape.circle), 
                                child: Icon(item['icone'] as IconData, color: item['cor'] as Color, size: 24)
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['desc'], style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: isDark ? Colors.white : const Color(0xFF0F172A)), overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 6),
                                    Text(formatoDataExtrato.format(item['data'] as DateTime), style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              Text('+ ${formatoMoeda.format(item['valor'])}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: item['cor'] as Color)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumBentoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final bool isDark;
  final bool isLoading;

  const _PremiumBentoCard({
    required this.title, required this.value, required this.icon, 
    required this.iconColor, required this.isDark, required this.isLoading
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D24) : Colors.white, 
        borderRadius: BorderRadius.circular(28), 
        boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10))]
      ),
      padding: const EdgeInsets.all(24), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, 
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16)
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 24), 
          isLoading 
            ? SizedBox(height: 38, child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: iconColor, strokeWidth: 3)))) 
            : Text(value, style: TextStyle(fontSize: 36, color: isDark ? Colors.white : const Color(0xFF0F172A), fontWeight: FontWeight.w900, letterSpacing: -1.0, height: 1.0)),
          const SizedBox(height: 6),
          Text(title, style: TextStyle(fontSize: 14, color: isDark ? Colors.grey[400] : const Color(0xFF64748B), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _PulseAvatar extends StatelessWidget {
  final String initials;
  final bool isOnline;
  final bool isDark;
  final String? localPath;
  final String? remoteUrl;
  final VoidCallback onTap;

  const _PulseAvatar({required this.initials, required this.isOnline, required this.isDark, this.localPath, this.remoteUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final statusColor = isOnline ? const Color(0xFF10B981) : Colors.grey.shade400;
    ImageProvider? profileImage;
    if (localPath != null && File(localPath!).existsSync()) profileImage = FileImage(File(localPath!));
    else if (remoteUrl != null && remoteUrl!.isNotEmpty) profileImage = NetworkImage(remoteUrl!);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 56, width: 56, 
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1D24) : Colors.white, 
              shape: BoxShape.circle, 
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5))],
              image: profileImage != null ? DecorationImage(image: profileImage, fit: BoxFit.cover) : null
            ), 
            child: profileImage == null ? Center(child: Text(initials, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontWeight: FontWeight.w800, fontSize: 18))) : null
          ),
          Positioned(
            bottom: 2, right: 0, 
            child: Container(
              height: 16, width: 16, 
              decoration: BoxDecoration(
                color: statusColor, shape: BoxShape.circle, 
                border: Border.all(color: isDark ? const Color(0xFF0F1115) : const Color(0xFFF4F6F9), width: 3)
              )
            )
          ),
        ],
      ),
    );
  }
}