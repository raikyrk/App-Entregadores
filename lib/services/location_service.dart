import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  static bool isTracking = false;
  
  // 👉 AS TRÊS PEÇAS DA NOVA ARQUITETURA
  static StreamSubscription<Position>? _positionStream;
  static Timer? _syncTimer; // O Maestro Inquebrável
  static Position? _lastPosition; // A Memória Cache

  static Future<void> startTracking() async {
    if (isTracking) return;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    final prefs = await SharedPreferences.getInstance();
    final entregadorName = prefs.getString('entregador'); 
    if (entregadorName == null || entregadorName.isEmpty) return;

    isTracking = true;

    // 1. O Ouvinte Silencioso: Atualiza APENAS a variável local (Custo zero de Firebase)
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, 
      ),
    ).listen((Position position) {
      _lastPosition = position; 
    });

    // 2. O Relógio Suíço: Acorda EXATAMENTE a cada 10 segundos
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      // Se já recebemos alguma posição do satélite, disparamos pro banco
      if (_lastPosition != null) {
        try {
          await FirebaseFirestore.instance.collection('entregadores_ativos').doc(entregadorName).set({
            'lat': _lastPosition!.latitude,
            'lng': _lastPosition!.longitude,
            'heading': _lastPosition!.heading, 
            'speed': _lastPosition!.speed,     
            'timestamp': FieldValue.serverTimestamp(), 
          }, SetOptions(merge: true));
          
          debugPrint('🚀 [TIMER 10s] Coordenada cravada no Firebase!');
        } catch (e) {
          debugPrint('Erro no timer de sync do Firebase: $e');
        }
      }
    });
  }

  static void stopTracking() async {
    isTracking = false;
    
    // Mata os dois processos!
    _positionStream?.cancel();
    _syncTimer?.cancel();
    _lastPosition = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final entregadorName = prefs.getString('entregador');
      
      if (entregadorName != null && entregadorName.isNotEmpty) {
        await FirebaseFirestore.instance.collection('entregadores_ativos').doc(entregadorName).delete();
        debugPrint('🛑 Rastreador e Timer Desligados. Limpo da base de dados.');
      }
    } catch (e) {
      debugPrint('Erro ao sair do radar no Firebase: $e');
    }
  }
}