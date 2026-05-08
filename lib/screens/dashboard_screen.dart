import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'scanner_screen.dart';
import 'profile_tab.dart';
import 'corridas_tab.dart';
import 'mapa_tab.dart';
import 'home_tab.dart'; // O novo tab refatorado

import '../widgets/ao_gosto_bottom_bar.dart'; 
import '../services/location_service.dart';

// Modais Extraídos
import '../widgets/dashboard_filter_modal.dart';
import '../widgets/dashboard_extrato_modal.dart';
import '../widgets/dashboard_fechamento_modal.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  int _currentTabIndex = 0;
  bool _isFirstLoad = true;
  
  String? _cachedEntregadorName;
  String? _cachedCD;
  String? _fotoPerfilLocal;
  String? _fotoPerfilUrl;

  bool _isTracking = false;

  double _saldoDoPeriodo = 0.0;
  double _totalMaquininha = 0.0;
  int _entregasPendentes = 0;
  int _entregasConcluidas = 0;
  int _tempoMedioMinutos = 0;
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
    DateTime? dt;

    if (value is Timestamp) {
      dt = value.toDate();
    } else if (value is String) {
      dt = DateTime.tryParse(value);
      if (dt == null && value.contains(' de ')) {
        try {
          final partes = value.split(' às ');
          final pedacosData = partes[0].trim().split(' de ');
          if (pedacosData.length == 3) {
            final dia = int.parse(pedacosData[0]);
            final mesStr = pedacosData[1].toLowerCase().trim();
            final ano = int.parse(pedacosData[2]);
            const meses = {'janeiro': 1, 'fevereiro': 2, 'março': 3, 'abril': 4, 'maio': 5, 'junho': 6, 'julho': 7, 'agosto': 8, 'setembro': 9, 'outubro': 10, 'novembro': 11, 'dezembro': 12};
            final mes = meses[mesStr] ?? 1;
            int hora = 0, minuto = 0, segundo = 0;
            if (partes.length > 1) {
              final pedacosHora = partes[1].trim().split(' ')[0].split(':');
              if (pedacosHora.isNotEmpty) hora = int.parse(pedacosHora[0]);
              if (pedacosHora.length > 1) minuto = int.parse(pedacosHora[1]);
              if (pedacosHora.length > 2) segundo = int.parse(pedacosHora[2]);
            }
            dt = DateTime(ano, mes, dia, hora, minuto, segundo);
          }
        } catch (e) {
          debugPrint('Falha ao traduzir: $value');
        }
      }
    }

    if (dt != null) {
      if (dt.year == 2026 && dt.month == 1 && dt.day == 1) return null;
      return dt;
    }
    return null;
  }

  Future<void> _fetchDashboardData() async {
    if (_cachedEntregadorName == null) return;
    setState(() => _isLoadingDados = true);

    try {
      double totalCorridas = 0.0;
      double totalExtras = 0.0;
      double auditorMaquininha = 0.0; 
      int countPendentes = 0;
      int countConcluidas = 0;
      int somaMinutosSla = 0; 
      int countSlaValidos = 0;
      List<Map<String, dynamic>> extrato = [];

      final pedidosQuery = await FirebaseFirestore.instance.collection('pedidos')
          .where('entregador', isEqualTo: _cachedEntregadorName)
          .get();

      for (var doc in pedidosQuery.docs) {
        try {
          final data = doc.data();
          final status = data['status']?.toString().toLowerCase() ?? '';

          if (status.contains('conclu') || status.contains('entregue')) {
            DateTime? dt;
            if (data['agendamento'] is Map && data['agendamento']['is_agendado'] == true) {
              dt = _safeDate(data['agendamento']['data']);
            }
            dt ??= _safeDate(data['data_entrega']) ?? _safeDate(data['data_conclusao']) ?? _safeDate(data['timestamp']) ?? _safeDate(data['created_at']);

            if (dt != null) {
              if (dt.isAfter(_startDate.subtract(const Duration(seconds: 1))) &&
                  dt.isBefore(_endDate.add(const Duration(seconds: 1)))) {
                countConcluidas++;
                
                DateTime? dtEntrega = _safeDate(data['data_entrega']) ?? _safeDate(data['data_conclusao']);
                DateTime? dtInicioRota = _safeDate(data['timestamp_atribuicao']) ?? _safeDate(data['timestamp']) ?? _safeDate(data['created_at']);
                
                if (dtEntrega != null && dtInicioRota != null && dtEntrega.isAfter(dtInicioRota)) {
                    int diffMinutos = dtEntrega.difference(dtInicioRota).inMinutes;
                    if (diffMinutos < (12 * 60)) { 
                        somaMinutosSla += diffMinutos;
                        countSlaValidos++;
                    }
                }

                double taxa = 0.0;
                if (data['pagamento'] is Map) {
                  taxa = _safeDouble(data['pagamento']['taxa_entrega']);
                  String metodo = (data['pagamento']['metodo_principal'] ?? '').toString().toLowerCase();
                  bool isOnline = metodo.contains('site') || metodo.contains('online') || metodo.contains('pix');
                  
                  if (!isOnline) {
                    auditorMaquininha += _safeDouble(data['pagamento']['valor_total']);
                  }
                } else {
                  taxa = _safeDouble(data['taxa_entrega']);
                }
                
                totalCorridas += taxa;
                
                extrato.add({
                  'tipo': 'corrida', 'id': doc.id, 'valor': taxa, 'data': dt,
                  'desc': 'Pedido #${doc.id}', 'icone': Icons.two_wheeler_rounded, 'cor': const Color(0xFF10B981)
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
          _totalMaquininha = auditorMaquininha; 
          _entregasPendentes = countPendentes;
          _entregasConcluidas = countConcluidas;
          _tempoMedioMinutos = countSlaValidos > 0 ? (somaMinutosSla / countSlaValidos).round() : 0;
          _extratoDoPeriodo = extrato;
          _isLoadingDados = false;

          if (_isFirstLoad && _entregasPendentes > 0) {
            _currentTabIndex = 1;
          }
          _isFirstLoad = false;
        });
      }
    } catch (e) {
      debugPrint('Erro fatal no motor de dados: $e');
      if (mounted) setState(() => _isLoadingDados = false);
    }
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

  void _onTabTapped(int index) {
    HapticFeedback.lightImpact();
    _loadUserData();
    if (index == 0) _fetchDashboardData();
    setState(() => _currentTabIndex = index);
  }

  void _handleScanTap() async {
    if (!_isTracking) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Row(children: [Icon(Icons.info_outline_rounded, color: Colors.white), SizedBox(width: 8), Expanded(child: Text('Fique On-line para escanear pedidos!', style: TextStyle(color: Colors.white)))]), backgroundColor: Colors.amber.shade800, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      );
      return;
    }

    final result = await Navigator.push(context, PageRouteBuilder(pageBuilder: (c, a, sa) => const ScannerScreen(), transitionsBuilder: (c, a, sa, child) => FadeTransition(opacity: a, child: child)));
    if (result == true && mounted) _onTabTapped(1);
  }

  Future<void> _toggleTracking() async {
    HapticFeedback.mediumImpact();
    
    if (_isTracking) {
      DashboardFechamentoModal.show(
        context,
        totalMaquininha: _totalMaquininha,
        saldoDoPeriodo: _saldoDoPeriodo,
        entregadorName: _cachedEntregadorName ?? 'Desconhecido',
        onSuccess: _desligarRadarComSucesso,
        onSkip: _desligarRadarSemComprovante,
      );
    } else {
      // 👉 Correção 1: Passando o context para a função
      bool sucesso = await LocationService.startTracking(context);
      
      // 👉 Correção 2: Trava de segurança para evitar crash se o usuário fechar a tela enquanto carregava
      if (!mounted) return;
      
      if (!sucesso) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [Icon(Icons.warning_rounded, color: Colors.white), SizedBox(width: 8), Expanded(child: Text('Permissão de GPS obrigatória! Autorize nas configurações.', style: TextStyle(color: Colors.white)))]), 
            backgroundColor: Colors.red.shade700, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
          ),
        );
        return;
      }

      setState(() => _isTracking = LocationService.isTracking);
      
      if (_isTracking) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [Icon(Icons.battery_charging_full_rounded, color: Colors.white, size: 20), SizedBox(width: 8), Expanded(child: Text('Conectado! Modo bateria economia 🔋', style: TextStyle(color: Colors.white)))]), 
            backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
          )
        );
      }
    }
  }

  void _desligarRadarComSucesso() {
    LocationService.stopTracking();
    setState(() => _isTracking = false);
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(children: [Icon(Icons.check_circle_rounded, color: Colors.white), SizedBox(width: 8), Expanded(child: Text('Fechamento concluído! Bom descanso.'))]),
        backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _desligarRadarSemComprovante() {
    LocationService.stopTracking();
    setState(() => _isTracking = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: const Text('Você está Off-line (Sem comprovante).', style: TextStyle(color: Colors.white)), backgroundColor: Colors.grey.shade800, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F1115) : const Color(0xFFF4F6F9);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        bottom: false, 
        child: IndexedStack(
          index: _currentTabIndex,
          children: [
            HomeTab(
              isDark: isDark,
              textColor: textColor,
              isTracking: _isTracking,
              entregadorName: _cachedEntregadorName ?? '',
              fotoPerfilLocal: _fotoPerfilLocal,
              fotoPerfilUrl: _fotoPerfilUrl,
              labelPeriodo: _labelPeriodo,
              saldoDoPeriodo: _saldoDoPeriodo,
              entregasPendentes: _entregasPendentes,
              entregasConcluidas: _entregasConcluidas,
              tempoMedioMinutos: _tempoMedioMinutos,
              isLoadingDados: _isLoadingDados,
              onToggleTracking: _toggleTracking,
              onAvatarTap: () => _onTabTapped(3),
              onShowFilter: () => DashboardFilterModal.show(
                context,
                isDark: isDark,
                labelPeriodo: _labelPeriodo,
                startDate: _startDate,
                endDate: _endDate,
                onApplyFilter: _applyFilter,
              ),
              onShowExtrato: () => DashboardExtratoModal.show(
                context,
                isDark: isDark,
                labelPeriodo: _labelPeriodo,
                saldoDoPeriodo: _saldoDoPeriodo,
                extratoDoPeriodo: _extratoDoPeriodo,
              ),
            ),
            CorridasTab(entregadorName: _cachedEntregadorName ?? ''),
            const MapaTab(),
            ProfileTab(initialName: _cachedEntregadorName ?? 'Entregador', cdName: _cachedCD ?? 'Sem CD', isTracking: _isTracking),
          ],
        ),
      ),
      extendBody: true, 
      bottomNavigationBar: AoGostoBottomBar(currentIndex: _currentTabIndex, onTap: _onTabTapped, onScanTap: _handleScanTap),
    );
  }
}