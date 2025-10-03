import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io' show File, FileMode;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'main.dart';
import 'login_screen.dart';
import 'scanner_screen.dart';
import 'deliveries_screen.dart';
import 'dart:io';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 0, end: 1).animate(_pulseController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _writeLog(String message) async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/entregador.log');
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString('$timestamp: $message\n', mode: FileMode.append);
    } catch (e, stackTrace) {
      await _writeLog('Erro ao escrever log: $e\nStackTrace: $stackTrace');
    }
  }

  Future<void> _uploadLog() async {
    try {
      await _writeLog('Iniciando upload do arquivo de log');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/entregador.log');
      if (!await file.exists()) {
        await _writeLog('Arquivo de log não existe');
        return;
      }
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final logUploadEndpoint = dotenv.env['LOG_UPLOAD_ENDPOINT'] ?? '';
      if (baseUrl.isEmpty || logUploadEndpoint.isEmpty) {
        await _writeLog('Erro: Variáveis de ambiente API_BASE_URL ou LOG_UPLOAD_ENDPOINT não definidas');
        return;
      }
      final uri = Uri.parse('$baseUrl$logUploadEndpoint');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        await http.MultipartFile.fromPath('log_file', file.path),
      );
      final response = await request.send().timeout(const Duration(seconds: 10));
      await _writeLog('Status do upload do log: ${response.statusCode}');
      if (response.statusCode == 200) {
        await _writeLog('Log enviado com sucesso para o servidor');
      } else {
        await _writeLog('Falha ao enviar log: Status ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      await _writeLog('Erro ao enviar log: $e\nStackTrace: $stackTrace');
    }
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('entregador');
    await _writeLog('Usuário deslogado');
    await _uploadLog();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _refreshDashboard() async {
    await _writeLog('Atualização do painel iniciada');
    if (!mounted) return;
    setState(() {
      // Forçar a reconstrução do widget para recarregar os dados
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Painel atualizado!'),
        duration: Duration(seconds: 2),
      ),
    );
    await _uploadLog();
  }

  Future<String> _getEntregadorName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('entregador') ?? 'Entregador';
    await _writeLog('Nome do entregador obtido: $name');
    return name;
  }

  Future<Map<String, dynamic>> _getDailyDeliveries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entregador = prefs.getString('entregador') ?? '';
      final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await _writeLog('Buscando entregas para entregador: $entregador, data: $formattedDate');
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final deliveriesEndpoint = dotenv.env['DELIVERIES_ENDPOINT'] ?? '';
      final completedDeliveriesEndpoint = dotenv.env['COMPLETED_DELIVERIES_ENDPOINT'] ?? '';
      if (baseUrl.isEmpty || deliveriesEndpoint.isEmpty || completedDeliveriesEndpoint.isEmpty) {
        await _writeLog('Erro: Variáveis de ambiente API_BASE_URL, DELIVERIES_ENDPOINT ou COMPLETED_DELIVERIES_ENDPOINT não definidas');
        return {
          'completed': 0,
          'pending': 0,
          'total': 0,
        };
      }
      final pendingResponse = await http.get(
        Uri.parse('$baseUrl$deliveriesEndpoint&entregador=${Uri.encodeComponent(entregador)}&date=$formattedDate'),
      ).timeout(const Duration(seconds: 10));
      await _writeLog('Status da resposta de entregas pendentes: ${pendingResponse.statusCode}');
      int pendingCount = 0;
      int completedCount = 0;
      if (pendingResponse.statusCode == 200) {
        final pendingData = jsonDecode(pendingResponse.body);
        await _writeLog('Dados de entregas pendentes: $pendingData');
        if (pendingData['status'] == 'success') {
          pendingCount = List<Map<String, dynamic>>.from(pendingData['deliveries']).length;
        }
      }
      final completedResponse = await http.get(
        Uri.parse('$baseUrl$completedDeliveriesEndpoint&entregador=${Uri.encodeComponent(entregador)}&date=$formattedDate'),
      ).timeout(const Duration(seconds: 10));
      await _writeLog('Status da resposta de entregas concluídas: ${completedResponse.statusCode}');
      if (completedResponse.statusCode == 200) {
        final completedData = jsonDecode(completedResponse.body);
        await _writeLog('Dados de entregas concluídas: $completedData');
        if (completedData['status'] == 'success') {
          completedCount = List<Map<String, dynamic>>.from(completedData['deliveries']).length;
        }
      }
      final result = {
        'completed': completedCount,
        'pending': pendingCount,
        'total': pendingCount + completedCount,
      };
      await _writeLog('Resultado das entregas: $result');
      await _uploadLog();
      return result;
    } catch (e, stackTrace) {
      await _writeLog('Erro ao buscar entregas: $e\nStackTrace: $stackTrace');
      await _uploadLog();
      return {
        'completed': 0,
        'pending': 0,
        'total': 0,
      };
    }
  }

  Future<Map<String, String>> _getAverageDeliveryTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entregador = prefs.getString('entregador') ?? '';
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final yesterday = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));
      await _writeLog('Calculando tempo médio para entregador: $entregador, hoje: $today, ontem: $yesterday');
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final completedDeliveriesEndpoint = dotenv.env['COMPLETED_DELIVERIES_ENDPOINT'] ?? '';
      if (baseUrl.isEmpty || completedDeliveriesEndpoint.isEmpty) {
        await _writeLog('Erro: Variáveis de ambiente API_BASE_URL ou COMPLETED_DELIVERIES_ENDPOINT não definidas');
        return {
          'averageTime': '0 min',
          'difference': '0 min',
        };
      }
      Future<double> calculateAverageForDate(String date) async {
        final response = await http.get(
          Uri.parse('$baseUrl$completedDeliveriesEndpoint&entregador=${Uri.encodeComponent(entregador)}&date=$date'),
        ).timeout(const Duration(seconds: 10));
        await _writeLog('Status da resposta de entregas concluídas ($date): ${response.statusCode}');
        if (response.statusCode != 200) {
          await _writeLog('Erro: Status code não é 200 para data $date');
          return 0.0;
        }
        final data = jsonDecode(response.body);
        await _writeLog('Dados de entregas concluídas ($date): $data');
        if (data['status'] != 'success') {
          await _writeLog('Erro: Status da API não é success para data $date');
          return 0.0;
        }
        final deliveries = List<Map<String, dynamic>>.from(data['deliveries']);
        if (deliveries.isEmpty) {
          await _writeLog('Nenhuma entrega encontrada para data $date');
          return 0.0;
        }
        double totalMinutes = 0.0;
        for (var delivery in deliveries) {
          final duration = delivery['duracao_minutos']?.toDouble() ?? 0.0;
          totalMinutes += duration;
        }
        final average = totalMinutes / deliveries.length;
        await _writeLog('Tempo médio calculado para $date: $average minutos');
        return average;
      }
      final todayAverage = await calculateAverageForDate(today);
      final yesterdayAverage = await calculateAverageForDate(yesterday);
      String averageTime;
      if (todayAverage >= 60) {
        final hours = (todayAverage ~/ 60).toInt();
        final minutes = (todayAverage % 60).round();
        averageTime = '${hours}h${minutes}m';
      } else {
        averageTime = '${todayAverage.round()} min';
      }
      String difference;
      final diffMinutes = todayAverage - yesterdayAverage;
      if (diffMinutes.abs() >= 60) {
        final hours = (diffMinutes.abs() ~/ 60).toInt();
        final minutes = (diffMinutes.abs() % 60).round();
        difference = '${diffMinutes >= 0 ? '+' : '-'}${hours}h${minutes}m';
      } else {
        difference = '${diffMinutes >= 0 ? '+' : '-'}${diffMinutes.abs().round()} min';
      }
      if (diffMinutes == 0) {
        difference = '0 min';
      }
      final result = {
        'averageTime': averageTime,
        'difference': difference,
      };
      await _writeLog('Resultado do tempo médio: $result');
      await _uploadLog();
      return result;
    } catch (e, stackTrace) {
      await _writeLog('Erro ao calcular tempo médio: $e\nStackTrace: $stackTrace');
      await _uploadLog();
      return {
        'averageTime': '0 min',
        'difference': '0 min',
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.logout, color: Color(0xFFF28C38), size: 24),
          onPressed: () => _logout(context),
          tooltip: 'Sair',
        ),
        title: const Row(
          children: [
            Icon(Icons.motorcycle, color: Color(0xFFF28C38), size: 24),
            SizedBox(width: 8),
            Text(
              'Ao Gosto - Delivery',
              style: TextStyle(
                color: Color(0xFF374151),
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FutureBuilder<String>(
                            future: _getEntregadorName(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const CircularProgressIndicator(color: Color(0xFFF28C38));
                              }
                              final nomeEntregador = snapshot.data ?? 'Entregador';
                              return Text(
                                'Olá, $nomeEntregador',
                                style: const TextStyle(
                                  fontSize: 24,
                                  color: Color(0xFFF28C38),
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Poppins',
                                ),
                              );
                            },
                          ),
                          const Text(
                            'Bem-vindo ao seu painel de entregas',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF4B5563),
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            await _writeLog('Botão de atualizar painel pressionado');
                            await _refreshDashboard();
                          },
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFF28C38), Color(0xFFF5A623)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.refresh,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'upload_report') {
                              await _writeLog('Botão Enviar Relatórios pressionado');
                              if (!mounted) return;
                              try {
                                final ImagePicker picker = ImagePicker();
                                final XFile? photo = await picker.pickImage(source: ImageSource.camera);
                                if (!mounted) return;
                                if (photo == null) {
                                  await _writeLog('Nenhuma foto capturada');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Nenhuma foto foi capturada.'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                  return;
                                }
                                final prefs = await SharedPreferences.getInstance();
                                final entregador = prefs.getString('entregador') ?? 'Desconhecido';
                                final timestamp = DateTime.now().toIso8601String();
                                final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
                                final photoUploadEndpoint = dotenv.env['PHOTO_UPLOAD_ENDPOINT'] ?? '';
                                if (baseUrl.isEmpty || photoUploadEndpoint.isEmpty) {
                                  await _writeLog('Erro: Variáveis de ambiente API_BASE_URL ou PHOTO_UPLOAD_ENDPOINT não definidas');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Erro de configuração. Contate o suporte.'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                  return;
                                }
                                final uri = Uri.parse('$baseUrl$photoUploadEndpoint');
                                final request = http.MultipartRequest('POST', uri)
                                  ..fields['entregador'] = entregador
                                  ..fields['timestamp'] = timestamp
                                  ..files.add(await http.MultipartFile.fromPath('photo', photo.path));
                                final response = await request.send().timeout(const Duration(seconds: 10));
                                await _writeLog('Status do upload da foto: ${response.statusCode}');
                                if (!mounted) return;
                                if (response.statusCode == 200) {
                                  await _writeLog('Foto enviada com sucesso para o servidor');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Foto enviada com sucesso!'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                } else {
                                  await _writeLog('Falha ao enviar foto: Status ${response.statusCode}');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Falha ao enviar a foto.'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } catch (e, stackTrace) {
                                await _writeLog('Erro ao enviar foto: $e\nStackTrace: $stackTrace');
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Erro ao capturar ou enviar a foto.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                              await _uploadLog();
                            }
                          },
                          itemBuilder: (BuildContext context) => [
                            PopupMenuItem<String>(
                              value: 'upload_report',
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFF28C38), Color(0xFFF5A623)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.upload_file,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Enviar Relatórios',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Poppins',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          offset: const Offset(0, 50),
                          child: Container(
                            width: 64,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE4C4),
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Color(0xFFF28C38),
                              size: 32,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            AnimatedCard(
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF28C38), Color(0xFFF5A623)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF28C38),
                            borderRadius: BorderRadius.circular(40),
                            boxShadow: [
                              BoxShadow(
                                color: const Color.fromRGBO(242, 140, 56, 0.4),
                                blurRadius: 10 * _pulseAnimation.value,
                                spreadRadius: 10 * _pulseAnimation.value,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner,
                            color: Colors.white,
                            size: 32,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'QR Code',
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Escaneia aí, lenda! O corre não para 🛵',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontFamily: 'Poppins',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () async {
                        await _writeLog('Botão Escanear QR Code pressionado');
                        if (!Platform.isAndroid) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Escaneamento de QR Code não está disponível nesta plataforma.'),
                            ),
                          );
                          await _uploadLog();
                        } else {
                          if (!mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ScannerScreen()),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFF28C38),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        minimumSize: const Size(200, 48),
                      ),
                      child: const Text(
                        'Escanear QR Code',
                        style: TextStyle(
                          fontSize: 16,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            AnimatedCard(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Suas Entregas',
                          style: TextStyle(
                            fontSize: 20,
                            color: Color(0xFF374151),
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        Flexible(
                          child: ElevatedButton(
                            onPressed: () async {
                              await _writeLog('Botão Ver Entregas pressionado');
                              if (!mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const DeliveriesScreen()),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF28C38),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text(
                              'Ver Entregas',
                              style: TextStyle(
                                fontSize: 16,
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<Map<String, dynamic>>(
                      future: _getDailyDeliveries(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const CircularProgressIndicator(color: Color(0xFFF28C38));
                        }
                        final data = snapshot.data ?? {'completed': 0, 'pending': 0, 'total': 0};
                        return Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  await _writeLog('Card Entregas Hoje clicado');
                                  if (!mounted) return;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const DeliveriesScreen(initialTabIndex: 0),
                                    ),
                                  );
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFE4C4),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Entregas hoje',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Color(0xFF4B5563),
                                              fontFamily: 'Poppins',
                                            ),
                                          ),
                                          Text(
                                            '${data['total']}',
                                            style: const TextStyle(
                                              fontSize: 24,
                                              color: Color(0xFFF28C38),
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Poppins',
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF5E6),
                                          borderRadius: BorderRadius.circular(24),
                                        ),
                                        child: const Icon(
                                          Icons.inventory_2,
                                          color: Color(0xFFF28C38),
                                          size: 24,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  await _writeLog('Card Entregas Concluídas clicado');
                                  if (!mounted) return;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const DeliveriesScreen(initialTabIndex: 1),
                                    ),
                                  );
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE7F6E9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Concluídas hoje',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Color(0xFF4B5563),
                                              fontFamily: 'Poppins',
                                            ),
                                          ),
                                          Text(
                                            '${data['completed']}',
                                            style: const TextStyle(
                                              fontSize: 24,
                                              color: Color(0xFF16A34A),
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Poppins',
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD1FAE5),
                                          borderRadius: BorderRadius.circular(24),
                                        ),
                                        child: const Icon(
                                          Icons.check_circle,
                                          color: Color(0xFF16A34A),
                                          size: 24,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            AnimatedCard(
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF28C38), Color(0xFFF5A623)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tempo Médio',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Poppins',
                              ),
                            ),
                            Text(
                              'Hoje',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color.fromRGBO(255, 255, 255, 0.7),
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ],
                        ),
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(255, 255, 255, 0.2),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Icon(
                            Icons.timer,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FutureBuilder<Map<String, String>>(
                      future: _getAverageDeliveryTime(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const CircularProgressIndicator(color: Colors.white);
                        }
                        final data = snapshot.data ?? {'averageTime': '0 min', 'difference': '0 min'};
                        final avgTime = data['averageTime']!;
                        final difference = data['difference']!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              avgTime,
                              style: const TextStyle(
                                fontSize: 40,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Poppins',
                              ),
                            ),
                            const Text(
                              'Tempo médio por entrega',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color.fromRGBO(255, 255, 255, 0.7),
                                fontFamily: 'Poppins',
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              decoration: BoxDecoration(
                                border: Border(top: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.2))),
                              ),
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Melhor que ontem',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color.fromRGBO(255, 255, 255, 0.7),
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                  Text(
                                    difference,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: difference.startsWith('-') ? Colors.green : difference == '0 min' ? Colors.white : Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnimatedCard extends StatefulWidget {
  final Widget child;
  const AnimatedCard({super.key, required this.child});
  @override
  AnimatedCardState createState() => AnimatedCardState();
}

class AnimatedCardState extends State<AnimatedCard> {
  bool _isElevated = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isElevated = true),
      onTapUp: (_) => setState(() => _isElevated = false),
      onTapCancel: () => setState(() => _isElevated = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        transform: Matrix4.translationValues(0, _isElevated ? -5 : 0, 0),
        child: Card(
          elevation: _isElevated ? 10 : 4,
          shadowColor: Colors.black.withValues(alpha: 0.1 * 255),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: widget.child,
        ),
      ),
    );
  }
}