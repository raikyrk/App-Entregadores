import 'dart:async';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with TickerProviderStateMixin {
  MobileScannerController? _camCtrl;
  bool _processing = false;
  bool _isSuccess = false; // 👉 O NOVO ESTADO DE SUCESSO!
  String? _lastScannedId;
  Timer? _debounceTimer;

  late AnimationController _scanLineCtrl;
  late Animation<double> _scanLineAnim;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    _scanLineCtrl = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this)..repeat(reverse: true);
    _scanLineAnim = CurvedAnimation(parent: _scanLineCtrl, curve: Curves.easeInOut);

    _pulseCtrl = AnimationController(duration: const Duration(milliseconds: 2000), vsync: this)..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _initCamera();
  }

  Future<void> _initCamera() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    _camCtrl = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      facing: CameraFacing.back,
      torchEnabled: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
    if (mounted) setState(() {});
  }

  void _showMessage(String text, {bool isError = false}) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFE53E3E) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String? _extractId(String rawData) {
    try {
      final uri = Uri.tryParse(rawData);
      if (uri != null && uri.hasQuery) {
        if (uri.queryParameters.containsKey('id')) return uri.queryParameters['id'];
        if (uri.queryParameters.containsKey('pedido')) return uri.queryParameters['pedido'];
      }
      return rawData.trim();
    } catch (_) {
      return rawData.trim();
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!mounted || _processing || _isSuccess || capture.barcodes.isEmpty) return;

    final raw = capture.barcodes.first.displayValue ?? '';
    final id = _extractId(raw);
    
    if (id == null || id.isEmpty) return;

    if (_lastScannedId == id) return;
    _lastScannedId = id;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () => _lastScannedId = null);

    await _processDelivery(id);
  }

  Future<void> _processDelivery(String pedidoId) async {
    setState(() => _processing = true);
    HapticFeedback.lightImpact();

    try {
      final prefs = await SharedPreferences.getInstance();
      final nomeEntregador = prefs.getString('entregador') ?? 'Entregador Desconhecido';
      
      final docRef = FirebaseFirestore.instance.collection('pedidos').doc(pedidoId);
      final docSnap = await docRef.get();

      if (!docSnap.exists) {
        _showMessage('O pedido #$pedidoId não foi encontrado na base de dados.', isError: true);
        setState(() => _processing = false);
        return;
      }

      final data = docSnap.data()!;
      final statusAtual = data['status']?.toString().toLowerCase() ?? '';
      final entregadorAtual = data['entregador']?.toString() ?? '';

      if (statusAtual.contains('conclu') || statusAtual.contains('entregue')) {
        _showMessage('Atenção: Este pedido já foi entregue!', isError: true);
        setState(() => _processing = false);
        return;
      }
      
      if (entregadorAtual.isNotEmpty && entregadorAtual != '-' && entregadorAtual != nomeEntregador) {
        _showMessage('Este pedido já está com o entregador: $entregadorAtual!', isError: true);
        setState(() => _processing = false);
        return;
      }

      // ATUALIZA NO FIRESTORE
      await docRef.update({
        'entregador': nomeEntregador,
        'status': 'Saiu pra Entrega',
        'data_saida': FieldValue.serverTimestamp(),
      });

      // 👉 A MÁGICA DA RECOMPENSA VISUAL
      HapticFeedback.heavyImpact(); // Vibração forte
      if (!mounted) return;
      
      setState(() {
        _processing = false;
        _isSuccess = true; // Aciona a tela verde gigante!
      });

      // Deixa o entregador "curtir" a tela de sucesso por 1.5 segundos
      await Future.delayed(const Duration(milliseconds: 1500));
      
      if (!mounted) return;
      Navigator.pop(context, true); // Volta avisando o Dashboard que deu certo!

    } catch (e) {
      _showMessage('Erro de conexão. Tente novamente.', isError: true);
      setState(() => _processing = false);
    }
  }

  void _showDebugDialog() {
    final TextEditingController ctrl = TextEditingController(text: '149691'); 
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.bug_report_rounded, color: Color(0xFFF28C38)),
            SizedBox(width: 8),
            Text('Modo Dev', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Simular leitura de QR Code:', style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'ID do Pedido',
                labelStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.qr_code_rounded, color: Colors.grey),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade800), borderRadius: BorderRadius.circular(16)),
                focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFF28C38), width: 2), borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _processDelivery(ctrl.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF28C38), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Simular', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
    final safeTop = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_camCtrl != null) MobileScanner(controller: _camCtrl!, onDetect: _onDetect),
          CustomPaint(size: Size(size.width, size.height), painter: ScannerOverlayPainter()),
          AnimatedBuilder(animation: _pulseAnim, builder: (context, child) => CustomPaint(size: Size(size.width, size.height), painter: AnimatedFramePainter(_pulseAnim.value))),
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
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.transparent, Color(0xFFF28C38), Color(0xFFF28C38), Colors.transparent]), boxShadow: [BoxShadow(color: const Color(0xFFF28C38).withOpacity(0.8), blurRadius: 15, spreadRadius: 2)]),
                ),
              );
            },
          ),
          Positioned(
            top: safeTop + 16, left: 20, right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildGlassButton(Icons.close_rounded, () => Navigator.pop(context)),
                Row(
                  children: [
                    if (kDebugMode) Padding(padding: const EdgeInsets.only(right: 12), child: _buildGlassButton(Icons.bug_report_rounded, _showDebugDialog)),
                    _buildGlassButton(_camCtrl?.torchEnabled ?? false ? Icons.flash_on_rounded : Icons.flash_off_rounded, () { _camCtrl?.toggleTorch(); setState(() {}); }),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: size.height * 0.15, left: 0, right: 0,
            child: const Column(
              children: [
                Text('Escanear Pedido', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                SizedBox(height: 8),
                Text('Centralize o QR Code na marcação', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),

          // LOADING DE PROCESSAMENTO
          if (_processing)
            Container(
              color: Colors.black.withOpacity(0.85),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                  decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.white.withOpacity(0.1)), boxShadow: [BoxShadow(color: const Color(0xFFF28C38).withOpacity(0.2), blurRadius: 40, spreadRadius: 5)]),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 50, height: 50, child: CircularProgressIndicator(color: Color(0xFFF28C38), strokeWidth: 4, strokeCap: StrokeCap.round)),
                      const SizedBox(height: 24),
                      const Text('Atribuindo Rota...', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Sincronizando com a base', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),

          // 👉 TELA DE SUCESSO (A MAIOR RECOMPENSA DE UX)
          if (_isSuccess)
            Container(
              color: Colors.black.withOpacity(0.9),
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.5), blurRadius: 40, spreadRadius: 10)],
                            ),
                            child: const Icon(Icons.check_rounded, color: Colors.white, size: 80),
                          ),
                          const SizedBox(height: 32),
                          const Text('Pedido Atribuído!', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                          const SizedBox(height: 8),
                          Text('Redirecionando para Corridas...', style: TextStyle(color: Colors.grey[400], fontSize: 16)),
                        ],
                      ),
                    );
                  }
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGlassButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.2))), child: Icon(icon, color: Colors.white, size: 24)),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.75)..style = PaintingStyle.fill;
    final scanAreaSize = size.width * 0.7;
    final left = (size.width - scanAreaSize) / 2;
    final top = size.height * 0.3;
    final rect = Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize);
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height))..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(40)))..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class AnimatedFramePainter extends CustomPainter {
  final double pulseValue;
  AnimatedFramePainter(this.pulseValue);

  @override
  void paint(Canvas canvas, Size size) {
    final scanAreaSize = size.width * 0.7;
    final left = (size.width - scanAreaSize) / 2;
    final top = size.height * 0.3;
    final paint = Paint()..color = const Color(0xFFF28C38).withOpacity(0.8 + (pulseValue * 0.2))..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round;
    const cornerLength = 40.0;
    const radius = 40.0;
    void drawCorner(Offset start, Offset h, Offset v) {
      final path = Path()..moveTo(start.dx, start.dy)..lineTo(h.dx, h.dy)..moveTo(start.dx, start.dy)..lineTo(v.dx, v.dy);
      canvas.drawPath(path, paint);
    }
    drawCorner(Offset(left, top + radius), Offset(left, top + radius + cornerLength), Offset(left + radius + cornerLength, top));
    drawCorner(Offset(left + scanAreaSize, top + radius), Offset(left + scanAreaSize, top + radius + cornerLength), Offset(left + scanAreaSize - radius - cornerLength, top));
    drawCorner(Offset(left, top + scanAreaSize - radius), Offset(left, top + scanAreaSize - radius - cornerLength), Offset(left + radius + cornerLength, top + scanAreaSize));
    drawCorner(Offset(left + scanAreaSize, top + scanAreaSize - radius), Offset(left + scanAreaSize, top + scanAreaSize - radius - cornerLength), Offset(left + scanAreaSize - radius - cornerLength, top + scanAreaSize));
    final glowPaint = Paint()..color = const Color(0xFFF28C38).withOpacity(0.15 + (pulseValue * 0.15))..style = PaintingStyle.stroke..strokeWidth = 2..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    final glowRect = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize), const Radius.circular(40));
    canvas.drawRRect(glowRect, glowPaint);
  }
  @override
  bool shouldRepaint(AnimatedFramePainter old) => old.pulseValue != pulseValue;
}