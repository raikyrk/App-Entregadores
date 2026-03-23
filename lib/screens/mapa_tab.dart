import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class MapaTab extends StatefulWidget {
  const MapaTab({super.key});

  @override
  State<MapaTab> createState() => _MapaTabState();
}

class _MapaTabState extends State<MapaTab> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;
  
  LatLng _currentPosition = const LatLng(-19.9167, -43.9345); // Praça Sete (BH) Padrão
  bool _isLoadingGps = true;
  bool _hasPermission = false;
  
  // 👉 Controle do nosso Banner de Visão de Futuro
  bool _showFutureFeatureTeaser = true;
  
  String _entregadorName = '';
  List<LatLng> _todasAsCoordenadas = [];

  @override
  void initState() {
    super.initState();
    _loadEntregadorEIniciarGps();
  }

  Future<void> _loadEntregadorEIniciarGps() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _entregadorName = prefs.getString('entregador') ?? '';
    });
    _checkLocationPermission();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showError('O GPS do celular está desativado.');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showError('Permissão de localização negada.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showError('Permissões de localização permanentemente negadas.');
      return;
    }

    setState(() => _hasPermission = true);
    _startTracking();
  }

  void _startTracking() async {
    try {
      Position initialPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(initialPos.latitude, initialPos.longitude);
          _isLoadingGps = false;
        });
        _mapController.move(_currentPosition, 16.0);
      }
    } catch (e) {
      debugPrint("Erro GPS inicial: $e");
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((Position position) {
      if (mounted) {
        setState(() => _currentPosition = LatLng(position.latitude, position.longitude));
      }
    });
  }

  void _recenterMap() {
    HapticFeedback.lightImpact();
    _mapController.move(_currentPosition, 16.0);
  }

  void _fitBounds() {
    HapticFeedback.lightImpact();
    if (_todasAsCoordenadas.isEmpty) {
      _recenterMap();
      return;
    }
    
    final points = [_currentPosition, ..._todasAsCoordenadas];
    final bounds = LatLngBounds.fromPoints(points);
    
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60.0)),
    );
  }

  void _showError(String msg) {
    if (mounted) {
      setState(() => _isLoadingGps = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final mapUrl = isDark 
        ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png' 
        : 'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1115) : const Color(0xFFF4F6F9),
      extendBodyBehindAppBar: true, // Deixa o mapa subir e ocupar a tela toda
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // Efeito de sombra sutil no texto do AppBar para dar leitura por cima do mapa
        title: Text(
          'Mapa ao Vivo', 
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A), 
            fontWeight: FontWeight.w900, 
            letterSpacing: -1.0,
            fontSize: 28,
            shadows: [Shadow(color: isDark ? Colors.black54 : Colors.white70, blurRadius: 10)]
          )
        ),
        centerTitle: false,
      ),
      body: Stack(
        children: [
          // 1. MOTOR DO MAPA
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('pedidos')
                .where('entregador', isEqualTo: _entregadorName)
                .snapshots(),
            builder: (context, snapshot) {
              
              List<Marker> markersDePedidos = [];
              _todasAsCoordenadas.clear(); 

              if (snapshot.hasData) {
                final pedidosPendentes = snapshot.data!.docs.where((doc) {
                  final status = (doc.data() as Map<String, dynamic>)['status']?.toString().toLowerCase() ?? '';
                  return status.contains('saiu') || status.contains('andamento');
                });

                for (var doc in pedidosPendentes) {
                  final data = doc.data() as Map<String, dynamic>;
                  final enderecoMap = data['endereco'];
                  
                  if (enderecoMap is Map && enderecoMap['latitude'] != null && enderecoMap['longitude'] != null) {
                    final lat = (enderecoMap['latitude'] as num).toDouble();
                    final lng = (enderecoMap['longitude'] as num).toDouble();
                    final pos = LatLng(lat, lng);
                    
                    _todasAsCoordenadas.add(pos); 
                    
                    DateTime? dataPedido;
                    if (data['timestamp'] != null) {
                      dataPedido = data['timestamp'] is Timestamp 
                          ? (data['timestamp'] as Timestamp).toDate() 
                          : DateTime.tryParse(data['timestamp'].toString());
                    }

                    Color pinColor = const Color(0xFF10B981); 
                    if (dataPedido != null) {
                      final atraso = DateTime.now().difference(dataPedido);
                      if (atraso.inHours >= 2) pinColor = const Color(0xFFEF4444); 
                      else if (atraso.inHours >= 1) pinColor = const Color(0xFFF59E0B); 
                    }

                    markersDePedidos.add(
                      Marker(
                        point: pos,
                        width: 50,
                        height: 50,
                        child: GestureDetector(
                          onTap: () => _showMiniCard(context, doc.id, data, isDark),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(Icons.location_on_rounded, color: pinColor, size: 48),
                              const Positioned(top: 8, child: Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 16)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                }
              }

              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentPosition,
                  initialZoom: 15.0,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                ),
                children: [
                  TileLayer(urlTemplate: mapUrl, userAgentPackageName: 'com.aogosto.app'),
                  MarkerLayer(
                    markers: [
                      Marker(point: _currentPosition, width: 60, height: 60, child: _buildDriverMarker()),
                      ...markersDePedidos,
                    ],
                  ),
                ],
              );
            },
          ),

          // 2. LOADING GPS
          if (_isLoadingGps)
            Container(
              color: isDark ? const Color(0xFF0F1115).withOpacity(0.8) : Colors.white.withOpacity(0.8),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFF28C38)),
                    SizedBox(height: 16),
                    Text('Buscando satélites...', style: TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),

          // 👉 3. O BANNER DE TEASER (VISÃO DE FUTURO)
          if (_showFutureFeatureTeaser)
            Positioned(
              top: 110, // Logo abaixo do AppBar
              left: 20,
              right: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), // Vidro Fosco
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1D24).withOpacity(0.85) : Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFF28C38).withOpacity(0.4), width: 1.5),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Ícone Radar Fluorescente
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF28C38).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.radar_rounded, color: Color(0xFFF28C38), size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Vem aí: Coletas em Rede', 
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: isDark ? Colors.white : const Color(0xFF0F172A), letterSpacing: -0.5)
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Em breve, você poderá visualizar e coletar pedidos de outros CDs no mapa. 🤑', 
                                style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontWeight: FontWeight.w600, height: 1.4)
                              ),
                            ],
                          ),
                        ),
                        // Botão Fechar Elegante
                        GestureDetector(
                          onTap: () => setState(() => _showFutureFeatureTeaser = false),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05), shape: BoxShape.circle),
                            child: Icon(Icons.close_rounded, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 4. BOTÕES FLUTUANTES (Controles do Mapa)
          if (!_isLoadingGps && _hasPermission)
            Positioned(
              bottom: 120, // Acima da barra de navegação
              right: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Botão de Visão Global (Otimizado)
                  Container(
                    decoration: BoxDecoration(
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: FloatingActionButton(
                      heroTag: 'fit_bounds_btn',
                      onPressed: _fitBounds,
                      mini: true,
                      elevation: 0,
                      backgroundColor: isDark ? const Color(0xFF2C2F36) : Colors.white,
                      child: Icon(Icons.zoom_out_map_rounded, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Botão de Centralizar (Otimizado)
                  Container(
                    decoration: BoxDecoration(
                      boxShadow: [BoxShadow(color: const Color(0xFFF28C38).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: FloatingActionButton(
                      heroTag: 'recenter_btn',
                      onPressed: _recenterMap,
                      elevation: 0,
                      backgroundColor: const Color(0xFFF28C38), 
                      child: const Icon(Icons.my_location_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDriverMarker() {
    return Stack(
      alignment: Alignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(seconds: 2),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Container(width: 60 * value, height: 60 * value, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFF28C38).withOpacity(1.0 - value)));
          },
          onEnd: () { if (mounted) setState(() {}); },
        ),
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: const Color(0xFFF28C38), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))]),
          child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 20),
        ),
      ],
    );
  }

  // ===========================================================================
  // 👉 MINI-CARD (AGORA COM DNA PREMIUM SLATE)
  // ===========================================================================
  void _showMiniCard(BuildContext context, String pedidoId, Map<String, dynamic> data, bool isDark) {
    HapticFeedback.lightImpact();
    
    String clienteText = 'Cliente Ao Gosto';
    if (data['cliente'] is String) clienteText = data['cliente'];
    else if (data['cliente'] is Map) clienteText = data['cliente']['nome'] ?? 'Cliente Ao Gosto';

    String enderecoText = 'Endereço não informado';
    if (data['endereco'] is Map) {
      final map = data['endereco'] as Map<String, dynamic>;
      final rua = map['rua'] ?? '';
      final num = map['numero'] ?? '';
      final bairro = map['bairro'] ?? '';
      enderecoText = '$rua, $num - $bairro';
      enderecoText = enderecoText.replaceAll(RegExp(r'^, | - $'), '').trim();
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1D24) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 28),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFF28C38).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                  child: Text('#$pedidoId', style: const TextStyle(color: Color(0xFFF28C38), fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(clienteText, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A), letterSpacing: -0.5), overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.location_on_rounded, size: 16, color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(enderecoText, style: TextStyle(fontSize: 15, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontWeight: FontWeight.w500, height: 1.4))),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context); 
                  _showMapOptions(context, enderecoText, isDark); 
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 22),
                label: const Text('Navegar até o cliente', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 👉 SELETOR DE WAZE / GOOGLE MAPS (COM DNA PREMIUM SLATE)
  // ===========================================================================
  void _showMapOptions(BuildContext context, String endereco, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(color: isDark ? const Color(0xFF1A1D24) : Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(36))),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(margin: const EdgeInsets.only(bottom: 24), width: 48, height: 5, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(3)))),
            Text('Iniciar Rota', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A), letterSpacing: -0.5), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            _buildMapAppCard(context, 'Google Maps', Icons.map_rounded, const Color(0xFF4285F4), () => _openNavApp('google.navigation:q=', 'http://maps.google.com/maps?q=', endereco), isDark),
            const SizedBox(height: 16),
            _buildMapAppCard(context, 'Waze', Icons.navigation_rounded, const Color(0xFF33CCFF), () => _openNavApp('waze://?q=', 'https://waze.com/ul?q=', endereco), isDark),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMapAppCard(BuildContext ctx, String title, IconData icon, Color iconColor, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF22252D) : Colors.white,
          border: Border.all(color: isDark ? Colors.transparent : const Color(0xFFE2E8F0)), 
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
        ),
        child: Row(
          children: [
            Container(width: 52, height: 52, decoration: BoxDecoration(color: iconColor.withOpacity(0.15), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: iconColor, size: 28)),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                  const SizedBox(height: 2),
                  Text('Navegação otimizada', style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 18, color: isDark ? const Color(0xFF64748B) : const Color(0xFFCBD5E1)),
          ],
        ),
      ),
    );
  }

  Future<void> _openNavApp(String scheme, String fallbackUrl, String endereco) async {
    final enc = Uri.encodeComponent(endereco);
    try {
      if (!await launchUrl(Uri.parse('$scheme$enc'), mode: LaunchMode.externalApplication)) {
        await launchUrl(Uri.parse('$fallbackUrl$enc'), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(Uri.parse('$fallbackUrl$enc'), mode: LaunchMode.externalApplication);
    }
    if (mounted) Navigator.pop(context); 
  }
}