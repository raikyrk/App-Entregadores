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
  static const Color cardBg = Color(0xFF2C2C2E);

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
          barrierDismissible: false,
          builder: (_) => _buildModernDialog(
            icon: Icons.access_time_rounded,
            iconColor: primary,
            title: 'Lembrete de Conclusão',
            message: 'O pedido #${delivery['id_pedido']} está pendente há mais de 1 hora. Deseja marcá-lo como concluído?',
            primaryAction: () {
              Navigator.pop(context);
              _markAsCompleted(delivery['id_pedido'], delivery['timestamp'], delivery['telefone']);
            },
            primaryLabel: 'Concluir',
            secondaryAction: () => Navigator.pop(context),
            secondaryLabel: 'Ignorar',
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

    final messageApiUrl = dotenv.env['MESSAGE_API_URL'];
    final messageApiToken = dotenv.env['MESSAGE_API_TOKEN'];

    if (messageApiUrl == null || messageApiUrl.isEmpty ||
        messageApiToken == null || messageApiToken.isEmpty) {
      developer.log('MESSAGE_API_URL ou MESSAGE_API_TOKEN não definidos');
      return;
    }

    final payload = {
      "number": phone,
      "text": mensagem
    };

    final headers = {
      "Accept": "application/json",
      "Content-Type": "application/json",
      "token": messageApiToken,
    };

    try {
      final response = await http.post(
        Uri.parse(messageApiUrl),
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        developer.log('Mensagem concluída enviada: ${response.statusCode}');
        developer.log('Response: ${response.body}');
      }
    } catch (e) {
      developer.log('Erro ao enviar mensagem concluída: $e');
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Entrega concluída com sucesso!'),
            ],
          ),
          backgroundColor: success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Erro ao concluir: $e')),
            ],
          ),
          backgroundColor: danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
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

    if (baseUrl.isEmpty || deletePend.isEmpty || deleteComp.isEmpty) {
      throw Exception('Endpoints de exclusão ausentes');
    }

    // REMOVIDO: chamada à planilha (agora feita no PHP)
    // if (!isCompleted) { ... }

    final apiUrl = isCompleted ? '$baseUrl$deleteComp' : '$baseUrl$deletePend';
    final dbResp = await http.post(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'id_pedido': id,
        'nome_entregador': entregador,
        'timestamp': timestamp,
      },
    ).timeout(const Duration(seconds: 30)); // Aumentar para 30s

    if (dbResp.statusCode != 200) {
      throw Exception('Erro no servidor: ${dbResp.statusCode}');
    }

    final dbData = jsonDecode(dbResp.body);
    if (dbData['status'] != 'success') {
      throw Exception(dbData['message'] ?? 'Erro desconhecido');
    }

    await _fetchDeliveries();
    if (!mounted) return;

    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.white),
            SizedBox(width: 12),
            Text('Entrega excluída com sucesso!'),
          ],
        ),
        backgroundColor: danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  } catch (e) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text('Erro ao excluir: $e')),
          ],
        ),
        backgroundColor: danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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
          colorScheme: const ColorScheme.light(
            primary: primary,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Colors.black87,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: primary),
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
            child: child,
          ),
        ),
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primary.withOpacity(0.2), primary.withOpacity(0.1)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.description_outlined, color: primary, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pedido #${delivery['id_pedido']}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: dark,
                            ),
                          ),
                          Text(
                            DateFormat('dd/MM/yyyy às HH:mm').format(DateTime.parse(delivery['timestamp'])),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Content
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailSection(
                      icon: Icons.location_on_outlined,
                      iconColor: danger,
                      title: 'Endereço de Entrega',
                      content: '${delivery['rua'] ?? 'N/A'}, ${delivery['numero'] ?? 'S/N'}\n${delivery['bairro'] ?? 'N/A'}\n${delivery['cidade'] ?? 'N/A'} - ${delivery['estado'] ?? ''}',
                    ),
                    
                    if (delivery['cep'] != null && delivery['cep'].toString().trim().isNotEmpty)
                      _buildDetailSection(
                        icon: Icons.pin_drop_outlined,
                        iconColor: info,
                        title: 'CEP',
                        content: delivery['cep'],
                      ),
                    
                    _buildDetailSection(
                      icon: Icons.phone_outlined,
                      iconColor: success,
                      title: 'Contato',
                      content: delivery['telefone'] ?? 'N/A',
                    ),

                    const SizedBox(height: 24),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            onPressed: () => _showMapOptions(context, delivery),
                            icon: Icons.map_outlined,
                            label: 'Ver Mapa',
                            color: info,
                          ),
                        ),
                        if (delivery['telefone'] != null && 
                            delivery['telefone'] != 'N/A' && 
                            delivery['telefone'].toString().trim().isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildActionButton(
                              onPressed: () async {
                                final phone = delivery['telefone'].toString().replaceAll(RegExp(r'\D'), '');
                                final formatted = phone.startsWith('55') ? phone : '55$phone';
                                final uri = Uri.parse('tel:+$formatted');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri);
                                } else {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Não foi possível discar')),
                                    );
                                  }
                                }
                              },
                              icon: Icons.phone,
                              label: 'Ligar',
                              color: success,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 15,
                    color: dark,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        elevation: 0,
      ),
    );
  }

  void _showMapOptions(BuildContext context, Map<String, dynamic> delivery) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Escolha o aplicativo',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: dark,
              ),
            ),
            const SizedBox(height: 24),
            _buildMapOptionCard(
              context,
              delivery,
              'Google Maps',
              Icons.map,
              const Color(0xFF4285F4),
              () => _openGoogleMaps(delivery),
            ),
            const SizedBox(height: 12),
            _buildMapOptionCard(
              context,
              delivery,
              'Waze',
              Icons.navigation,
              const Color(0xFF33CCFF),
              () => _openWaze(delivery),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildMapOptionCard(
    BuildContext ctx,
    Map<String, dynamic> delivery,
    String title,
    IconData icon,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[200]!),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: dark,
                    ),
                  ),
                  Text(
                    'Abrir navegação',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Future<void> _openGoogleMaps(Map<String, dynamic> d) async {
    final addr = _buildAddressString(d);
    if (addr.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Endereço incompleto')),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Endereço incompleto')),
        );
      }
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

  Widget _buildModernDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required VoidCallback primaryAction,
    required String primaryLabel,
    VoidCallback? secondaryAction,
    String? secondaryLabel,
  }) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: dark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[600],
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                if (secondaryAction != null && secondaryLabel != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: secondaryAction,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        side: BorderSide(color: Colors.grey[300]!),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(secondaryLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: primaryAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: iconColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(primaryLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back, color: primary, size: 20),
          ),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
          ),
          tooltip: 'Voltar ao Dashboard',
        ),
        title: const Text(
          'Entregas',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: dark,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey[600],
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [primary, Color(0xFFFF9A56)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(4),
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              tabs: const [
                Tab(text: 'Pendentes'),
                Tab(text: 'Concluídos'),
              ],
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
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: primary.withOpacity(0.2),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation(primary),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Carregando entregas...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              : _errorMessage != null
                  ? Center(
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: danger.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.error_outline,
                                color: danger,
                                size: 48,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Ops! Algo deu errado',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: dark,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _errorMessage!,
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey[600],
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 28),
                            ElevatedButton.icon(
                              onPressed: () {
                                _initializePrefs().then((_) {
                                  if (mounted) _fetchDeliveries();
                                });
                              },
                              icon: const Icon(Icons.refresh, size: 20),
                              label: const Text('Tentar Novamente'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header Card
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white,
                                  Colors.grey[50]!,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 15,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Olá, ${_prefs.getString('entregador') ?? ''}',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: dark,
                                              letterSpacing: -0.5,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _tabController.index == 0
                                                ? 'Entregas do dia'
                                                : 'Histórico: ${_selectedDates.map((d) => DateFormat('dd/MM').format(d)).join(', ')}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[600],
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        if (_tabController.index == 1)
                                          _buildIconButton(
                                            icon: Icons.calendar_today_rounded,
                                            onPressed: () => _selectDate(context),
                                            tooltip: 'Filtrar datas',
                                          ),
                                        const SizedBox(width: 8),
                                        _buildIconButton(
                                          icon: Icons.refresh_rounded,
                                          onPressed: () {
                                            _initializePrefs().then((_) {
                                              if (mounted) _fetchDeliveries();
                                            });
                                          },
                                          tooltip: 'Atualizar',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildStatCard(
                                        icon: Icons.local_shipping_rounded,
                                        iconColor: info,
                                        title: 'Total',
                                        value: '${_tabController.index == 0 ? _pendingDeliveries.length : _completedDeliveries.length}',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildStatCard(
                                        icon: Icons.payments_rounded,
                                        iconColor: success,
                                        title: 'A Receber',
                                        value: 'R\$ ${NumberFormat.currency(locale: 'pt_BR', symbol: '', decimalDigits: 2).format(_tabController.index == 0 ? _pendingDeliveries.fold(0.0, (s, i) => s + i['taxa_entrega']) : _completedDeliveries.fold(0.0, (s, i) => s + i['taxa_entrega']))}',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Expanded(
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                _pendingDeliveries.isEmpty
                                    ? _buildEmptyState(
                                        icon: Icons.inventory_2_outlined,
                                        title: 'Nenhuma entrega pendente',
                                        subtitle: 'Você está em dia com suas entregas!',
                                      )
                                    : ListView.builder(
                                        physics: const BouncingScrollPhysics(),
                                        itemCount: _pendingDeliveries.length,
                                        itemBuilder: (_, i) => _buildDeliveryCard(
                                          context,
                                          _pendingDeliveries[i],
                                          false,
                                          i,
                                        ),
                                      ),
                                _completedDeliveries.isEmpty
                                    ? _buildEmptyState(
                                        icon: Icons.check_circle_outline,
                                        title: 'Nenhuma entrega concluída',
                                        subtitle: 'Selecione um período para visualizar',
                                      )
                                    : ListView.builder(
                                        physics: const BouncingScrollPhysics(),
                                        itemCount: _completedDeliveries.length,
                                        itemBuilder: (_, i) => _buildDeliveryCard(
                                          context,
                                          _completedDeliveries[i],
                                          true,
                                          i,
                                        ),
                                      ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

          // Floating QR Button
          DraggableFloatingButton(
            initialOffset: Offset(size.width - 80, size.height - 140 - kBottomNavigationBarHeight),
            onPressed: () async {
              if (!(Platform.isAndroid || Platform.isIOS)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Escaneamento não disponível nesta plataforma.'),
                  ),
                );
                return;
              }

              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScannerScreen()),
              );

              if (result == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: const [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 12),
                        Text('Pedido escaneado com sucesso!'),
                      ],
                    ),
                    backgroundColor: success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: Colors.grey[700]),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: iconColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: dark,
              letterSpacing: -0.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.grey[400], size: 56),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[600],
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryCard(
    BuildContext ctx,
    Map<String, dynamic> d,
    bool completed,
    int idx,
  ) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (idx * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () => _showDeliveryDetails(ctx, d),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cardBg,
                  cardBg.withOpacity(0.95),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: completed
                                    ? [success, success.withOpacity(0.8)]
                                    : [primary, Color(0xFFFF9A56)],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: (completed ? success : primary).withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              '#${d['id_pedido']}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (completed)
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: success.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_circle,
                                color: success,
                                size: 18,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d['bairro'] ?? 'N/A',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${d['rua'] ?? 'N/A'}, ${d['numero'] ?? 'S/N'}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.attach_money,
                              color: success,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'R\$ ${NumberFormat.currency(locale: 'pt_BR', symbol: '', decimalDigits: 2).format(d['taxa_entrega'])}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!completed)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildCardActionButton(
                          ctx,
                          icon: Icons.check_rounded,
                          color: success,
                          onPressed: () => showDialog(
                            context: ctx,
                            builder: (_) => _buildModernDialog(
                              icon: Icons.check_circle_outline,
                              iconColor: success,
                              title: 'Confirmar Conclusão',
                              message: 'Deseja marcar esta entrega como concluída?',
                              primaryAction: () {
                                Navigator.pop(ctx);
                                _markAsCompleted(d['id_pedido'], d['timestamp'], d['telefone']);
                              },
                              primaryLabel: 'Confirmar',
                              secondaryAction: () => Navigator.pop(ctx),
                              secondaryLabel: 'Cancelar',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildCardActionButton(
                          ctx,
                          icon: Icons.delete_outline_rounded,
                          color: danger,
                          onPressed: () => showDialog(
                            context: ctx,
                            builder: (_) => _buildModernDialog(
                              icon: Icons.delete_outline,
                              iconColor: danger,
                              title: 'Confirmar Exclusão',
                              message: 'Tem certeza que deseja excluir esta entrega?',
                              primaryAction: () {
                                Navigator.pop(ctx);
                                _deleteDelivery(d['id_pedido'], d['timestamp'], completed);
                              },
                              primaryLabel: 'Excluir',
                              secondaryAction: () => Navigator.pop(ctx),
                              secondaryLabel: 'Cancelar',
                            ),
                          ),
                        ),
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

  Widget _buildCardActionButton(
    BuildContext ctx, {
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class DraggableFloatingButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Offset initialOffset;

  const DraggableFloatingButton({
    super.key,
    required this.onPressed,
    this.initialOffset = const Offset(20, 20),
  });

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
            _offset = Offset(
              _offset.dx + details.delta.dx,
              _offset.dy + details.delta.dy,
            );
            final size = MediaQuery.of(context).size;
            _offset = Offset(
              _offset.dx.clamp(0, size.width - 60),
              _offset.dy.clamp(0, size.height - 60 - kBottomNavigationBarHeight),
            );
          });
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_DeliveriesScreenState.primary, Color(0xFFFF9A56)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _DeliveriesScreenState.primary.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}