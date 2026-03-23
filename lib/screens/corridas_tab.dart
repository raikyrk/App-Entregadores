import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class CorridasTab extends StatefulWidget {
  final String entregadorName;

  const CorridasTab({super.key, required this.entregadorName});

  @override
  State<CorridasTab> createState() => _CorridasTabState();
}

class _CorridasTabState extends State<CorridasTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _liveTimer; 

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) HapticFeedback.selectionClick();
    });

    // Timer para o SLA atualizar na tela a cada minuto
    _liveTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _finalizarEntrega(String pedidoId) async {
    HapticFeedback.heavyImpact();
    try {
      await FirebaseFirestore.instance.collection('pedidos').doc(pedidoId).update({
        'status': 'Concluído',
        'data_entrega': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 12),
              Text('Entrega finalizada com sucesso!', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    } catch (e) {
      debugPrint('Erro ao finalizar entrega: $e');
    }
  }

  Future<void> _openWhatsApp(String phoneRaw, String clienteNome, String pedidoId) async {
    if (phoneRaw.isEmpty || phoneRaw.contains('Não informado')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Telefone não informado.')));
      return;
    }

    final phone = phoneRaw.replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) return;
    
    final formattedPhone = phone.startsWith('55') ? phone : '55$phone';
    final primeiroNome = clienteNome.split(' ').first;
    final message = "Olá $primeiroNome, sou o ${widget.entregadorName}, parceiro da Ao Gosto. 🥩\n\nEstou a caminho com o seu pedido *#$pedidoId*!";
    final encodedMessage = Uri.encodeComponent(message);
    
    final url = Uri.parse('whatsapp://send?phone=$formattedPhone&text=$encodedMessage');
    final fallbackUrl = Uri.parse('https://wa.me/$formattedPhone?text=$encodedMessage');

    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _abrirRotaMultipla(List<String> enderecosBrutos) async {
    HapticFeedback.heavyImpact();

    final enderecosValidos = enderecosBrutos
        .where((e) => e.isNotEmpty && !e.contains('Não informado') && !e.contains('nuvem'))
        .take(10)
        .toList();

    if (enderecosValidos.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('É necessário ter endereços válidos para agrupar.')));
      return;
    }

    final destination = Uri.encodeComponent(enderecosValidos.last);
    final waypoints = enderecosValidos.take(enderecosValidos.length - 1).map((e) => Uri.encodeComponent(e)).join('%7C');
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$destination&waypoints=$waypoints');

    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir o Google Maps.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao abrir navegação.')));
    }
  }

  void _showMapOptions(BuildContext context, String endereco) {
    if (endereco.isEmpty || endereco.contains('Não informado') || endereco.contains('nuvem')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Endereço inválido.')));
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1D24) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          ),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(margin: const EdgeInsets.only(bottom: 24), width: 48, height: 5, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(3)))),
              Text('Iniciar Rota', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A), letterSpacing: -0.5), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              _buildMapOptionCard(context, 'Google Maps', Icons.map_rounded, const Color(0xFF4285F4), () => _openGoogleMaps(endereco), isDark),
              const SizedBox(height: 16),
              _buildMapOptionCard(context, 'Waze', Icons.navigation_rounded, const Color(0xFF33CCFF), () => _openWaze(endereco), isDark),
              const SizedBox(height: 16),
            ],
          ),
        );
      }
    );
  }

  Widget _buildMapOptionCard(BuildContext ctx, String title, IconData icon, Color iconColor, VoidCallback onTap, bool isDark) {
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

  Future<void> _openGoogleMaps(String endereco) async {
    final enc = Uri.encodeComponent(endereco);
    final nav = Uri.parse('google.navigation:q=$enc');
    final fallback = Uri.parse('https://www.google.com/maps/search/?api=1&query=$enc');
    try {
      if (!await launchUrl(nav, mode: LaunchMode.externalApplication)) await launchUrl(fallback, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _openWaze(String endereco) async {
    final enc = Uri.encodeComponent(endereco);
    final waze = Uri.parse('waze://?q=$enc&navigate=yes');
    final fallback = Uri.parse('https://www.waze.com/ul?q=$enc');
    try {
      if (!await launchUrl(waze, mode: LaunchMode.externalApplication)) await launchUrl(fallback, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: Colors.transparent, 
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Minhas Corridas', style: TextStyle(fontSize: 28, color: textColor, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Container(
            height: 54,
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1D24) : const Color(0xFFF1F5F9), 
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.transparent)
            ),
            child: TabBar(
              controller: _tabController,
              padding: const EdgeInsets.all(6), 
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(24), 
                color: isDark ? const Color(0xFF2C2F36) : Colors.white, 
                boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))]
              ),
              labelColor: isDark ? Colors.white : const Color(0xFF0F172A),
              unselectedLabelColor: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.3),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              splashBorderRadius: BorderRadius.circular(24),
              tabs: const [Tab(text: 'Em Andamento'), Tab(text: 'Concluídas')],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const BouncingScrollPhysics(),
        children: [
          _buildListaCorridas(isDark, isConcluida: false),
          _buildListaCorridas(isDark, isConcluida: true),
        ],
      ),
    );
  }

  Widget _buildListaCorridas(bool isDark, {required bool isConcluida}) {
    final query = FirebaseFirestore.instance
        .collection('pedidos')
        .where('entregador', isEqualTo: widget.entregadorName);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Erro de conexão.', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFFF28C38)));

        final hoje = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

        final corridas = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status']?.toString().toLowerCase() ?? '';
          
          if (isConcluida) {
            bool isDone = status.contains('conclu') || status.contains('entregue');
            if (!isDone) return false;

            DateTime? dataPedido;
            if (data['data_entrega'] != null) {
              dataPedido = data['data_entrega'] is Timestamp ? (data['data_entrega'] as Timestamp).toDate() : DateTime.tryParse(data['data_entrega'].toString());
            } else if (data['timestamp'] != null) {
              dataPedido = data['timestamp'] is Timestamp ? (data['timestamp'] as Timestamp).toDate() : DateTime.tryParse(data['timestamp'].toString());
            }
            
            if (dataPedido != null) {
               return dataPedido.isAfter(hoje.subtract(const Duration(seconds: 1)));
            }
            return false;
          } else {
            return status.contains('saiu') || status.contains('andamento');
          }
        }).toList();

        if (corridas.isEmpty) return _buildEmptyState(isDark, isConcluida);

        if (!isConcluida) {
          corridas.sort((a, b) {
             final tA = (a.data() as Map<String, dynamic>)['timestamp'];
             final tB = (b.data() as Map<String, dynamic>)['timestamp'];
             if (tA == null || tB == null) return 0;
             return tA.toString().compareTo(tB.toString());
          });
        }

        List<String> todosEnderecos = [];

        return Column(
          children: [
            // BANNER DE OTIMIZAÇÃO DE ROTA
            if (!isConcluida && corridas.length >= 2)
              Container(
                margin: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1D24) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _abrirRotaMultipla(todosEnderecos),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFFF28C38), Color(0xFFE87A24)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: const Color(0xFFF28C38).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
                            ),
                            child: const Icon(Icons.route_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Rotas Otimizadas', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                                Text('${corridas.length} entregas agrupadas', style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 16, color: isDark ? const Color(0xFF64748B) : const Color(0xFFCBD5E1)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // A LISTA DE CARDS
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 120), 
                physics: const BouncingScrollPhysics(),
                itemCount: corridas.length,
                itemBuilder: (context, index) {
                  final doc = corridas[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final id = doc.id;

                  String enderecoText = 'Endereço não informado';
                  if (data['endereco'] is String) {
                    enderecoText = data['endereco'];
                  } else if (data['endereco'] is Map) {
                    final map = data['endereco'] as Map<String, dynamic>;
                    final rua = map['rua'] ?? map['logradouro'] ?? '';
                    final numero = map['numero'] ?? '';
                    final bairro = map['bairro'] ?? '';
                    final cidade = map['cidade'] ?? 'Belo Horizonte'; 
                    
                    enderecoText = '$rua, $numero';
                    if (bairro.isNotEmpty) enderecoText += ' - $bairro';
                    enderecoText += ', $cidade'; 
                    enderecoText = enderecoText.replaceAll(RegExp(r'^, | - $'), '').trim();
                    if (enderecoText.isEmpty || enderecoText == ',') enderecoText = 'Endereço na nuvem';
                  }

                  if (!isConcluida) todosEnderecos.add(enderecoText);

                  String clienteText = 'Cliente Ao Gosto';
                  String telefoneText = '';
                  
                  if (data['cliente'] is String) {
                    clienteText = data['cliente'];
                  } else if (data['nome_cliente'] is String) {
                    clienteText = data['nome_cliente'];
                  } else if (data['cliente'] is Map) {
                    final map = data['cliente'] as Map<String, dynamic>;
                    clienteText = map['nome'] ?? 'Cliente Ao Gosto';
                    telefoneText = map['telefone'] ?? map['celular'] ?? '';
                  }
                  if (telefoneText.isEmpty) telefoneText = data['telefone'] ?? '';

                  // 👉 EXTRAÇÃO DO DEADLINE INTELIGENTE (Agendado vs Imediato)
                  DateTime? limiteEntrega;
                  bool isAgendado = false;
                  String janelaTexto = '';

                  if (data['agendamento'] is Map && (data['agendamento']['is_agendado'] == true || data['agendamento']['janela_texto'] != null)) {
                    isAgendado = true;
                    janelaTexto = data['agendamento']['janela_texto']?.toString() ?? '';
                    
                    DateTime? dataBaseAgendamento;
                    if (data['agendamento']['data'] != null) {
                       final agenData = data['agendamento']['data'];
                       dataBaseAgendamento = agenData is Timestamp ? agenData.toDate() : DateTime.tryParse(agenData.toString());
                    }
                    
                    if (dataBaseAgendamento != null && janelaTexto.contains('-')) {
                      // Extrai o limite máximo da janela de entrega (Ex: 12:00 - 15:00 -> pega o 15:00)
                      try {
                          final horaFimStr = janelaTexto.split('-').last.trim(); 
                          final horaMinuto = horaFimStr.split(':');
                          final hora = int.parse(horaMinuto[0]);
                          final minuto = int.parse(horaMinuto[1]);
                          
                          limiteEntrega = DateTime(dataBaseAgendamento.year, dataBaseAgendamento.month, dataBaseAgendamento.day, hora, minuto);
                      } catch (_) {
                          limiteEntrega = dataBaseAgendamento; 
                      }
                    } else {
                      limiteEntrega = dataBaseAgendamento;
                    }
                  } 
                  
                  // Se for Imediato (Pra Agora)
                  if (!isAgendado) {
                    DateTime? criacao;
                    if (data['timestamp'] != null) {
                      criacao = data['timestamp'] is Timestamp ? (data['timestamp'] as Timestamp).toDate() : DateTime.tryParse(data['timestamp'].toString());
                    } else if (data['created_at'] != null) {
                      criacao = data['created_at'] is Timestamp ? (data['created_at'] as Timestamp).toDate() : DateTime.tryParse(data['created_at'].toString());
                    }
                    
                    // O limite da corrida imediata é 1 hora após a aprovação
                    if (criacao != null) {
                        limiteEntrega = criacao.add(const Duration(hours: 1)); 
                    }
                  }

                  // 👉 O DETECTOR DE CARVÃO
                  int quantidadeCarvao = 0;
                  if (data['itens'] is List) {
                    final itens = data['itens'] as List<dynamic>;
                    for (var item in itens) {
                      if (item is Map) {
                        final nomeItem = item['nome']?.toString().toLowerCase() ?? '';
                        if (nomeItem.contains('carvao') || nomeItem.contains('carvão')) {
                          quantidadeCarvao += (item['quantidade'] as num?)?.toInt() ?? 1;
                        }
                      }
                    }
                  }
                  
                  return _buildCorridaCard(id, clienteText, enderecoText, telefoneText, limiteEntrega, isConcluida, quantidadeCarvao, isDark);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCorridaCard(String id, String cliente, String endereco, String telefone, DateTime? limiteEntrega, bool isConcluida, int quantidadeCarvao, bool isDark) {
    Color slaColor = Colors.transparent;
    Color slaBgColor = Colors.transparent;
    String slaText = '';
    
    // 👉 CRONÔMETRO DE SLA (Versão Logística Big Tech)
    if (!isConcluida && limiteEntrega != null) {
      final agora = DateTime.now();
      
      if (agora.isAfter(limiteEntrega)) {
        final atraso = agora.difference(limiteEntrega);
        slaColor = const Color(0xFFEF4444); 
        slaBgColor = const Color(0xFFEF4444).withOpacity(0.12);
        
        if (atraso.inHours > 0) {
            slaText = 'Atrasado: ${atraso.inHours}h ${atraso.inMinutes.remainder(60)}m';
        } else {
            slaText = 'Atrasado: ${atraso.inMinutes}m';
        }
      } else {
        final tempoRestante = limiteEntrega.difference(agora);
        if (tempoRestante.inMinutes <= 45) { 
            slaColor = const Color(0xFFF59E0B); 
            slaBgColor = const Color(0xFFF59E0B).withOpacity(0.12);
            
            if (tempoRestante.inHours > 0) {
              slaText = 'Vence em: ${tempoRestante.inHours}h ${tempoRestante.inMinutes.remainder(60)}m';
            } else {
              slaText = 'Vence em: ${tempoRestante.inMinutes}m';
            }
        }
      }
    }

    final hasSlaAlert = slaColor != Colors.transparent;
    final cardBgColor = isDark ? const Color(0xFF1A1D24) : Colors.white;

    String clienteFormatado = cliente.isNotEmpty 
        ? cliente.split(' ').map((p) => p.isNotEmpty ? '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}' : '').join(' ')
        : 'Cliente';

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(32),
        border: hasSlaAlert ? Border.all(color: slaColor.withOpacity(0.4), width: 1.5) : null,
        boxShadow: [
          BoxShadow(
            color: hasSlaAlert ? slaColor.withOpacity(0.15) : const Color(0xFF0F172A).withOpacity(0.04), 
            blurRadius: 24, 
            offset: const Offset(0, 10)
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 👉 CABEÇALHO DO CARD (Blindado contra Overflows)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start, // Mantém tudo alinhado ao topo
              children: [
                // ESQUERDA: ID + SLA (Envolvidos em Expanded para ceder espaço se precisar)
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2F36) : const Color(0xFFF1F5F9), 
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '#$id',
                          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF334155), fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
                        ),
                      ),
                      if (hasSlaAlert) ...[
                        const SizedBox(width: 8),
                        // FLEXIBLE: Permite que o alerta diminua e use "..." se o texto for gigante
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: slaBgColor, borderRadius: BorderRadius.circular(10)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min, // Não ocupa espaço à toa
                              children: [
                                Icon(Icons.timer_rounded, size: 14, color: slaColor),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    slaText, 
                                    style: TextStyle(color: slaColor, fontWeight: FontWeight.w800, fontSize: 12),
                                    overflow: TextOverflow.ellipsis, // A MÁGICA CONTRA O OVERFLOW
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(width: 12), // Respiro entre a esquerda e a direita
                
                // DIREITA: ALERTA DE CARVÃO (Sempre visível e protegido)
                if (quantidadeCarvao > 0 && !isConcluida)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_fire_department_rounded, color: Color(0xFFEF4444), size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Carvão x$quantidadeCarvao', 
                          style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else if (isConcluida)
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20)
                else 
                  const SizedBox.shrink(), 
              ],
            ),
          ),
          
          // NOME E ENDEREÇO
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(clienteFormatado, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A), letterSpacing: -0.5)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.location_on_rounded, size: 16, color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(endereco, style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), height: 1.4, fontWeight: FontWeight.w500))),
              ],
            ),
          ),
          
          // BOTÕES DE AÇÃO
          if (!isConcluida) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => _openWhatsApp(telefone, cliente, id),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 52,
                      width: 52,
                      decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                      child: const Center(child: FaIcon(FontAwesomeIcons.whatsapp, color: Color(0xFF25D366), size: 22)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () => _showMapOptions(context, endereco),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 52,
                      width: 52,
                      decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2F36) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(16)),
                      child: Center(child: Icon(Icons.map_rounded, size: 22, color: isDark ? Colors.white : const Color(0xFF334155))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _finalizarEntrega(id),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFF28C38), Color(0xFFE87A24)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: const Color(0xFFF28C38).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('Entregue', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
             const SizedBox(height: 20),
          ]
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, bool isConcluida) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isConcluida ? Icons.task_alt_rounded : Icons.inbox_rounded, 
              size: 80, 
              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1) 
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isConcluida ? 'Nenhuma corrida' : 'Tudo limpo!', 
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A), letterSpacing: -0.5)
          ),
          const SizedBox(height: 12),
          Text(
            isConcluida ? 'As entregas do dia aparecerão aqui.' : 'Aguardando novas chamadas.', 
            style: TextStyle(fontSize: 16, color: const Color(0xFF64748B), fontWeight: FontWeight.w500)
          ),
        ],
      ),
    );
  }
}