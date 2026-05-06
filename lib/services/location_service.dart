// lib/services/location_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  static bool isTracking = false;
  
  static StreamSubscription<Position>? _positionStream;
  // 👉 Timer removido daqui! O disparo agora é nativo.
  static Position? _lastPosition; 
  static Position? _lastSavedPosition; // 👉 VARIÁVEL DE CONTROLE MANTIDA

  static Future<bool> startTracking() async {
    if (isTracking) return true;

    // 1. O GPS físico do celular está ligado?
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return false; 
    }

    // 2. O App tem permissão de localização?
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false; 
    }

    // Pega o nome salvo no login
    final prefs = await SharedPreferences.getInstance();
    final entregadorNome = prefs.getString('entregador'); 
    
    if (entregadorNome == null || entregadorNome.isEmpty) {
      debugPrint('⚠️ Erro: Nome do entregador não encontrado na memória local!');
      return false;
    }

    isTracking = true;

    // 👉 BUSCA INTELIGENTE: Pega o ID real do documento dele no Firestore antes de iniciar
    String docId = entregadorNome; // Fallback
    try {
      final query = await FirebaseFirestore.instance
          .collection('entregadores')
          .where('nome', isEqualTo: entregadorNome)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        docId = query.docs.first.id;
      }
    } catch(e) {
      debugPrint('Erro ao buscar ID do documento do entregador: $e');
    }

    try {
      _lastPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      debugPrint('Aviso: GPS não respondeu de imediato.');
    }

    // 3. Configuração do Foreground Service (Para não morrer no bolso)
    late LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // 👉 TRAVA 1: O Android só acorda a Stream a cada 10 metros!
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Buscando rotas e enviando localização para a central...",
          notificationTitle: "Ao Gosto: Você está On-line",
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 10, // 👉 TRAVA 1: O iOS só acorda a Stream a cada 10 metros!
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true, 
      );
    } else {
      locationSettings = const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
    }

    // 4. 👉 A GRANDE MUDANÇA: O Listener que salva as coordenadas no Firestore do Marcelão (Sem Timer)
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) async {
      _lastPosition = position; 

      // 👉 TRAVA 2 (O FILTRO SALVADOR DE DINHEIRO)
      // Protege contra pulos falsos do GPS (drift). Se for < 5 metros, aborta.
      if (_lastSavedPosition != null) {
        double distance = Geolocator.distanceBetween(
            _lastSavedPosition!.latitude, _lastSavedPosition!.longitude,
            position.latitude, position.longitude);
        
        if (distance < 5.0) return; // Sai fora e economiza o Write!
      }

      try {
        await FirebaseFirestore.instance.collection('entregadores').doc(docId).set({
          'nome': entregadorNome, 
          'is_online': true,
          'localizacao_atual': {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'heading': position.heading, 
            'velocidade': position.speed * 3.6,     
            'last_update': FieldValue.serverTimestamp(), 
          }
        }, SetOptions(merge: true));

        _lastSavedPosition = position; // 👉 Atualiza a última posição salva com sucesso

      } catch (e) {
        debugPrint('Erro no sync do Firebase via Stream: $e');
      }
    });

    return true; 
  }

  static void stopTracking() async {
    isTracking = false;
    _positionStream?.cancel();
    // 👉 Chamada do Timer removida daqui
    _lastPosition = null;
    _lastSavedPosition = null; // Limpa a memória de posição ao deslogar

    try {
      final prefs = await SharedPreferences.getInstance();
      final entregadorNome = prefs.getString('entregador');
      
      if (entregadorNome != null && entregadorNome.isNotEmpty) {
        // Encontra o documento dele para setar offline
        final query = await FirebaseFirestore.instance
            .collection('entregadores')
            .where('nome', isEqualTo: entregadorNome)
            .limit(1)
            .get();
            
        if (query.docs.isNotEmpty) {
          await query.docs.first.reference.set({'is_online': false}, SetOptions(merge: true));
        }
      }
    } catch (e) {
      debugPrint('Erro ao sair do radar no Firebase: $e');
    }
  }
}