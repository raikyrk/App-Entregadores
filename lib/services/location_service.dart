// lib/services/location_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart'; // Import mantido!

class LocationService {
  static bool isTracking = false;
  
  static StreamSubscription<Position>? _positionStream;
  static Position? _lastPosition; 
  static Position? _lastSavedPosition; 

  // 👉 ATENÇÃO: Passando o BuildContext aqui (igual arrumamos no Dashboard)
  static Future<bool> startTracking(BuildContext context) async {
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

    // 👉 3. A MÁGICA EM AÇÃO: Pedindo as permissões vitais para o Android 13+
    if (defaultTargetPlatform == TargetPlatform.android) {
      
      // Pede para mostrar a notificação (Evita o crash silencioso)
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }

      // Pede para o Android NÃO matar o app por bateria
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        var status = await Permission.ignoreBatteryOptimizations.request();
        
        // Se o usuário negar, mostra aquele nosso alerta educacional
        if (!status.isGranted && context.mounted) {
          final prefs = await SharedPreferences.getInstance();
          bool jaMostrouAviso = prefs.getBool('aviso_bateria_mostrado') ?? false;

          if (!jaMostrouAviso) {
            await prefs.setBool('aviso_bateria_mostrado', true);
            _mostrarAvisoBateriaManual(context);
          }
        }
      }
    }

    // Restante do seu código original...
    final prefs = await SharedPreferences.getInstance();
    final entregadorNome = prefs.getString('entregador'); 
    
    if (entregadorNome == null || entregadorNome.isEmpty) {
      debugPrint('⚠️ Erro: Nome do entregador não encontrado na memória local!');
      return false;
    }

    isTracking = true;

    String docId = entregadorNome; 
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

    // 4. Configuração do Foreground Service (Para não morrer no bolso)
    late LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, 
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Buscando rotas e enviando localização para a central...",
          notificationTitle: "Go! Entregas: Você está On-line",
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 5, 
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true, 
      );
    } else {
      locationSettings = const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5); 
    }

    // 5. O Listener que salva as coordenadas no Firestore
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) async {
      _lastPosition = position; 

      if (_lastSavedPosition != null) {
        double distance = Geolocator.distanceBetween(
            _lastSavedPosition!.latitude, _lastSavedPosition!.longitude,
            position.latitude, position.longitude);
        
        if (distance < 5.0) return; 
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

        _lastSavedPosition = position; 

      } catch (e) {
        debugPrint('Erro no sync do Firebase via Stream: $e');
      }
    });

    return true; 
  }

  static void stopTracking() async {
    isTracking = false;
    _positionStream?.cancel();
    _lastPosition = null;
    _lastSavedPosition = null; 

    try {
      final prefs = await SharedPreferences.getInstance();
      final entregadorNome = prefs.getString('entregador');
      
      if (entregadorNome != null && entregadorNome.isNotEmpty) {
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

  // Alerta extra caso ele recuse a permissão automática
  static void _mostrarAvisoBateriaManual(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Atenção, Entregador!"),
          content: const Text(
            "Para o GPS não desligar quando você colocar o celular no bolso, você precisa tirar a restrição de bateria do nosso aplicativo.\n\n"
            "Na próxima tela, vá em 'Bateria' e escolha 'Não Restrito' (ou 'Sem Restrição')."
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings(); 
              },
              child: const Text("Entendi, vamos lá!"),
            ),
          ],
        );
      },
    );
  }
}