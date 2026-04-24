import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart'; 
import 'package:geolocator/geolocator.dart'; // 👉 GPS
import 'package:permission_handler/permission_handler.dart'; // 👉 Notificações

import 'login_screen.dart';
import '../services/location_service.dart';

class ProfileTab extends StatefulWidget {
  final String initialName;
  final String cdName;
  final bool isTracking;

  const ProfileTab({
    super.key,
    required this.initialName,
    required this.cdName,
    required this.isTracking,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

// 👉 O "WidgetsBindingObserver" FAZ O APP PERCEBER QUANDO O MOTOBOY VOLTA DAS CONFIGURAÇÕES!
class _ProfileTabState extends State<ProfileTab> with WidgetsBindingObserver {
  String _apelido = '';
  String _telefone = '';
  String _placa = '';
  String _corMoto = '';
  String? _localImagePath; 
  String? _remoteImageUrl; 
  String _appVersion = ''; 
  
  // 🚀 A MÁGICA DO SHOREBIRD AQUI:
  // Quando você fizer um hotfix, mude para "2", rode `shorebird patch` e todos os apps atualizam na rua!
  final String _otaPatchVersion = "3"; 
  
  bool _isUploadingPhoto = false; 

  // Variáveis da Saúde do App
  bool _hasGps = false;
  bool _hasBgGps = false;
  bool _hasNotifications = false;
  bool _isLoadingDiagnostics = true;

  final ImagePicker _picker = ImagePicker();

  // 👉 FocusNodes para a edição inline inteligente!
  final FocusNode _focusApelido = FocusNode();
  final FocusNode _focusTelefone = FocusNode();
  final FocusNode _focusPlaca = FocusNode();
  final FocusNode _focusCor = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Começa a observar o celular
    _loadData();
    _loadAppVersion(); 
    _checkDiagnostics(); // Roda o Raio-X nas permissões
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Para de observar ao fechar a aba
    _focusApelido.dispose();
    _focusTelefone.dispose();
    _focusPlaca.dispose();
    _focusCor.dispose();
    super.dispose();
  }

  // Se ele foi nas configurações e voltou pro app, roda o Raio-X de novo!
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDiagnostics();
    }
  }

  // ===========================================================================
  // 👉 MOTOR DE DIAGNÓSTICO DO SISTEMA (RAIO-X)
  // ===========================================================================
  Future<void> _checkDiagnostics() async {
    setState(() => _isLoadingDiagnostics = true);

    try {
      bool gpsEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission locPerm = await Geolocator.checkPermission();
      
      bool isGpsGranted = (locPerm == LocationPermission.whileInUse || locPerm == LocationPermission.always);
      bool isBgGranted = (locPerm == LocationPermission.always);

      var notifStatus = await Permission.notification.status;
      bool isNotifGranted = notifStatus.isGranted;

      if (mounted) {
        setState(() {
          _hasGps = gpsEnabled && isGpsGranted;
          _hasBgGps = isBgGranted;
          _hasNotifications = isNotifGranted;
          _isLoadingDiagnostics = false;
        });
      }
    } catch (e) {
      debugPrint('Erro no diagnóstico: $e');
      if (mounted) setState(() => _isLoadingDiagnostics = false);
    }
  }

  void _openSettings() async {
    HapticFeedback.heavyImpact();
    await Geolocator.openAppSettings();
  }

  // ===========================================================================
  // 👉 CARREGAMENTO DE DADOS (MANTIDO INTACTO)
  // ===========================================================================
  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = packageInfo.version);
    } catch (e) {
      debugPrint('Erro ao ler versão do app: $e');
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apelido = prefs.getString('apelido_entregador') ?? '';
      _telefone = prefs.getString('telefone_entregador') ?? '';
      _placa = prefs.getString('placa_moto') ?? '';
      _corMoto = prefs.getString('cor_moto') ?? '';
      _localImagePath = prefs.getString('foto_perfil_local'); 
      _remoteImageUrl = prefs.getString('foto_perfil_url');
    });

    if (_remoteImageUrl == null || _telefone.isEmpty) {
      try {
        final query = await FirebaseFirestore.instance.collection('entregadores').where('nome', isEqualTo: widget.initialName).limit(1).get();
        if (query.docs.isNotEmpty) {
          final data = query.docs.first.data();
          setState(() {
            _telefone = data['telefone_contato'] ?? _telefone;
            _placa = data['placa_veiculo'] ?? _placa;
            _corMoto = data['cor_veiculo'] ?? _corMoto;
            _apelido = data['apelido'] ?? _apelido;
            _remoteImageUrl = data['foto_url']; 
          });
          if(_remoteImageUrl != null) await prefs.setString('foto_perfil_url', _remoteImageUrl!);
          if(_telefone.isNotEmpty) await prefs.setString('telefone_entregador', _telefone);
        }
      } catch (e) {
        debugPrint('Erro na sync de inicialização: $e');
      }
    }
  }

  // ===========================================================================
  // 👉 UPLOAD DE FOTO PREMIUM
  // ===========================================================================
  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 40, maxWidth: 400);
      if (pickedFile == null) return;

      setState(() => _isUploadingPhoto = true);
      HapticFeedback.selectionClick();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('foto_perfil_local', pickedFile.path);
      setState(() => _localImagePath = pickedFile.path);

      final storageRef = FirebaseStorage.instance.ref().child('fotos_perfil').child('${widget.initialName.toLowerCase().replaceAll(' ', '_')}.jpg');
      await storageRef.putFile(File(pickedFile.path));
      final downloadUrl = await storageRef.getDownloadURL();

      final query = await FirebaseFirestore.instance.collection('entregadores').where('nome', isEqualTo: widget.initialName).limit(1).get();
      if (query.docs.isNotEmpty) { await query.docs.first.reference.update({'foto_url': downloadUrl}); }

      await prefs.setString('foto_perfil_url', downloadUrl);
      setState(() { _remoteImageUrl = downloadUrl; _isUploadingPhoto = false; });

      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Row(children: [Icon(Icons.check_circle_rounded, color: Colors.white), SizedBox(width: 8), Text('Foto atualizada!', style: TextStyle(fontWeight: FontWeight.bold))]), backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    } catch (e) {
      setState(() => _isUploadingPhoto = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Erro ao salvar foto. Verifique a internet.'), backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    }
  }

  void _showImagePickerModal() {
    HapticFeedback.lightImpact();
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        decoration: BoxDecoration(color: isDark ? const Color(0xFF1A1D24) : Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))]),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(margin: const EdgeInsets.only(top: 16, bottom: 16), height: 5, width: 48, decoration: BoxDecoration(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
            Padding(padding: const EdgeInsets.only(bottom: 16), child: Text('Atualizar Foto', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A), letterSpacing: -0.5))),
            _buildModalAction(icon: Icons.camera_alt_rounded, color: const Color(0xFF3B82F6), title: 'Tirar Selfie', onTap: () { Navigator.pop(ctx); _pickAndUploadImage(ImageSource.camera); }, isDark: isDark),
            _buildModalAction(icon: Icons.photo_library_rounded, color: const Color(0xFF8B5CF6), title: 'Escolher da Galeria', onTap: () { Navigator.pop(ctx); _pickAndUploadImage(ImageSource.gallery); }, isDark: isDark),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildModalAction({required IconData icon, required Color color, required String title, required VoidCallback onTap, required bool isDark}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: color, size: 24)),
            const SizedBox(width: 16),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF0F172A))),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 👉 MODAL DE EDIÇÃO REVISADO (ANTI-PUXADINHO)
  // ===========================================================================
  void _showEditModal({FocusNode? targetFocus}) {
    HapticFeedback.lightImpact();
    final cApelido = TextEditingController(text: _apelido);
    final cTelefone = TextEditingController(text: _telefone);
    final cPlaca = TextEditingController(text: _placa);
    final cCor = TextEditingController(text: _corMoto);

    // Abre o teclado no campo certo após o modal abrir
    Future.delayed(const Duration(milliseconds: 300), () {
      if (targetFocus != null && targetFocus.canRequestFocus) {
        targetFocus.requestFocus();
      }
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = MediaQuery.of(ctx).platformBrightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom), 
          child: Container(
            decoration: BoxDecoration(color: isDark ? const Color(0xFF1A1D24) : Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(36))),
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Container(height: 5, width: 48, decoration: BoxDecoration(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300, borderRadius: BorderRadius.circular(4)))),
                const SizedBox(height: 24),
                Text('Editar Informações', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A), letterSpacing: -0.5), textAlign: TextAlign.center),
                const SizedBox(height: 32),
                
                _buildModernInput('Como quer ser chamado?', cApelido, Icons.person_rounded, fNode: _focusApelido, isDark: isDark),
                const SizedBox(height: 16),
                _buildModernInput('WhatsApp', cTelefone, Icons.phone_android_rounded, fNode: _focusTelefone, type: TextInputType.phone, formatters: [_PhoneInputFormatter()], isDark: isDark),
                const SizedBox(height: 16),
                _buildModernInput('Placa da Moto', cPlaca, Icons.pin_rounded, fNode: _focusPlaca, formatters: [_UpperCaseTextFormatter(), LengthLimitingTextInputFormatter(8)], isDark: isDark),
                const SizedBox(height: 16),
                _buildModernInput('Cor da Moto', cCor, Icons.palette_rounded, fNode: _focusCor, isDark: isDark),
                
                const SizedBox(height: 32),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF28C38), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('apelido_entregador', cApelido.text);
                      await prefs.setString('telefone_entregador', cTelefone.text);
                      await prefs.setString('placa_moto', cPlaca.text);
                      await prefs.setString('cor_moto', cCor.text);
                      
                      try {
                        final query = await FirebaseFirestore.instance.collection('entregadores').where('nome', isEqualTo: widget.initialName).limit(1).get();
                        if (query.docs.isNotEmpty) { await query.docs.first.reference.update({'telefone_contato': cTelefone.text, 'placa_veiculo': cPlaca.text, 'cor_veiculo': cCor.text, 'apelido': cApelido.text}); }
                      } catch (e) { debugPrint('Aviso: Erro sync Firebase: $e'); }
                      
                      setState(() { _apelido = cApelido.text; _telefone = cTelefone.text; _placa = cPlaca.text; _corMoto = cCor.text; });
                      HapticFeedback.mediumImpact();
                      if (!mounted) return;
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Row(children: [Icon(Icons.cloud_done_rounded, color: Colors.white), SizedBox(width: 12), Expanded(child: Text('Perfil atualizado com sucesso!', style: TextStyle(fontWeight: FontWeight.bold)))]), backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))));
                    },
                    child: const Text('Salvar Alterações', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModernInput(String label, TextEditingController ctrl, IconData icon, {FocusNode? fNode, TextInputType type = TextInputType.text, List<TextInputFormatter>? formatters, required bool isDark}) {
    return TextField(
      controller: ctrl, keyboardType: type, inputFormatters: formatters, focusNode: fNode, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontWeight: FontWeight.w600, fontSize: 16),
      decoration: InputDecoration(
        labelText: label, labelStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[500], fontWeight: FontWeight.w500), prefixIcon: Icon(icon, color: isDark ? Colors.grey[600] : Colors.grey[400]), filled: true, fillColor: isDark ? const Color(0xFF2C2F36) : const Color(0xFFF8FAFC), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFF28C38), width: 2)),
      ),
    );
  }

  void _onLogout(BuildContext context) async {
    if (widget.isTracking) LocationService.stopTracking();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('entregador');
    await prefs.remove('cd_entregador');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
  }

  String _getInitials() {
    String nameToUse = _apelido.isNotEmpty ? _apelido : widget.initialName;
    List<String> parts = nameToUse.trim().split(' ');
    if (parts.length > 1) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0][0].toUpperCase();
  }

  // ===========================================================================
  // 👉 CONSTRUÇÃO DA TELA INCRÍVEL (A NOVA ERA)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final displayName = _apelido.isNotEmpty ? _apelido : widget.initialName;

    String nomeFormatado = displayName.isNotEmpty 
        ? displayName.split(' ').map((p) => p.isNotEmpty ? '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}' : '').join(' ')
        : 'Entregador';

    ImageProvider? profileImage;
    if (_localImagePath != null && File(_localImagePath!).existsSync()) {
      profileImage = FileImage(File(_localImagePath!));
    } else if (_remoteImageUrl != null && _remoteImageUrl!.isNotEmpty) {
      profileImage = NetworkImage(_remoteImageUrl!);
    }

    return Scaffold(
      backgroundColor: Colors.transparent, 
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 24),
            
            // 👉 CABEÇALHO INTEGRADO (AVATAR + NOME + CD) - EXPERT DESIGN
            Container(
              padding: const EdgeInsets.all(24),
              width: double.infinity,
              decoration: BoxDecoration(color: isDark ? const Color(0xFF1A1D24) : Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 10))]),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 👉 BOTÃO SAIR (ELEGANCE NO TOPO) - UX #1
                 Positioned(
                    top: -8, left: -8, // Ajustei levemente para o ícone novo encaixar melhor
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _showLogoutDialog(context),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12), 
                          // 👉 Trocamos o bolt_rounded pelo logout_rounded
                          child: Icon(Icons.logout_rounded, color: const Color(0xFFEF4444).withOpacity(0.8), size: 22)
                        ),
                      ),
                    ),
                  ),

                  // Marca d'água GO
                  Positioned(right: -30, top: -20, child: Image.asset('assets/go-laranja.png', height: 120, width: 120, fit: BoxFit.contain, opacity: const AlwaysStoppedAnimation(0.03))),

                  Column(
                    children: [
                      Center(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              height: 130, width: 130, padding: const EdgeInsets.all(4), 
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFF28C38), width: 2.5), boxShadow: [BoxShadow(color: const Color(0xFFF28C38).withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10))]),
                              child: Container(decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2F36) : const Color(0xFFF1F5F9), shape: BoxShape.circle, image: profileImage != null ? DecorationImage(image: profileImage, fit: BoxFit.cover) : null), child: profileImage == null && !_isUploadingPhoto ? Center(child: Text(_getInitials(), style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -1.0))) : null),
                            ),
                            if (_isUploadingPhoto) Positioned.fill(child: Container(margin: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), shape: BoxShape.circle), child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)))),
                            Positioned(bottom: 0, right: 6, child: InkWell(onTap: _isUploadingPhoto ? null : _showImagePickerModal, borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFF28C38), Color(0xFFE87A24)], begin: Alignment.topLeft, end: Alignment.bottomRight), shape: BoxShape.circle, border: Border.all(color: isDark ? const Color(0xFF1A1D24) : Colors.white, width: 3.5), boxShadow: [BoxShadow(color: const Color(0xFFF28C38).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]), child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 18))))
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(nomeFormatado, style: TextStyle(fontSize: 26, color: textColor, fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1.0)),
                      const SizedBox(height: 8),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2F36) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.storefront_rounded, size: 16, color: Color(0xFFF28C38)), const SizedBox(width: 8), Text(widget.cdName, style: TextStyle(fontSize: 14, color: isDark ? Colors.white.withOpacity(0.9) : const Color(0xFF334155), fontWeight: FontWeight.w700))])),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),

            // 👉 1. BENTO BOX: SAÚDE DO APP (MANTIDO E INTEGRADO)
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Saúde do App', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: isDark ? Colors.grey[500] : const Color(0xFF64748B), letterSpacing: 0.2))]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: isDark ? const Color(0xFF1A1D24) : Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 8))]),
              child: _isLoadingDiagnostics 
                ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: Color(0xFFF28C38))))
                : Column(
                    children: [
                      _buildDiagnosticRow('Localização (GPS)', _hasGps, Icons.location_on_rounded, isDark),
                      _buildDiagnosticRow('GPS em 2º Plano', _hasBgGps, Icons.radar_rounded, isDark),
                      _buildDiagnosticRow('Notificações de Pedido', _hasNotifications, Icons.notifications_active_rounded, isDark, isLast: true),
                    ],
                  ),
            ),

            const SizedBox(height: 32),

            // 👉 2. BENTO BOX: CONTA (COM EDIÇÃO INLINE INTELIGENTE) - UX #2 & #3
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, 
              children: [
                Text('Detalhes da Conta', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: isDark ? Colors.grey[500] : const Color(0xFF64748B), letterSpacing: 0.2)),
                // 👉 Lápis de edição geral aqui no cabeçalho
                InkWell(onTap: () => _showEditModal(), borderRadius: BorderRadius.circular(8), child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.edit_rounded, color: isDark ? Colors.grey[600] : Colors.grey[400], size: 20))),
              ]
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: isDark ? const Color(0xFF1A1D24) : Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 8))]),
              child: Column(
                children: [
                  _buildBentoRow('WhatsApp', _telefone, Icons.phone_rounded, isDark, fNode: _focusTelefone),
                  _buildBentoRow('Placa da Moto', _placa, Icons.pin_rounded, isDark, fNode: _focusPlaca),
                  _buildBentoRow('Cor da Moto', _corMoto, Icons.palette_rounded, isDark, isLast: true, fNode: _focusCor),
                ],
              ),
            ),
            
            const SizedBox(height: 64),

            // 👉 FOOTER SHOREBIRD: VERSÃO + PATCH OTA (PREMIUM DESIGN) - DNA #4
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Opacity(opacity: isDark ? 0.3 : 0.4, child: Image.asset('assets/logo.png', height: 26, width: 26)),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2F36) : Colors.grey.shade100, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200)),
                  child: Row(
                    children: [
                      Text('v$_appVersion', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: isDark ? Colors.grey[400] : Colors.grey[700], letterSpacing: 0.5)),
                      Container(margin: const EdgeInsets.symmetric(horizontal: 8), width: 1, height: 12, color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                      Text('Patch $_otaPatchVersion', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFFF28C38), letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticRow(String title, bool isOk, IconData icon, bool isDark, {bool isLast = false}) {
    final statusColor = isOk ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final statusIcon = isOk ? Icons.check_circle_rounded : Icons.error_rounded;
    final statusText = isOk ? 'Tudo certo' : 'Requer Atenção';
    return InkWell(
      onTap: isOk ? null : _openSettings, 
      borderRadius: BorderRadius.circular(24),
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: isOk ? (isDark ? const Color(0xFF22252D) : const Color(0xFFF8FAFC)) : statusColor.withOpacity(0.08), borderRadius: BorderRadius.circular(24), border: isOk ? null : Border.all(color: statusColor.withOpacity(0.2), width: 1)),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: isDark ? Colors.grey[500] : Colors.grey[500], size: 18)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontSize: 15, color: isDark ? Colors.white : const Color(0xFF0F172A), fontWeight: FontWeight.w700, letterSpacing: -0.3)), const SizedBox(height: 4), Row(children: [Icon(statusIcon, color: statusColor, size: 14), const SizedBox(width: 4), Text(statusText, style: TextStyle(fontSize: 13, color: statusColor, fontWeight: FontWeight.w800))])])),
            if (!isOk) Icon(Icons.arrow_forward_ios_rounded, color: statusColor, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildBentoRow(String title, String value, IconData icon, bool isDark, {bool isLast = false, FocusNode? fNode}) {
    final isEmpty = value.isEmpty || value.contains('Adicionar');
    final displayValue = isEmpty ? 'Adicionar ${title.toLowerCase()}' : value;
    final valueTextColor = isEmpty ? (isDark ? Colors.grey[600] : Colors.grey[400]) : (isDark ? Colors.white : const Color(0xFF0F172A));
    
    return InkWell(
      // 👉 MÁGICA #3: Clicou na linha, abre o modal focado naquele campo!
      onTap: () => _showEditModal(targetFocus: fNode),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: isDark ? const Color(0xFF22252D) : const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(24)),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: isDark ? Colors.grey[600] : Colors.grey[400], size: 18)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[600] : Colors.grey[500], fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(displayValue, style: TextStyle(fontSize: 16, color: valueTextColor, fontWeight: isEmpty ? FontWeight.w500 : FontWeight.w800, letterSpacing: -0.3)),
                ],
              ),
            ),
            // Ícone de seta sutil pra indicar que é clicável
            Icon(Icons.arrow_forward_ios_rounded, color: isDark ? Colors.grey[800] : Colors.grey[300], size: 12),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    HapticFeedback.heavyImpact();
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1D24) : Colors.white,
        title: Text('Sair da Conta', style: TextStyle(fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A))),
        content: Text('Tem certeza que deseja desconectar? Suas corridas pararão de ser rastreadas pelo radar.', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontWeight: FontWeight.w500)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)), actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontWeight: FontWeight.w700))),
          ElevatedButton(onPressed: () { Navigator.pop(ctx); _onLogout(context); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('Sair Agora', style: TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }
}

// FORMATADORES MANTIDOS
class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    String formatted = '';
    for (int i = 0; i < digits.length; i++) {
      if (i == 0) formatted += '(';
      if (i == 2) formatted += ') ';
      if (i == 7) formatted += '-';
      formatted += digits[i];
    }
    if (formatted.length > 15) formatted = formatted.substring(0, 15);
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(text: newValue.text.toUpperCase(), selection: newValue.selection);
  }
}