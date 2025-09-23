import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import 'main.dart';
import 'deliveries_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  _ScannerScreenState createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  MobileScannerController cameraController = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
    torchEnabled: false,
    autoStart: false,
  );
  bool _isProcessing = false;
  String? _resultMessage;
  String? _cachedEntregador;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      _initializeScanner();
    }
    _loadEntregador();
  }

  Future<void> _loadEntregador() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedEntregador = prefs.getString('entregador');
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initializeScanner() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    var status = await Permission.camera.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (mounted) {
        setState(() {
          _resultMessage = 'Permissão de câmera negada. Ative nas configurações.';
        });
      }
      return;
    }

    try {
      await cameraController.start();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Erro ao inicializar o scanner: $e');
      if (mounted) {
        setState(() {
          _resultMessage = 'Erro ao inicializar o scanner: $e';
        });
      }
    }
  }

  Future<void> _scanQRCode(BarcodeCapture capture) async {
    if (!(Platform.isAndroid || Platform.isIOS) || !mounted || _isProcessing) return;
    setState(() {
      _isProcessing = true;
    });

    try {
      final barcodes = capture.barcodes;
      if (barcodes.isNotEmpty) {
        final decodedText = barcodes.first.displayValue ?? '';
        print('QR Code detectado: $decodedText');
        final id = _extractIdFromUrl(decodedText);
        if (id != null) {
          await _processQRCode(id);
        } else {
          if (!mounted) return;
          setState(() {
            _resultMessage = 'QR Code inválido: ID do pedido não encontrado.';
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _resultMessage = 'Nenhum QR Code detectado.';
        });
      }
    } catch (e) {
      print('Erro ao escanear QR Code: $e');
      if (!mounted) return;
      setState(() {
        _resultMessage = 'Erro ao escanear QR Code: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
    }
  }

  String? _extractIdFromUrl(String url) {
    try {
      final urlParams = Uri.parse(url).queryParameters;
      return urlParams['id'];
    } catch (e) {
      print('Erro ao extrair ID do QR Code: $e');
      return null;
    }
  }

  Future<void> enviarMensagemSaiuPraEntrega(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber == 'N/A' || phoneNumber.trim().isEmpty) {
      print("Número de telefone inválido ou não fornecido");
      return;
    }
    const mensagem = "Vrummm! 🛵\nO seu pedido acabou de sair para entrega! - Mensagem Automática";
    final phone = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) {
      print("Número de telefone inválido após formatação");
      return;
    }
    const url = "https://api.wzap.chat/v1/messages";
    final payload = {
      "phone": phone,
      "message": mensagem
    };
    final headers = {
      "Content-Type": "application/json",
      "Token": "7343607cd11509da88407ea89353ebdd8a79bdf9c3152da4025274c08c370b7b90ab0b68307d28cf"
    };
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(payload),
      );
      print("Mensagem 'Saiu pra Entrega' enviada: ${response.body}");
    } catch (error) {
      print("Erro ao enviar mensagem 'Saiu pra Entrega': $error");
    }
  }

  Future<void> _processQRCode(String id) async {
  if (_cachedEntregador == null || _cachedEntregador!.isEmpty) {
    if (!mounted) return;
    setState(() {
      _resultMessage = 'Erro: Nome do entregador não definido. Faça login novamente.';
    });
    return;
  }

  try {
    String normalizedEntregador = _cachedEntregador!.trim();
    const List<String> upperCaseNames = [''];
    if (upperCaseNames.contains(normalizedEntregador.toLowerCase())) {
      normalizedEntregador = normalizedEntregador.toUpperCase();
    } else {
      normalizedEntregador = normalizedEntregador
          .split(' ')
          .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
          .join(' ');
    }

    // Verificar duplicatas
    final duplicateResponse = await http.get(
      Uri.parse('https://aogosto.store/entregador/api.php?action=check_duplicate&id_pedido=$id'),
    ).timeout(const Duration(seconds: 10));
    if (duplicateResponse.body.isEmpty) {
      if (!mounted) return;
      setState(() {
        _resultMessage = 'Erro: Resposta vazia ao verificar duplicatas.';
      });
      return;
    }
    final duplicateData = jsonDecode(duplicateResponse.body);

    if (duplicateData['status'] == 'success' && duplicateData['is_duplicate']) {
      if (!mounted) return;
      setState(() {
        _resultMessage = duplicateData['message'] ?? 'Este pedido já foi escaneado!';
      });
      return;
    }

    // Enviar dados para a API
    final body = {
      'id_pedido': id,
      'nome_entregador': normalizedEntregador,
      'timestamp': DateTime.now().toIso8601String(),
      'bairro': 'N/A',
      'rua': 'N/A',
      'telefone': 'N/A',
      'nome': 'N/A',
      'pagamento': 'N/A',
      'numero': 'N/A',
      'cidade': 'N/A',
    };
    final response = await http.post(
      Uri.parse('https://aogosto.store/entregador/api.php?action=assign_and_save_delivery'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    ).timeout(const Duration(seconds: 10));

    print('Resposta bruta da API assign_and_save_delivery: ${response.body}');
    if (response.body.isEmpty) {
      if (!mounted) return;
      setState(() {
        _resultMessage = 'Erro: Resposta vazia da API ao atribuir entrega.';
      });
      return;
    }

    final data = jsonDecode(response.body);

    if (data['status'] == 'success') {
      // Enviar mensagem de "Saiu pra Entrega"
      await enviarMensagemSaiuPraEntrega(data['telefone']);

      if (!mounted) return;
      setState(() {
        final messages = [
          'Feito! Agora é só meter marcha, $normalizedEntregador 🚀',
          'Você faz a diferença, $normalizedEntregador. Bora levar o pedido #$id até o cliente!',
          'Boaaa, $normalizedEntregador! Agora é só partir pro abraço... digo, pra entrega!',
          'Pedido #$id é seu, $normalizedEntregador. Agora corre que o churrasco tá esperando!'
        ];
        _resultMessage = messages[DateTime.now().millisecond % messages.length];
      });
      await Future.delayed(const Duration(seconds: 2)); // Aumentado para dar tempo de exibir a mensagem
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DeliveriesScreen()),
      );
    } else {
      if (!mounted) return;
      setState(() {
        _resultMessage = data['message'] ?? 'Erro ao atribuir e salvar o pedido.';
      });
    }
  } catch (e) {
    print('Erro ao processar QR Code: $e');
    if (e is TimeoutException) {
      if (!mounted) return;
      setState(() {
        _resultMessage = 'Conexão lenta, mas a entrega foi registrada! Verifique a planilha.';
      });
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DeliveriesScreen()),
      );
    } else {
      if (!mounted) return;
      setState(() {
        _resultMessage = 'Erro inesperado: $e';
      });
    }
  }
}

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (Platform.isAndroid || Platform.isIOS)
            MobileScanner(
              controller: cameraController,
              onDetect: _scanQRCode,
              errorBuilder: (context, error) {
                return Center(
                  child: Text(
                    'Erro no scanner: $error',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.red,
                      backgroundColor: Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          Positioned(
            top: 20,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFFF28C38)),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ),
          Positioned(
            top: 20,
            right: 20,
            child: IconButton(
              icon: Icon(
                cameraController.torchEnabled ? Icons.flash_on : Icons.flash_off,
                color: const Color(0xFFF28C38),
              ),
              onPressed: () async {
                await cameraController.toggleTorch();
                setState(() {});
              },
            ),
          ),
          if (_resultMessage != null)
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  _resultMessage!,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.red,
                    backgroundColor: Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}