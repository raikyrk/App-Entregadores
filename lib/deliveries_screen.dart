import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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
  const DeliveriesScreen({super.key, this.initialTabIndex = 0});

  @override
  State<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends State<DeliveriesScreen> with SingleTickerProviderStateMixin {
  List<DateTime> _selectedDates = [DateTime.now()];
  List<Map<String, dynamic>> _pendingDeliveries = [];
  List<Map<String, dynamic>> _completedDeliveries = [];
  bool _isLoading = true;
  late SharedPreferences prefs;
  String? _errorMessage;
  late TabController _tabController;
  final ImagePicker _picker = ImagePicker();
  Timer? _notificationTimer;

  // Tailwind-inspired colors
  static const Color primary = Color(0xFFF28C38);
  static const Color success = Color(0xFF48BB78);
  static const Color danger = Color(0xFFE53E3E);
  static const Color info = Color(0xFF4299E1);
  static const Color light = Color(0xFFF7FAFC);
  static const Color dark = Color(0xFF1A202C);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _initializePrefs();
    // Inicia o timer para verificar pedidos pendentes a cada 10 minutos
    _startNotificationTimer();
  }

  void _startNotificationTimer() {
    _notificationTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      if (_tabController.index == 0 && mounted) {
        _checkPendingDeliveries();
      }
    });
  }

  Future<void> _checkPendingDeliveries() async {
    final now = DateTime.now();
    for (var delivery in _pendingDeliveries) {
      final timestamp = DateTime.tryParse(delivery['timestamp'] ?? '');
      if (timestamp != null && now.difference(timestamp).inHours >= 1) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: Colors.white,
            title: const Text(
              'Lembrete de Conclusão',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: dark),
            ),
            content: Text(
              'O pedido #${delivery['id_pedido']} está pendente há mais de 1 hora. Deseja marcá-lo como concluído?',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Colors.grey),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Concluir'),
              ),
            ],
          ),
        );
        // Para evitar múltiplos diálogos, interrompe após o primeiro
        break;
      }
    }
  }

  Future<void> _initializePrefs() async {
    try {
      prefs = await SharedPreferences.getInstance();
      _fetchDeliveries();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro ao inicializar dados: $e';
        _isLoading = false;
      });
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
      final entregador = prefs.getString('entregador') ?? '';
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final deliveriesEndpoint = dotenv.env['DELIVERIES_ENDPOINT'] ?? '';
      final completedDeliveriesEndpoint = dotenv.env['COMPLETED_DELIVERIES_ENDPOINT'] ?? '';
      if (baseUrl.isEmpty || deliveriesEndpoint.isEmpty || completedDeliveriesEndpoint.isEmpty) {
        throw Exception('Erro: Variáveis de ambiente API_BASE_URL, DELIVERIES_ENDPOINT ou COMPLETED_DELIVERIES_ENDPOINT não definidas');
      }
      final pendingResponse = await http.get(
        Uri.parse('$baseUrl$deliveriesEndpoint&entregador=${Uri.encodeComponent(entregador)}'),
      ).timeout(const Duration(seconds: 10));
      if (pendingResponse.statusCode != 200) {
        throw Exception('Erro ao buscar entregas pendentes: Status ${pendingResponse.statusCode}');
      }
      final pendingData = jsonDecode(pendingResponse.body);
      if (pendingData['status'] == 'success') {
        final deliveries = List<Map<String, dynamic>>.from(pendingData['deliveries']);
        for (var delivery in deliveries) {
          delivery['is_completed'] = false;
          delivery['taxa_entrega'] = double.parse(delivery['taxa_entrega'].toString());
          _pendingDeliveries.add(delivery);
        }
      } else {
        throw Exception('Erro ao buscar entregas pendentes: ${pendingData['message']}');
      }
      for (var date in _selectedDates) {
        final formattedDate = DateFormat('yyyy-MM-dd').format(date);
        final completedResponse = await http.get(
          Uri.parse('$baseUrl$completedDeliveriesEndpoint&entregador=${Uri.encodeComponent(entregador)}&date=$formattedDate'),
        ).timeout(const Duration(seconds: 10));
        if (completedResponse.statusCode != 200) {
          throw Exception('Erro ao buscar entregas concluídas: Status ${completedResponse.statusCode}');
        }
        final completedData = jsonDecode(completedResponse.body);
        if (completedData['status'] == 'success') {
          final deliveries = List<Map<String, dynamic>>.from(completedData['deliveries']);
          for (var delivery in deliveries) {
            delivery['is_completed'] = true;
            delivery['taxa_entrega'] = double.parse(delivery['taxa_entrega'].toString());
            _completedDeliveries.add(delivery);
          }
        } else {
          throw Exception('Erro ao buscar entregas concluídas: ${completedData['message']}');
        }
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
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
      developer.log("Número de telefone inválido ou não fornecido");
      return;
    }

    const mensagem = "Parece que o seu pedido foi concluído com sucesso! \n\nEspero que goste de nossos produtos 🧡";

    final phone = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) {
      developer.log("Número de telefone inválido após formatação");
      return;
    }

    final messageApiUrl = dotenv.env['MESSAGE_API_URL'] ?? '';
    final messageApiKey = dotenv.env['MESSAGE_API_KEY'] ?? '';
    if (messageApiUrl.isEmpty || messageApiKey.isEmpty) {
      developer.log("Erro: Variáveis de ambiente MESSAGE_API_URL ou MESSAGE_API_KEY não definidas");
      return;
    }

    final payload = {
      "number": phone,
      "text": mensagem,
    };

    final headers = {
      "Content-Type": "application/json",
      "apikey": messageApiKey,
    };

    try {
      final response = await http.post(
        Uri.parse(messageApiUrl),
        headers: headers,
        body: jsonEncode(payload),
      );
      developer.log("Mensagem 'Concluído' enviada: ${response.body}");
    } catch (error) {
      developer.log("Erro ao enviar mensagem 'Concluído': $error");
    }
  }

  Future<void> _markAsCompleted(String id, String timestamp, String? telefone) async {
    final entregador = prefs.getString('entregador') ?? '';
    setState(() {
      _isLoading = true;
    });
    try {
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final markCompletedEndpoint = dotenv.env['MARK_COMPLETED_ENDPOINT'] ?? '';
      if (baseUrl.isEmpty || markCompletedEndpoint.isEmpty) {
        throw Exception('Erro: Variáveis de ambiente API_BASE_URL ou MARK_COMPLETED_ENDPOINT não definidas');
      }
      final response = await http.post(
        Uri.parse('$baseUrl$markCompletedEndpoint'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'id_pedido': id,
          'nome_entregador': entregador,
          'timestamp': timestamp,
          'timestamp_concluido': DateTime.now().toIso8601String(),
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('Erro ao marcar entrega como concluída: Status ${response.statusCode}');
      }
      final data = jsonDecode(response.body);
      if (data['status'] != 'success') {
        throw Exception('Erro ao marcar entrega como concluída: ${data['message']}');
      }
      await enviarMensagemConcluido(telefone);
      await _fetchDeliveries();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrega marcada como concluída!')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao marcar entrega como concluída: $e')),
      );
    }
  }

  Future<void> _deleteDelivery(String id, String timestamp, bool isCompleted) async {
    final entregador = prefs.getString('entregador') ?? '';
    final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (timestamp.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro: Timestamp do pedido não fornecido.')),
      );
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final deleteDeliveryEndpoint = dotenv.env['DELETE_DELIVERY_ENDPOINT'] ?? '';
      final deleteCompletedDeliveryEndpoint = dotenv.env['DELETE_COMPLETED_DELIVERY_ENDPOINT'] ?? '';
      final planilhaExcluirEndpoint = dotenv.env['PLANILHA_EXCLUIR_ENDPOINT'] ?? '';
      if (baseUrl.isEmpty || deleteDeliveryEndpoint.isEmpty || deleteCompletedDeliveryEndpoint.isEmpty || planilhaExcluirEndpoint.isEmpty) {
        throw Exception('Erro: Variáveis de ambiente API_BASE_URL, DELETE_DELIVERY_ENDPOINT, DELETE_COMPLETED_DELIVERY_ENDPOINT ou PLANILHA_EXCLUIR_ENDPOINT não definidas');
      }
      String apiUrl = isCompleted ? '$baseUrl$deleteCompletedDeliveryEndpoint' : '$baseUrl$deleteDeliveryEndpoint';
      if (!isCompleted) {
        final planilhaUrl = '$baseUrl$planilhaExcluirEndpoint?excluir=1&id=$id&data=$formattedDate&timestamp=${Uri.encodeComponent(timestamp)}&entregador=${Uri.encodeComponent(entregador)}';
        final planilhaResponse = await http.get(
          Uri.parse(planilhaUrl),
        ).timeout(const Duration(seconds: 10));
        if (planilhaResponse.statusCode != 200) {
          throw Exception('Erro ao excluir entrega da planilha: Status ${planilhaResponse.statusCode}');
        }
      }
      final dbResponse = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'id_pedido': id,
          'nome_entregador': entregador,
          'timestamp': timestamp,
        },
      ).timeout(const Duration(seconds: 10));
      if (dbResponse.statusCode != 200) {
        throw Exception('Falha ao excluir do banco de dados: Status ${dbResponse.statusCode}');
      }
      final dbData = jsonDecode(dbResponse.body);
      if (dbData['status'] != 'success') {
        throw Exception('Erro ao excluir: ${dbData['message']}');
      }
      await _fetchDeliveries();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrega excluída com sucesso!')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao excluir entrega: $e')),
      );
    }
  }

  Future<void> _uploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma imagem selecionada.')),
        );
        return;
      }
      final entregador = prefs.getString('entregador') ?? '';
      if (entregador.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro: Nome do entregador não encontrado.')),
        );
        return;
      }
      setState(() {
        _isLoading = true;
      });
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final reportsUploadEndpoint = dotenv.env['REPORTS_UPLOAD_ENDPOINT'] ?? '';
      if (baseUrl.isEmpty || reportsUploadEndpoint.isEmpty) {
        throw Exception('Erro: Variáveis de ambiente API_BASE_URL ou REPORTS_UPLOAD_ENDPOINT não definidas');
      }
      final uri = Uri.parse('$baseUrl$reportsUploadEndpoint');
      final request = http.MultipartRequest('POST', uri);
      request.fields['nome_entregador'] = entregador;
      final fileStream = http.ByteStream(image.openRead());
      final length = await File(image.path).length();
      final multipartFile = http.MultipartFile(
        'imagem',
        fileStream,
        length,
        filename: image.name,
        contentType: MediaType('image', image.name.split('.').last),
      );
      request.files.add(multipartFile);
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        if (data['status'] == 'success') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'])),
          );
        } else {
          throw Exception(data['message']);
        }
      } else {
        throw Exception('Erro ao enviar imagem: Status ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar imagem: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDates.isNotEmpty
          ? DateTimeRange(
              start: _selectedDates.first,
              end: _selectedDates.last,
            )
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 7)),
              end: DateTime.now(),
            ),
      firstDate: DateTime(2020),
      lastDate: DateTime(2028, 12, 31),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: primary,
              ),
            ),
            dialogTheme: const DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 400,
                maxHeight: 600,
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDates = [];
        DateTime current = picked.start;
        while (!current.isAfter(picked.end)) {
          _selectedDates.add(current);
          current = current.add(const Duration(days: 1));
        }
      });
      _fetchDeliveries();
    }
  }

  void _showDeliveryDetails(BuildContext context, Map<String, dynamic> delivery) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.white,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '#${delivery['id_pedido']} - Detalhes',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: dark),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailItem(
                'Data/Hora',
                DateFormat('dd/MM - HH:mm').format(DateTime.parse(delivery['timestamp'])),
              ),
              _buildDetailItem(
                'Endereço',
                '${delivery['rua'] ?? 'N/A'}, ${delivery['numero'] ?? 'S/N'}\n'
                    '${delivery['bairro'] ?? 'N/A'}\n'
                    '${delivery['cidade'] ?? 'N/A'} - ${delivery['estado'] ?? ''}',
              ),
              if (delivery['cep'] != null && delivery['cep'].toString().trim().isNotEmpty)
                _buildDetailItem('CEP', delivery['cep']),
              _buildDetailItem('Contato', delivery['telefone'] ?? 'N/A'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _showMapOptions(context, delivery),
            style: TextButton.styleFrom(foregroundColor: info),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on),
                SizedBox(width: 4),
                Text('Mapa'),
              ],
            ),
          ),
          if (delivery['telefone'] != null &&
              delivery['telefone'] != 'N/A' &&
              delivery['telefone'].trim().isNotEmpty)
            TextButton(
              onPressed: () async {
                if (!mounted) return;
                final phone = delivery['telefone'].replaceAll(RegExp(r'\D'), '');
                final formattedPhone = phone.startsWith('55') ? phone : '55$phone';
                final Uri phoneUri = Uri.parse('tel:+$formattedPhone');
                if (await canLaunchUrl(phoneUri)) {
                  await launchUrl(phoneUri);
                } else {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Não foi possível abrir o discador.')),
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: success),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone),
                  SizedBox(width: 4),
                  Text('Ligar'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14, color: dark),
          ),
        ],
      ),
    );
  }

  void _showMapOptions(BuildContext context, Map<String, dynamic> delivery) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.white,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Abrir no Mapa',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: dark),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMapOption(
              context,
              delivery,
              'Google Maps',
              Icons.map,
              Colors.blue,
              () async {
                if (!mounted) return;
                final rua = delivery['rua'] ?? '';
                final numero = (delivery['numero'] != null && delivery['numero'].toString().trim().isNotEmpty)
                    ? delivery['numero']
                    : '';
                final bairro = delivery['bairro'] ?? '';
                final cidade = delivery['cidade'] ?? '';
                final estado = delivery['estado'] ?? '';
                final cep = delivery['cep'] ?? '';

                if (rua.isEmpty && numero.isEmpty && bairro.isEmpty) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Endereço incompleto para abrir no mapa.')),
                  );
                  Navigator.pop(context);
                  return;
                }

                final enderecoCompleto = Uri.encodeComponent(
                  '$rua ${numero.toString().trim()}, $bairro, $cidade - $estado, $cep, Brasil',
                );

                final googleMapsUri = Uri.parse('google.navigation:q=$enderecoCompleto');
                final fallbackUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$enderecoCompleto');

                try {
                  if (await canLaunchUrl(googleMapsUri)) {
                    await launchUrl(googleMapsUri, mode: LaunchMode.externalApplication);
                  } else {
                    await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Não foi possível abrir o Google Maps.')),
                  );
                }
                if (!mounted) return;
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
            _buildMapOption(
              context,
              delivery,
              'Waze',
              Icons.directions,
              Colors.blue,
              () async {
                if (!mounted) return;
                final rua = delivery['rua'] ?? '';
                final numero = (delivery['numero'] != null && delivery['numero'].toString().trim().isNotEmpty)
                    ? delivery['numero']
                    : '';
                final bairro = delivery['bairro'] ?? '';
                final cidade = delivery['cidade'] ?? '';
                final estado = delivery['estado'] ?? '';
                final cep = delivery['cep'] ?? '';

                if (rua.isEmpty && numero.isEmpty && bairro.isEmpty) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Endereço incompleto para abrir no mapa.')),
                  );
                  Navigator.pop(context);
                  return;
                }

                final enderecoCompleto = Uri.encodeComponent(
                  '$rua ${numero.toString().trim()}, $bairro, $cidade - $estado, $cep, Brasil',
                );

                final wazeUri = Uri.parse('waze://?q=$enderecoCompleto&navigate=yes');
                final fallbackUri = Uri.parse('https://www.waze.com/ul?q=$enderecoCompleto');

                try {
                  if (await canLaunchUrl(wazeUri)) {
                    await launchUrl(wazeUri, mode: LaunchMode.externalApplication);
                  } else {
                    await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Não foi possível abrir o Waze.')),
                  );
                }
                if (!mounted) return;
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[700],
              backgroundColor: Colors.white,
              side: const BorderSide(color: Colors.grey),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Widget _buildMapOption(
    BuildContext context,
    Map<String, dynamic> delivery,
    String title,
    IconData icon,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[200]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w500, color: dark),
                ),
                Text(
                  'Abrir no aplicativo',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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
    final screenSize = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: light,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_left, color: primary, size: 24),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DashboardScreen()),
            );
          },
          tooltip: 'Voltar ao Dashboard',
        ),
        title: const Text(
          'Painel de Entregas',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: dark),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: primary,
              unselectedLabelColor: Colors.grey[600],
              indicator: const UnderlineTabIndicator(
                borderSide: BorderSide(color: primary, width: 3),
                insets: EdgeInsets.symmetric(horizontal: 16),
              ),
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              tabs: const [
                Tab(text: 'Pedidos do Dia'),
                Tab(text: 'Pedidos Concluídos'),
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
                        width: 64,
                        height: 64,
                        margin: const EdgeInsets.only(bottom: 16),
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          valueColor: const AlwaysStoppedAnimation(primary),
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                      const Text(
                        'Carregando entregas...',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : _errorMessage != null
                  ? Center(
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error, color: Colors.red, size: 48),
                            const SizedBox(height: 16),
                            const Text(
                              'Ocorreu um erro',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: dark),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(fontSize: 16, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _fetchDeliveries,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                              child: const Text('Tentar Novamente'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
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
                                          Text(
                                            'Olá, ${prefs.getString('entregador') ?? ''}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              color: dark,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            _tabController.index == 0
                                                ? 'Todas as Entregas Pendentes'
                                                : 'Datas: ${_selectedDates.map((date) => DateFormat('dd/MM').format(date)).join(', ')}',
                                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                                            overflow: TextOverflow.ellipsis,
                                          ),
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
                                              elevation: 0,
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.calendar_today, size: 14),
                                                SizedBox(width: 6),
                                                Text('Filtrar', style: TextStyle(fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                        ElevatedButton(
                                          onPressed: _fetchDeliveries,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.grey[100],
                                            foregroundColor: Colors.grey[700],
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                            elevation: 0,
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.refresh, size: 14),
                                              SizedBox(width: 6),
                                              Text('Atualizar', style: TextStyle(fontSize: 12)),
                                            ],
                                          ),
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
                                        constraints: const BoxConstraints(
                                          minWidth: 140,
                                          maxWidth: 200,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[50],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: Colors.blue[100],
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: const Icon(Icons.local_shipping, color: Colors.blue, size: 20),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Total de Pedidos',
                                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    '${_tabController.index == 0 ? _pendingDeliveries.length : _completedDeliveries.length}',
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.bold,
                                                      color: dark,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      flex: 1,
                                      child: Container(
                                        constraints: const BoxConstraints(
                                          minWidth: 140,
                                          maxWidth: 200,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.green[50],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: Colors.green[100],
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: const Icon(Icons.attach_money, color: Colors.green, size: 20),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Total a Receber',
                                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    'R\$ ${NumberFormat.currency(locale: 'pt_BR', symbol: '', decimalDigits: 2).format(_tabController.index == 0 ? _pendingDeliveries.fold(0.0, (sum, item) => sum + item['taxa_entrega']) : _completedDeliveries.fold(0.0, (sum, item) => sum + item['taxa_entrega']))}',
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.bold,
                                                      color: dark,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
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
                                        itemBuilder: (context, index) {
                                          final delivery = _pendingDeliveries[index];
                                          return _buildDeliveryCard(context, delivery, false, index);
                                        },
                                      ),
                                _completedDeliveries.isEmpty
                                    ? _buildEmptyState(
                                        'Nenhuma entrega concluída',
                                        'Nenhuma entrega encontrada para as datas selecionadas.',
                                      )
                                    : ListView.builder(
                                        itemCount: _completedDeliveries.length,
                                        itemBuilder: (context, index) {
                                          final delivery = _completedDeliveries[index];
                                          return _buildDeliveryCard(context, delivery, true, index);
                                        },
                                      ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
          DraggableFloatingButton(
            // Posiciona o botão no canto inferior direito inicialmente
            initialOffset: Offset(screenSize.width - 80, screenSize.height - 140 - kBottomNavigationBarHeight),
            onPressed: () {
              if (!(Platform.isAndroid || Platform.isIOS)) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Escaneamento de QR Code não está disponível nesta plataforma.'),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ScannerScreen()),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(48),
            ),
            child: const Icon(Icons.local_shipping, color: Colors.grey, size: 48),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: dark),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryCard(BuildContext context, Map<String, dynamic> delivery, bool isCompleted, int index) {
    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 300),
      child: Transform.translate(
        offset: const Offset(0, 0),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => _showDeliveryDetails(context, delivery),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                border: Border.all(color: Colors.black54),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
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
                                decoration: BoxDecoration(
                                  color: isCompleted ? success.withOpacity(0.9) : primary.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'ID DO PEDIDO #${delivery['id_pedido']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'TAXA: R\$ ${NumberFormat.currency(locale: 'pt_BR', symbol: '', decimalDigits: 2).format(delivery['taxa_entrega'])}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'BAIRRO: ${delivery['bairro'] ?? 'N/A'}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!isCompleted) ...[
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.white),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  backgroundColor: Colors.white,
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: Colors.green[100],
                                          borderRadius: BorderRadius.circular(26),
                                        ),
                                        child: const Icon(Icons.check, color: success, size: 26),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Confirmar Conclusão',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: dark),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Deseja marcar esta entrega como concluída?',
                                        style: TextStyle(fontSize: 14, color: Colors.black54),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.black87,
                                        backgroundColor: Colors.white,
                                        side: const BorderSide(color: Colors.black26),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text('Cancelar'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _markAsCompleted(delivery['id_pedido'], delivery['timestamp'], delivery['telefone']);
                                      },
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        backgroundColor: success,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text('Confirmar'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            color: success,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                            style: IconButton.styleFrom(backgroundColor: success.withOpacity(0.9)),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.white),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  backgroundColor: Colors.white,
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: Colors.red[100],
                                          borderRadius: BorderRadius.circular(26),
                                        ),
                                        child: const Icon(Icons.delete, color: danger, size: 26),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Confirmar Exclusão',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: dark),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Tem certeza que deseja excluir esta entrega?',
                                        style: TextStyle(fontSize: 14, color: Colors.black54),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.black87,
                                        backgroundColor: Colors.white,
                                        side: const BorderSide(color: Colors.black26),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text('Cancelar'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _deleteDelivery(delivery['id_pedido'], delivery['timestamp'], isCompleted);
                                      },
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        backgroundColor: danger,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text('Excluir'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            color: danger,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                            style: IconButton.styleFrom(backgroundColor: danger.withOpacity(0.9)),
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
  _DraggableFloatingButtonState createState() => _DraggableFloatingButtonState();
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
            final screenSize = MediaQuery.of(context).size;
            _offset = Offset(
              _offset.dx.clamp(0, screenSize.width - 60),
              _offset.dy.clamp(0, screenSize.height - 60 - kBottomNavigationBarHeight),
            );
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