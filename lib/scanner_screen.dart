// lib/scanner_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// =============================================
// 1. FUNÇÃO DE NORMALIZAÇÃO DO ENTREGADOR
// =============================================
String normalizeEntregadorName(String name) {
  if (name.isEmpty) return name;

  // <-- LISTA EXATA dos entregadores aceitos pelo backend
  const allowedNames = [
    'Uber', 'Lala-Move', 'Gabriel', 'Leonardo', 'John Lenon', 'Reginaldo',
    'Jeferson', 'Marcos Geraldo', 'Gilvan', 'Leandro', 'Eduardo', 'Marcelo',
    'Retirada', 'Paulo', 'Diogo', 'Loggi', 'Felipe', 'Elcio', 'Denner',
    'Bruno', 'Jaci', 'Kennedy', 'Rodrigo', 'Jose', 'Matheus', '-'
  ];

  final normalized = name.trim().toLowerCase();

  // Busca por correspondência case-insensitive
  for (final allowed in allowedNames) {
    if (allowed.toLowerCase() == normalized) {
      return allowed; // <-- Retorna o nome EXATO do backend
    }
  }

  // Fallback rápido para variações de "John Lenon"
  if (normalized == 'john lenon') {
    return 'John Lenon';
  }

  // Último recurso: Title case simples
  return name.trim().split(' ').map((word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }).join(' ');
}

// =============================================
// 2. SERVIÇO ESTÁTICO (OTIMIZADO)
// =============================================
class DeliveryService {
  // Cache para evitar chamadas duplicadas recentes
  static final Map<String, DateTime> _checkCache = {};
  static const _cacheTimeout = Duration(minutes: 5);

  static Future<bool> checkDuplicate(String id) async {
    if (_checkCache.containsKey(id)) {
      final cached = _checkCache[id]!;
      if (DateTime.now().difference(cached) < _cacheTimeout) {
        return true;
      }
      _checkCache.remove(id);
    }

    final base = dotenv.env['API_BASE_URL'] ?? '';
    final ep = dotenv.env['CHECK_DUPLICATE_ENDPOINT'] ?? '';
    if (base.isEmpty || ep.isEmpty) return false;

    final url = Uri.parse('$base$ep&id_pedido=$id');
    try {
      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.body.isNotEmpty) {
        final data = jsonDecode(resp.body);
        final isDup = data['status'] == 'success' && data['is_duplicate'] == true;
        if (isDup) _checkCache[id] = DateTime.now();
        return isDup;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('checkDuplicate erro (ignorado): $e');
    }
    return false;
  }

  static Future<Map<String, dynamic>?> registerDeliveryWithPhone(
      String id, String entregador) async {
    final base = dotenv.env['API_BASE_URL'] ?? '';
    final ep = dotenv.env['ASSIGN_AND_SAVE_DELIVERY_ENDPOINT'] ?? '';
    if (base.isEmpty || ep.isEmpty) return null;

    final url = Uri.parse('$base$ep');
    final body = {
      'id_pedido': id,
      'nome_entregador': entregador,
      'timestamp': DateTime.now().toIso8601String(),
      'bairro': 'N/A',
      'rua': 'N/A',
      'telefone': 'N/A',
      'nome': 'N/A',
      'pagamento': 'N/A',
      'numero': 'N/A',
      'cidade': 'N/A',
    };

    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      ).timeout(const Duration(seconds: 10));

      if (kDebugMode) debugPrint('REGISTER RESPONSE: ${resp.body}');

      if (resp.statusCode != 200 || resp.body.isEmpty) return null;

      final data = jsonDecode(resp.body);
      final success = data['status'] == 'success';
      final phone = data['telefone']?.toString();

      return {
        'success': success,
        'phone': phone,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('registerDeliveryWithPhone erro: $e');
      return null;
    }
  }

  static Future<void> enviarMensagemSaiuPraEntrega(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber == 'N/A' || phoneNumber.trim().isEmpty) {
      if (kDebugMode) debugPrint('Número de telefone inválido ou não fornecido');
      return;
    }
    const mensagem = "Vrummm! O seu pedido acabou de sair para entrega! - Mensagem Automática";
    final phone = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) {
      if (kDebugMode) debugPrint('Número de telefone inválido após formatação');
      return;
    }
    final messageApiUrl = dotenv.env['MESSAGE_API_URL'] ?? '';
    final messageApiKey = dotenv.env['MESSAGE_API_KEY'] ?? '';
    if (messageApiUrl.isEmpty || messageApiKey.isEmpty) {
      if (kDebugMode) debugPrint('Erro: Variáveis de ambiente MESSAGE_API_URL ou MESSAGE_API_KEY não definidas');
      return;
    }
    final payload = {"number": phone, "text": mensagem};
    final headers = {"Content-Type": "application/json", "apikey": messageApiKey};

    try {
      final response = await http
          .post(Uri.parse(messageApiUrl), headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 10));
      if (kDebugMode) debugPrint("Mensagem 'Saiu pra Entrega' enviada: ${response.body}");
    } catch (error) {
      if (kDebugMode) debugPrint("Erro ao enviar mensagem 'Saiu pra Entrega': $error");
    }
  }
}

// =============================================
// 3. TELA DO SCANNER (OTIMIZADA)
// =============================================
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with TickerProviderStateMixin {
  MobileScannerController? _camCtrl;

  bool _processing = false;
  String? _entregador;

  // Debounce otimizado
  Timer? _debounceTimer;
  String? _lastScannedId;

  late SharedPreferences _prefs;
  late AnimationController _scanLineCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _scanLineAnim;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    // Animação da linha de scan
    _scanLineCtrl = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scanLineAnim = CurvedAnimation(
      parent: _scanLineCtrl,
      curve: Curves.easeInOut,
    );

    // Animação de pulso para o frame
    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _entregador = _prefs.getString('entregador');
    await _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final p = await Permission.camera.request();
    if (!p.isGranted) {
      _showMessage('Permissão de câmera necessária', isError: true);
      return;
    }

    try {
      await _camCtrl?.dispose();

      _camCtrl = MobileScannerController(
        formats: [BarcodeFormat.qrCode],
        facing: CameraFacing.back,
        torchEnabled: false,
        returnImage: false,
        detectionSpeed: DetectionSpeed.noDuplicates,
        autoStart: true,
      );

      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao iniciar câmera: $e');
      _showMessage('Erro ao iniciar câmera', isError: true);
    }
  }

  void _showMessage(String txt, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                txt,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red.shade600 : const Color(0xFFF28C38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: Duration(seconds: isError ? 3 : 2),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!mounted || _processing) return;
    if (capture.barcodes.isEmpty) return;

    final raw = capture.barcodes.first.displayValue ?? '';
    final id = _extractId(raw);
    if (id == null || id.isEmpty) return;

    // Debounce otimizado
    if (_lastScannedId == id) return;

    _lastScannedId = id;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      _lastScannedId = null;
    });

    await _processQRCode(id);
  }

  Future<void> _processQRCode(String id) async {
    setState(() => _processing = true);

    HapticFeedback.mediumImpact();

    try {
      await _camCtrl?.stop();
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao parar câmera: $e');
    }

    // Verificação de duplicata
    final isDuplicate = await DeliveryService.checkDuplicate(id).timeout(
      const Duration(milliseconds: 1500),
      onTimeout: () => false,
    );

    if (isDuplicate) {
      HapticFeedback.heavyImpact();
      _showMessage('Este pedido já foi escaneado', isError: true);
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.pop(context, 'duplicate');
      return;
    }

    HapticFeedback.lightImpact();
    _showMessage('Pedido registrado com sucesso!');

    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) Navigator.pop(context, true);

    // Processamento em background
    _backgroundTasks(id);
  }

  String? _extractId(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.queryParameters.containsKey('id')) {
        return uri.queryParameters['id'];
      }
      return url.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _backgroundTasks(String id) async {
    var entregador = _entregador;
    if (entregador == null || entregador.isEmpty) {
      if (kDebugMode) debugPrint('Entregador não definido');
      return;
    }

    // <-- NORMALIZA O NOME ANTES DE ENVIAR
    entregador = normalizeEntregadorName(entregador);
    if (kDebugMode) debugPrint('Entregador normalizado: "$_entregador" → "$entregador"');

    // (Opcional) Validação local antes do envio
    const allowed = [
      'Uber', 'Lala-Move', 'Gabriel', 'Leonardo', 'John Lenon', 'Reginaldo',
      'Jeferson', 'Marcos Geraldo', 'Gilvan', 'Leandro', 'Eduardo', 'Marcelo',
      'Retirada', 'Paulo', 'Diogo', 'Loggi', 'Felipe', 'Elcio', 'Denner',
      'Bruno', 'Jaci', 'Kennedy', 'Rodrigo', 'Jose', 'Matheus', '-'
    ];
    if (!allowed.contains(entregador)) {
      if (kDebugMode) debugPrint('Entregador não autorizado: $entregador');
      return;
    }

    try {
      final result = await DeliveryService.registerDeliveryWithPhone(id, entregador);
      if (result == null || !result['success']) {
        if (kDebugMode) debugPrint('Erro ao registrar entrega');
        return;
      }

      final String? phone = result['phone'] as String?;
      await DeliveryService.enviarMensagemSaiuPraEntrega(phone);

      if (kDebugMode) debugPrint('Background tasks concluídas');
    } catch (e) {
      if (kDebugMode) debugPrint('Background error: $e');
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _debounceTimer?.cancel();
    _scanLineCtrl.dispose();
    _pulseCtrl.dispose();
    _camCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final safePadding = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Câmera
          if (_camCtrl != null && (Platform.isAndroid || Platform.isIOS))
            MobileScanner(
              controller: _camCtrl!,
              onDetect: _onDetect,
            ),

          // Overlay escuro
          CustomPaint(
            size: Size(size.width, size.height),
            painter: ScannerOverlayPainter(),
          ),

          // Frame animado com pulso
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) {
              return CustomPaint(
                size: Size(size.width, size.height),
                painter: AnimatedFramePainter(_pulseAnim.value),
              );
            },
          ),

          // Linha de scan animada
          AnimatedBuilder(
            animation: _scanLineAnim,
            builder: (context, child) {
              final scanAreaSize = size.width * 0.7;
              final scanAreaTop = size.height * 0.3;

              return Positioned(
                top: scanAreaTop + (_scanLineAnim.value * scanAreaSize),
                left: size.width * 0.15,
                right: size.width * 0.15,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Colors.transparent,
                        Color(0xFFF28C38),
                        Color(0xFFF28C38),
                        Colors.transparent,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF28C38).withOpacity(0.6),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Header com glassmorphism
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: safePadding.top + 8,
                bottom: 16,
                left: 8,
                right: 8,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.black.withOpacity(0.4),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildGlassButton(
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.pop(context),
                  ),
                  _buildGlassButton(
                    icon: _camCtrl?.torchEnabled ?? false
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                    onPressed: () => _camCtrl?.toggleTorch(),
                  ),
                ],
              ),
            ),
          ),

          // Instruções elegantes
          Positioned(
            top: size.height * 0.15,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Color(0xFFF28C38),
                    size: 48,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: const Color(0xFFF28C38).withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Text(
                    'Posicione o QR Code na área',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Loading overlay elegante
          if (_processing)
            Container(
              color: Colors.black.withOpacity(0.85),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFFF28C38).withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(
                          color: const Color(0xFFF28C38),
                          strokeWidth: 4,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Processando pedido...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Aguarde um momento',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGlassButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

// =============================================
// 4. OVERLAY PAINTER (MELHORADO)
// =============================================
class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    final scanAreaSize = size.width * 0.7;
    final left = (size.width - scanAreaSize) / 2;
    final top = size.height * 0.3;
    final rect = Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize);

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(32)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// =============================================
// 5. FRAME ANIMADO PAINTER
// =============================================
class AnimatedFramePainter extends CustomPainter {
  final double pulseValue;

  AnimatedFramePainter(this.pulseValue);

  @override
  void paint(Canvas canvas, Size size) {
    final scanAreaSize = size.width * 0.7;
    final left = (size.width - scanAreaSize) / 2;
    final top = size.height * 0.3;

    final opacity = 0.7 + (pulseValue * 0.3);
    final cornerPaint = Paint()
      ..color = const Color(0xFFF28C38).withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    const cornerLength = 40.0;
    const radius = 32.0;

    void drawCorner(Offset start, Offset horizontal, Offset vertical) {
      final path = Path()..moveTo(start.dx, start.dy);

      if (start.dx < size.width / 2 && start.dy < size.height / 2) {
        path.lineTo(start.dx, start.dy + cornerLength);
        path.moveTo(start.dx, start.dy);
        path.lineTo(start.dx + cornerLength, start.dy);
      } else if (start.dx > size.width / 2 && start.dy < size.height / 2) {
        path.lineTo(start.dx, start.dy + cornerLength);
        path.moveTo(start.dx, start.dy);
        path.lineTo(start.dx - cornerLength, start.dy);
      } else if (start.dx < size.width / 2 && start.dy > size.height / 2) {
        path.lineTo(start.dx, start.dy - cornerLength);
        path.moveTo(start.dx, start.dy);
        path.lineTo(start.dx + cornerLength, start.dy);
      } else {
        path.lineTo(start.dx, start.dy - cornerLength);
        path.moveTo(start.dx, start.dy);
        path.lineTo(start.dx - cornerLength, start.dy);
      }

      canvas.drawPath(path, cornerPaint);
    }

    drawCorner(
      Offset(left, top + radius),
      Offset(left + cornerLength, top + radius),
      Offset(left, top + radius + cornerLength),
    );
    drawCorner(
      Offset(left + scanAreaSize, top + radius),
      Offset(left + scanAreaSize - cornerLength, top + radius),
      Offset(left + scanAreaSize, top + radius + cornerLength),
    );
    drawCorner(
      Offset(left, top + scanAreaSize - radius),
      Offset(left + cornerLength, top + scanAreaSize - radius),
      Offset(left, top + scanAreaSize - radius - cornerLength),
    );
    drawCorner(
      Offset(left + scanAreaSize, top + scanAreaSize - radius),
      Offset(left + scanAreaSize - cornerLength, top + scanAreaSize - radius),
      Offset(left + scanAreaSize, top + scanAreaSize - radius - cornerLength),
    );

    final glowPaint = Paint()
      ..color = const Color(0xFFF28C38).withOpacity(0.1 + (pulseValue * 0.1))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);

    final glowRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize),
      const Radius.circular(32),
    );

    canvas.drawRRect(glowRect, glowPaint);
  }

  @override
  bool shouldRepaint(AnimatedFramePainter old) => old.pulseValue != pulseValue;
}