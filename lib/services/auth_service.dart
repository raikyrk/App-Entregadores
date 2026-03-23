import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;

class AuthService {
  /// Validação nível PRO: Busca direta pelo ID do Documento (O(1) - Ultra Rápido)
  static Future<Map<String, dynamic>> login(String pin) async {
    try {
      // Como o seu PIN é o próprio ID do documento, fazemos a leitura direta!
      final docSnapshot = await FirebaseFirestore.instance
          .collection('entregadores')
          .doc(pin) // Procura cirurgicamente o documento com o ID digitado (ex: '0001')
          .get();

      if (docSnapshot.exists) {
        final dados = docSnapshot.data()!;
        
        // Pega o nome do entregador exatamente como está na sua tabela
        final nomeEntregador = dados['nome'] ?? 'Entregador Ao Gosto';
        
        // Salva a sessão localmente
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('entregador', nomeEntregador);
        
        // Bônus: Já que você tem a informação do CD na tabela, 
        // vamos salvar no cache também para usar futuramente!
        await prefs.setString('cd_entregador', dados['CD'] ?? 'N/A');
        
        return {'success': true, 'nome': nomeEntregador};
      } else {
        // Se o documento com esse ID não existe, o PIN está errado
        return {'success': false, 'message': 'PIN incorreto. Entregador não encontrado.'};
      }
    } catch (e) {
      developer.log('Erro no login via Firestore: $e');
      return {'success': false, 'message': 'Erro de conexão com o banco de dados.'};
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('entregador');
    await prefs.remove('cd_entregador');
  }
}