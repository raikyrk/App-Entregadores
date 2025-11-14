import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'main.dart'; // AnimatedScaleButton
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _pinController = TextEditingController();
  String? _errorMessage;
  // Hash atual mantido no código conforme solicitado
  static const String currentHash = 'v0';

  @override
  void initState() {
    super.initState();
    // Chama apenas a verificação de atualização ao carregar a tela
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificarAtualizacao();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _writeLog(String message) async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/entregador.log');
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString('$timestamp: $message\n', mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> _uploadLog() async {
    try {
      await _writeLog('Iniciando upload do arquivo de log');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/entregador.log');
      if (!await file.exists()) return;
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final logUploadEndpoint = dotenv.env['LOG_UPLOAD_ENDPOINT'] ?? '';
      if (baseUrl.isEmpty || logUploadEndpoint.isEmpty) {
        await _writeLog('Erro: Variáveis de ambiente API_BASE_URL ou LOG_UPLOAD_ENDPOINT não definidas');
        return;
      }
      final uri = Uri.parse('$baseUrl$logUploadEndpoint');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('log_file', file.path));
      await request.send().timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<void> _login() async {
    setState(() {
      _errorMessage = null;
    });

    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() {
        _errorMessage = 'Por favor, insira o código.';
      });
      return;
    }

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await _writeLog('Tentativa $attempt - Validando PIN');
        final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
        final validatePinEndpoint = dotenv.env['VALIDATE_PIN_ENDPOINT'] ?? '';
        if (baseUrl.isEmpty || validatePinEndpoint.isEmpty) {
          setState(() {
            _errorMessage = 'Erro: Configuração de API ausente.';
          });
          await _writeLog('Erro: Variáveis de ambiente API_BASE_URL ou VALIDATE_PIN_ENDPOINT não definidas');
          return;
        }
        final response = await http.post(
          Uri.parse('$baseUrl$validatePinEndpoint'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'pin': pin},
        ).timeout(const Duration(seconds: 10));

        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['entregador'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('entregador', data['entregador']);
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DashboardScreen()),
          );
          return;
        } else {
          setState(() {
            _errorMessage = data['message'] ?? 'Código inválido.';
          });
          return;
        }
      } catch (e) {
        if (attempt == 3) {
          setState(() {
            _errorMessage = 'Erro de conexão: $e';
          });
        }
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    await _uploadLog();
  }

  Future<void> _verificarAtualizacao() async {
    try {
      await _writeLog('Verificando atualização na API');
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final checkUpdateEndpoint = dotenv.env['CHECK_UPDATE_ENDPOINT'] ?? '';
      final apkDownloadUrl = dotenv.env['APK_DOWNLOAD_URL'] ?? '';
      if (baseUrl.isEmpty || checkUpdateEndpoint.isEmpty || apkDownloadUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro: Configuração de atualização ausente.')),
        );
        await _writeLog('Erro: Variáveis de ambiente API_BASE_URL, CHECK_UPDATE_ENDPOINT ou APK_DOWNLOAD_URL não definidas');
        return;
      }
      final response = await http.get(
        Uri.parse('$baseUrl$checkUpdateEndpoint'),
        headers: {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao verificar atualização')),
        );
        return;
      }

      final data = jsonDecode(response.body);
      if (data['status'] != 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro na API: ${data['message'] ?? 'Resposta inválida'}')),
        );
        return;
      }

      final sha256Checksum = (data['sha256Checksum'] ?? '').toString().toLowerCase();
      final apkUrl = data['urlApk'] ?? '$baseUrl$apkDownloadUrl';
      final ultimaVersao = data['ultimaVersao'] ?? 'desconhecida';

      if (sha256Checksum.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro: Hash da API está vazia')),
        );
        return;
      }

      if (sha256Checksum != currentHash) {
        // Nova versão disponível
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false, // Impede fechar o diálogo
          builder: (_) => WillPopScope(
            onWillPop: () async => false, // Impede o botão "voltar"
            child: AlertDialog(
              title: const Text('Atualização Obrigatória'),
              content: Text('Nova versão ($ultimaVersao) disponível! É necessário atualizar o aplicativo.'),
              actions: [
                TextButton(
                  onPressed: () async {
                    final url = Uri.parse('$apkUrl?ts=${DateTime.now().millisecondsSinceEpoch}');
                    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Não foi possível abrir o link de atualização')),
                      );
                    }
                  },
                  child: const Text('Atualizar'),
                ),
              ],
            ),
          ),
        );
      }
      // Se o hash for igual, não mostra diálogo
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao verificar atualização: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Login - Ao Gosto Carnes',
                style: TextStyle(fontSize: 24, color: Color(0xFFF28C38), fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                style: const TextStyle(color: Colors.black87),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  hintText: 'Digite seu código - 4 dígitos',
                  hintStyle: const TextStyle(color: Colors.grey),
                ),
                obscureText: true,
                textAlign: TextAlign.center,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              const SizedBox(height: 20),
              AnimatedScaleButton(
                onPressed: _login,
                child: const Text('Entrar', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}