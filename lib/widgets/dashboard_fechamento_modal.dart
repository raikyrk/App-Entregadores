import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DashboardFechamentoModal extends StatefulWidget {
  final double totalMaquininha;
  final double saldoDoPeriodo;
  final String entregadorName;
  final VoidCallback onSuccess;
  final VoidCallback onSkip;

  const DashboardFechamentoModal({
    super.key,
    required this.totalMaquininha,
    required this.saldoDoPeriodo,
    required this.entregadorName,
    required this.onSuccess,
    required this.onSkip,
  });

  static void show(
    BuildContext context, {
    required double totalMaquininha,
    required double saldoDoPeriodo,
    required String entregadorName,
    required VoidCallback onSuccess,
    required VoidCallback onSkip,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DashboardFechamentoModal(
        totalMaquininha: totalMaquininha,
        saldoDoPeriodo: saldoDoPeriodo,
        entregadorName: entregadorName,
        onSuccess: onSuccess,
        onSkip: onSkip,
      ),
    );
  }

  @override
  State<DashboardFechamentoModal> createState() => _DashboardFechamentoModalState();
}

class _DashboardFechamentoModalState extends State<DashboardFechamentoModal> {
  bool _isUploadingReceipt = false;

  Future<void> _processarComprovante(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: source, imageQuality: 70);

    if (photo == null) return;

    setState(() => _isUploadingReceipt = true);

    try {
      final entregador = widget.entregadorName;
      final hoje = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final ref = FirebaseStorage.instance
          .ref()
          .child('comprovantes_maquininha/$entregador/${hoje}_$timestamp.jpg');
      await ref.putFile(File(photo.path));
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('fechamentos').add({
        'entregador': entregador,
        'data_fechamento': FieldValue.serverTimestamp(),
        'comprovante_url': url,
        'ganhos_motoboy': widget.saldoDoPeriodo,
        'total_passado_maquininha': widget.totalMaquininha,
      });

      setState(() => _isUploadingReceipt = false);
      if (mounted) Navigator.pop(context);

      widget.onSuccess();
    } catch (e) {
      setState(() => _isUploadingReceipt = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF28C38).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFF28C38), size: 40),
            ),
            const SizedBox(height: 20),
            Text('Fim de Expediente',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 8),
            Text('Para ficar off-line, envie a foto dos comprovantes da maquininha com o resumo das vendas de hoje.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey.shade400)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.withOpacity(0.3))),
              child: Column(
                children: [
                  const Text('Valor esperado no comprovante:', style: TextStyle(color: Colors.amber)),
                  Text(formatoMoeda.format(widget.totalMaquininha),
                      style: const TextStyle(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            if (_isUploadingReceipt)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Color(0xFF10B981)),
                    SizedBox(height: 16),
                    Text('Enviando comprovante...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            else
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _processarComprovante(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_rounded, color: Colors.white),
                      label: const Text('Fotografar Comprovante',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _processarComprovante(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_rounded, color: Colors.grey),
                      label: const Text('Escolher da Galeria',
                          style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Colors.grey.shade800),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onSkip();
                    },
                    child: const Text('Estou sem a maquininha (Pular)', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}