import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'main.dart';
import 'dashboard_screen.dart';
import 'scanner_screen.dart';

@immutable
class DeliveriesScreen extends StatefulWidget {
  final int initialTabIndex;

  const DeliveriesScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends State<DeliveriesScreen>
    with SingleTickerProviderStateMixin {
  List<DateTime> _selectedDates = [DateTime.now()];
  List<Map<String, dynamic>> _pendingDeliveries = [];
  List<Map<String, dynamic>> _completedDeliveries = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  late SharedPreferences _prefs;
  String? _errorMessage;
  late TabController _tabController;
  final ImagePicker _picker = ImagePicker();
  Timer? _notificationTimer;

  static const Color primary = Color(0xFFF28C38);
  static const Color success = Color(0xFF48BB78);
  static const Color danger = Color(0xFFE53E3E);
  static const Color info = Color(0xFF4299E1);
  static const Color light = Color(0xFFF7FAFC);
  static const Color dark = Color(0xFF1A202C);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTabIndex);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) setState(() {});
    });

    _initializePrefs().then((_) {
      if (mounted) {
        _fetchDeliveries();
      }
    });
  }

  Future<void> _initializePrefs() async {
    _prefs = await SharedPreferences.getInstance();
  }

  void _startNotificationTimer() {
    _notificationTimer?.cancel();
    _notificationTimer = Timer.periodic(
        const Duration(minutes: 10), (_) => _checkPendingDeliveries());
  }

  Future<void> _checkPendingDeliveries() async {
    final now = DateTime.now();
    for (final delivery in _pendingDeliveries) {
      final ts = DateTime.tryParse(delivery['timestamp'] ?? '');
      if (ts != null && now.difference(ts).inHours >= 1) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: Colors.white,
            title: const Text('Lembrete de Conclusão',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: dark)),
            content: Text(
                'O pedido #${delivery['id_pedido']} está pendente há mais de 1 hora. Deseja marcá-lo como concluído?',
                style: const TextStyle(fontSize: 14, color: Colors.grey)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Colors.grey),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Ignorar'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _markAsCompleted(delivery['id_pedido'], delivery['timestamp'], delivery['telefone']);
                },
                style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: success,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Concluir'),
              ),
            ],
          ),
        );
        break;
      }
    }
  }

  Future<void> _fetchDeliveries() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _pendingDeliveries = [];
      _completedDeliveries = [];
    });

    try {
      final entregador = _prefs.getString('entregador') ?? '';
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final deliveriesEndpoint = dotenv.env['DELIVERIES_ENDPOINT'] ?? '';
      final completedEndpoint = dotenv.env['COMPLETED_DELIVERIES_ENDPOINT'] ?? '';

      if (baseUrl.isEmpty || deliveriesEndpoint.isEmpty || completedEndpoint.isEmpty) {
        throw Exception('Variáveis de ambiente não definidas');
      }

      final pendingResp = await http.get(
        Uri.parse('$baseUrl$deliveriesEndpoint&entregador=${Uri.encodeComponent(entregador)}'),
      ).timeout(const Duration(seconds: 10));

      if (pendingResp.statusCode != 200) {
        throw Exception('Erro ao buscar pendentes: ${pendingResp.statusCode}');
      }

      final pendingJson = jsonDecode(pendingResp.body);
      if (pendingJson['status'] != 'success') {
        throw Exception('Pendentes: ${pendingJson['message']}');
      }

      final List<Map<String, dynamic>> pendentes = List.from(pendingJson['deliveries']);
      for (final d in pendentes) {
        d['is_completed'] = false;
        d['taxa_entrega'] = double.parse(d['taxa_entrega'].toString());
        _pendingDeliveries.add(d);
      }

      for (final date in _selectedDates) {
        final fmt = DateFormat('yyyy-MM-dd').format(date);
        final compResp = await http.get(
          Uri.parse('$baseUrl$completedEndpoint&entregador=${Uri.encodeComponent(entregador)}&date=$fmt'),
        ).timeout(const Duration(seconds: 10));

        if (compResp.statusCode != 200) {
          throw Exception('Erro ao buscar concluídas: ${compResp.statusCode}');
        }

        final compJson = jsonDecode(compResp.body);
        if (compJson['status'] != 'success') {
          throw Exception('Concluídas: ${compJson['message']}');
        }

        final List<Map<String, dynamic>> concluidas = List.from(compJson['deliveries']);
        for (final d in concluidas) {
          d['is_completed'] = true;
          d['taxa_entrega'] = double.parse(d['taxa_entrega'].toString());
          _completedDeliveries.add(d);
        }
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
      _startNotificationTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Erro ao carregar entregas: $e';
      });
    }
  }

  Future<void> enviarMensagemConcluido(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber == 'N/A' || phoneNumber.trim().isEmpty) {
      developer.log('Telefone inválido');
      return;
    }

    const mensagem = "Parece que o seu pedido foi concluído com sucesso! \n\nEspero que goste de nossos produtos";
    final phone = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) return;

    final url = dotenv.env['MESSAGE_API_URL'] ?? '';
    final key = dotenv.env['MESSAGE_API_KEY'] ?? '';
    if (url.isEmpty || key.isEmpty) return;

    final payload = {"number": phone, "text": mensagem};
    final headers = {"Content-Type": "application/json", "apikey": key};

    try {
      await http.post(Uri.parse(url), headers: headers, body: jsonEncode(payload)).timeout(const Duration(seconds: 10));
    } catch (e) {
      developer.log('Erro ao enviar mensagem: $e');
    }
  }

  Future<void> _markAsCompleted(String id, String timestamp, String? telefone) async {
    final entregador = _prefs.getString('entregador') ?? '';
    setState(() => _isLoading = true);
    try {
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final endpoint = dotenv.env['MARK_COMPLETED_ENDPOINT'] ?? '';
      if (baseUrl.isEmpty || endpoint.isEmpty) throw Exception('Endpoints ausentes');

      final resp = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'id_pedido': id,
          'nome_entregador': entregador,
          'timestamp': timestamp,
          'timestamp_concluido': DateTime.now().toIso8601String(),
        },
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) throw Exception('Status ${resp.statusCode}');
      final data = jsonDecode(resp.body);
      if (data['status'] != 'success') throw Exception(data['message']);

      await enviarMensagemConcluido(telefone);
      await _fetchDeliveries();
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entrega concluída!')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao concluir: $e')));
    }
  }

  Future<void> _deleteDelivery(String id, String timestamp, bool isCompleted) async {
    final entregador = _prefs.getString('entregador') ?? '';
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    setState(() => _isLoading = true);
    try {
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final deletePend = dotenv.env['DELETE_DELIVERY_ENDPOINT'] ?? '';
      final deleteComp = dotenv.env['DELETE_COMPLETED_DELIVERY_ENDPOINT'] ?? '';
      final planilhaEx = dotenv.env['PLANILHA_EXCLUIR_ENDPOINT'] ?? '';

      if (baseUrl.isEmpty || deletePend.isEmpty || deleteComp.isEmpty || planilhaEx.isEmpty) {
        throw Exception('Endpoints de exclusão ausentes');
      }

      if (!isCompleted) {
        final planUrl = '$baseUrl$planilhaEx?excluir=1&id=$id&data=$today&timestamp=${Uri.encodeComponent(timestamp)}&entregador=${Uri.encodeComponent(entregador)}';
        final planResp = await http.get(Uri.parse(planUrl)).timeout(const Duration(seconds: 10));
        if (planResp.statusCode != 200) throw Exception('Erro planilha: ${planResp.statusCode}');
      }

      final apiUrl = isCompleted ? '$baseUrl$deleteComp' : '$baseUrl$deletePend';
      final dbResp = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'id_pedido': id, 'nome_entregador': entregador, 'timestamp': timestamp},
      ).timeout(const Duration(seconds: 10));

      if (dbResp.statusCode != 200) throw Exception('DB: ${dbResp.statusCode}');
      final dbData = jsonDecode(dbResp.body);
      if (dbData['status'] != 'success') throw Exception(dbData['message']);

      await _fetchDeliveries();
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entrega excluída!')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDates.isNotEmpty
          ? DateTimeRange(start: _selectedDates.first, end: _selectedDates.last)
          : DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2028, 12, 31),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: primary, onPrimary: Colors.white, surface: Colors.white, onSurface: Colors.black87),
          textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: primary)),
        ),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600), child: child)),
      ),
    );

    if (picked != null) {
      setState(() {
        _selectedDates = [];
        var cur = picked.start;
        while (!cur.isAfter(picked.end)) {
          _selectedDates.add(cur);
          cur = cur.add(const Duration(days: 1));
        }
      });
      await _fetchDeliveries();
    }
  }

  void _showDeliveryDetails(BuildContext context, Map<String, dynamic> delivery) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.white,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('#${delivery['id_pedido']} - Detalhes', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: dark)),
            IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailItem('Data/Hora', DateFormat('dd/MM - HH:mm').format(DateTime.parse(delivery['timestamp']))),
              _buildDetailItem('Endereço', '${delivery['rua'] ?? 'N/A'}, ${delivery['numero'] ?? 'S/N'}\n${delivery['bairro'] ?? 'N/A'}\n${delivery['cidade'] ?? 'N/A'} - ${delivery['estado'] ?? ''}'),
              if (delivery['cep'] != null && delivery['cep'].toString().trim().isNotEmpty) _buildDetailItem('CEP', delivery['cep']),
              _buildDetailItem('Contato', delivery['telefone'] ?? 'N/A'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => _showMapOptions(context, delivery), style: TextButton.styleFrom(foregroundColor: info), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.location_on), SizedBox(width: 4), Text('Mapa')])),
          if (delivery['telefone'] != null && delivery['telefone'] != 'N/A' && delivery['telefone'].toString().trim().isNotEmpty)
            TextButton(
              onPressed: () async {
                final phone = delivery['telefone'].toString().replaceAll(RegExp(r'\D'), '');
                final formatted = phone.startsWith('55') ? phone : '55$phone';
                final uri = Uri.parse('tel:+$formatted');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível discar')));
                }
              },
              style: TextButton.styleFrom(foregroundColor: success),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.phone), SizedBox(width: 4), Text('Ligar')]),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String title, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 14, color: dark)),
        ]),
      );

  void _showMapOptions(BuildContext context, Map<String, dynamic> delivery) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.white,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Abrir no Mapa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: dark)),
            IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMapOption(context, delivery, 'Google Maps', Icons.map, Colors.blue, () => _openGoogleMaps(delivery)),
            const SizedBox(height: 8),
            _buildMapOption(context, delivery, 'Waze', Icons.directions, Colors.blue, () => _openWaze(delivery)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
                foregroundColor: Colors.grey[700],
                backgroundColor: Colors.white,
                side: const BorderSide(color: Colors.grey),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openGoogleMaps(Map<String, dynamic> d) async {
    final addr = _buildAddressString(d);
    if (addr.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Endereço incompleto')));
      return;
    }
    final enc = Uri.encodeComponent(addr);
    final nav = Uri.parse('google.navigation:q=$enc');
    final fallback = Uri.parse('https://www.google.com/maps/search/?api=1&query=$enc');
    try {
      await launchUrl(nav, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _openWaze(Map<String, dynamic> d) async {
    final addr = _buildAddressString(d);
    if (addr.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Endereço incompleto')));
      return;
    }
    final enc = Uri.encodeComponent(addr);
    final waze = Uri.parse('waze://?q=$enc&navigate=yes');
    final fallback = Uri.parse('https://www.waze.com/ul?q=$enc');
    try {
      await launchUrl(waze, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
    if (mounted) Navigator.pop(context);
  }

  String _buildAddressString(Map<String, dynamic> d) {
    final rua = d['rua'] ?? '';
    final num = (d['numero']?.toString().trim().isNotEmpty == true) ? d['numero'] : '';
    final bairro = d['bairro'] ?? '';
    final cidade = d['cidade'] ?? '';
    final estado = d['estado'] ?? '';
    final cep = d['cep'] ?? '';
    if (rua.isEmpty && num.isEmpty && bairro.isEmpty) return '';
    return '$rua $num, $bairro, $cidade - $estado, $cep, Brasil';
  }

  Widget _buildMapOption(BuildContext ctx, Map<String, dynamic> delivery, String title, IconData icon, Color iconColor, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey[200]!), borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.blue[100], borderRadius: BorderRadius.circular(20)), child: Icon(icon, color: iconColor)),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w500, color: dark)),
                Text('Abrir no aplicativo', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ]),
            ],
          ),
        ),
      );

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: light,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_left, color: primary, size: 24),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen())),
          tooltip: 'Voltar ao Dashboard',
        ),
        title: const Text('Painel de Entregas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: dark)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey))),
            child: TabBar(
              controller: _tabController,
              labelColor: primary,
              unselectedLabelColor: Colors.grey[600],
              indicator: const UnderlineTabIndicator(borderSide: BorderSide(color: primary, width: 3), insets: EdgeInsets.symmetric(horizontal: 16)),
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              tabs: const [Tab(text: 'Pedidos do Dia'), Tab(text: 'Pedidos Concluídos')],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      CircularProgressIndicator(strokeWidth: 4, valueColor: AlwaysStoppedAnimation(primary)),
                      SizedBox(height: 16),
                      Text('Carregando entregas...', style: TextStyle(fontSize: 16, color: Colors.grey)),
                    ],
                  ),
                )
              : _errorMessage != null
                  ? Center(
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))]),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error, color: Colors.red, size: 48),
                            const SizedBox(height: 16),
                            const Text('Ocorreu um erro', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: dark)),
                            const SizedBox(height: 8),
                            Text(_errorMessage!, style: const TextStyle(fontSize: 16, color: Colors.grey), textAlign: TextAlign.center),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () {
                                _initializePrefs().then((_) {
                                  if (mounted) _fetchDeliveries();
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                              child: const Text('Tentar Novamente'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))]),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Olá, ${_prefs.getString('entregador') ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: dark), overflow: TextOverflow.ellipsis),
                                          Text(
                                              _tabController.index == 0
                                                  ? 'Todas as Entregas Pendentes'
                                                  : 'Datas: ${_selectedDates.map((d) => DateFormat('dd/MM').format(d)).join(', ')}',
                                              style: const TextStyle(fontSize: 14, color: Colors.grey),
                                              overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (_tabController.index == 1)
                                          ElevatedButton(
                                            onPressed: () => _selectDate(context),
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.grey[100],
                                                foregroundColor: Colors.grey[700],
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                                elevation: 0),
                                            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.calendar_today, size: 14), SizedBox(width: 6), Text('Filtrar', style: TextStyle(fontSize: 12))]),
                                          ),
                                        ElevatedButton(
                                          onPressed: () {
                                            _initializePrefs().then((_) {
                                              if (mounted) _fetchDeliveries();
                                            });
                                          },
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.grey[100],
                                              foregroundColor: Colors.grey[700],
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                              elevation: 0),
                                          child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.refresh, size: 14), SizedBox(width: 6), Text('Atualizar', style: TextStyle(fontSize: 12))]),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Flexible(
                                      flex: 1,
                                      child: Container(
                                        constraints: const BoxConstraints(minWidth: 140, maxWidth: 200),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                                        child: Row(
                                          children: [
                                            Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(color: Colors.blue[100], borderRadius: BorderRadius.circular(20)),
                                                child: const Icon(Icons.local_shipping, color: Colors.blue, size: 20)),
                                            const SizedBox(width: 12),
                                            Expanded(
                                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              const Text('Total de Pedidos', style: TextStyle(fontSize: 12, color: Colors.grey), overflow: TextOverflow.ellipsis),
                                              Text('${_tabController.index == 0 ? _pendingDeliveries.length : _completedDeliveries.length}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: dark), overflow: TextOverflow.ellipsis)
                                            ])),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      flex: 1,
                                      child: Container(
                                        constraints: const BoxConstraints(minWidth: 140, maxWidth: 200),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
                                        child: Row(
                                          children: [
                                            Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(color: Colors.green[100], borderRadius: BorderRadius.circular(20)),
                                                child: const Icon(Icons.attach_money, color: Colors.green, size: 20)),
                                            const SizedBox(width: 12),
                                            Expanded(
                                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              const Text('Total a Receber', style: TextStyle(fontSize: 12, color: Colors.grey), overflow: TextOverflow.ellipsis),
                                              Text(
                                                  'R\$ ${NumberFormat.currency(locale: 'pt_BR', symbol: '', decimalDigits: 2).format(_tabController.index == 0 ? _pendingDeliveries.fold(0.0, (s, i) => s + i['taxa_entrega']) : _completedDeliveries.fold(0.0, (s, i) => s + i['taxa_entrega']))}',
                                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: dark),
                                                  overflow: TextOverflow.ellipsis)
                                            ])),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                _pendingDeliveries.isEmpty
                                    ? _buildEmptyState('Nenhuma entrega pendente', 'Você não tem entregas pendentes no momento.')
                                    : ListView.builder(
                                        itemCount: _pendingDeliveries.length,
                                        itemBuilder: (_, i) => _buildDeliveryCard(context, _pendingDeliveries[i], false, i),
                                      ),
                                _completedDeliveries.isEmpty
                                    ? _buildEmptyState('Nenhuma entrega concluída', 'Nenhuma entrega encontrada para as datas selecionadas.')
                                    : ListView.builder(
                                        itemCount: _completedDeliveries.length,
                                        itemBuilder: (_, i) => _buildDeliveryCard(context, _completedDeliveries[i], true, i),
                                      ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

          // BOTÃO QR CODE - FORA DO CHILDREN
          DraggableFloatingButton(
            initialOffset: Offset(size.width - 80, size.height - 140 - kBottomNavigationBarHeight),
            onPressed: () async {
              if (!(Platform.isAndroid || Platform.isIOS)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Escaneamento de QR Code não está disponível nesta plataforma.')),
                );
                return;
              }

              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScannerScreen()),
              );

              if (result == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Pedido escaneado com sucesso!'),
                    duration: Duration(seconds: 2),
                    backgroundColor: Colors.green,
                  ),
                );
                _fetchDeliveries();
              } else if (result == 'duplicate') {
                _fetchDeliveries();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) => Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))]),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 96, height: 96, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(48)), child: const Icon(Icons.local_shipping, color: Colors.grey, size: 48)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: dark)),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(fontSize: 16, color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      );

  Widget _buildDeliveryCard(BuildContext ctx, Map<String, dynamic> d, bool completed, int idx) {
    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 300),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () => _showDeliveryDetails(ctx, d),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E),
              border: Border.all(color: Colors.black54),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: completed ? success.withAlpha(230) : primary.withAlpha(230), borderRadius: BorderRadius.circular(6)),
                              child: Text('ID DO PEDIDO #${d['id_pedido']}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(height: 8),
                            Text('TAXA: R\$ ${NumberFormat.currency(locale: 'pt_BR', symbol: '', decimalDigits: 2).format(d['taxa_entrega'])}', style: const TextStyle(fontSize: 14, color: Colors.white70), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text('BAIRRO: ${d['bairro'] ?? 'N/A'}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(color: Color(0xFF2C2C2E), borderRadius: BorderRadius.vertical(bottom: Radius.circular(12))),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (!completed) ...[
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.white),
                          onPressed: () => showDialog(
                            context: ctx,
                            builder: (_) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              backgroundColor: Colors.white,
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  SizedBox(width: 52, height: 52, child: Icon(Icons.check, color: success, size: 26)),
                                  SizedBox(height: 16),
                                  Text('Confirmar Conclusão', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: dark)),
                                  SizedBox(height: 8),
                                  Text('Deseja marcar esta entrega como concluída?', style: TextStyle(fontSize: 14, color: Colors.black54), textAlign: TextAlign.center)
                                ],
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), style: TextButton.styleFrom(foregroundColor: Colors.black87, backgroundColor: Colors.white, side: const BorderSide(color: Colors.black26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text('Cancelar')),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _markAsCompleted(d['id_pedido'], d['timestamp'], d['telefone']);
                                  },
                                  style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: success, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                  child: const Text('Confirmar'),
                                ),
                              ],
                            ),
                          ),
                          color: success,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                          style: IconButton.styleFrom(backgroundColor: success.withAlpha(230)),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.white),
                          onPressed: () => showDialog(
                            context: ctx,
                            builder: (_) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              backgroundColor: Colors.white,
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  SizedBox(width: 52, height: 52, child: Icon(Icons.delete, color: danger, size: 26)),
                                  SizedBox(height: 16),
                                  Text('Confirmar Exclusão', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: dark)),
                                  SizedBox(height: 8),
                                  Text('Tem certeza que deseja excluir esta entrega?', style: TextStyle(fontSize: 14, color: Colors.black54), textAlign: TextAlign.center)
                                ],
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), style: TextButton.styleFrom(foregroundColor: Colors.black87, backgroundColor: Colors.white, side: const BorderSide(color: Colors.black26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text('Cancelar')),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _deleteDelivery(d['id_pedido'], d['timestamp'], completed);
                                  },
                                  style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: danger, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                  child: const Text('Excluir'),
                                ),
                              ],
                            ),
                          ),
                          color: danger,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                          style: IconButton.styleFrom(backgroundColor: danger.withAlpha(230)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DraggableFloatingButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Offset initialOffset;

  const DraggableFloatingButton({super.key, required this.onPressed, this.initialOffset = const Offset(20, 20)});

  @override
  State<DraggableFloatingButton> createState() => _DraggableFloatingButtonState();
}

class _DraggableFloatingButtonState extends State<DraggableFloatingButton> {
  late Offset _offset;

  @override
  void initState() {
    super.initState();
    _offset = widget.initialOffset;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _offset = Offset(_offset.dx + details.delta.dx, _offset.dy + details.delta.dy);
            final size = MediaQuery.of(context).size;
            _offset = Offset(_offset.dx.clamp(0, size.width - 60), _offset.dy.clamp(0, size.height - 60 - kBottomNavigationBarHeight));
          });
        },
        child: FloatingActionButton(
          onPressed: widget.onPressed,
          backgroundColor: _DeliveriesScreenState.primary,
          elevation: 6,
          child: const Icon(Icons.qr_code, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}