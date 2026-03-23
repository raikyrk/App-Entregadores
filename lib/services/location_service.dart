import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  static StreamSubscription<Position>? _positionStream;
  static bool isTracking = false;

  /// Inicia o rastreio blindado e envia para o Firestore
  static Future<void> startTracking() async {
    if (isTracking) return;

    bool serviceEnabled;
    LocationPermission permission;

    // 1. Verifica se o GPS do celular está ligado fisicamente
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('GPS Desativado no aparelho.');
      return;
    }

    // 2. Verifica e pede permissões
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Permissão de GPS negada.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Permissões negadas permanentemente.');
      return;
    }

    // Pega o nome do entregador logado para saber em qual documento salvar
    final prefs = await SharedPreferences.getInstance();
    final entregadorNome = prefs.getString('entregador') ?? 'Desconhecido';

    // 3. Configura o "Foreground Service" (A notificação que mantém o app vivo)
    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Só atualiza se ele andar 10 metros (poupa bateria e Firestore)
        forceLocationManager: true,
        // Isso aqui é a mágica que impede o Android de matar o App no bolso!
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Ao Gosto Delivery rodando em segundo plano.",
          notificationTitle: "Rastreio Ativo",
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 10,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true, // Mostra a pílula azul no iPhone
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }

    isTracking = true;
    debugPrint('🚀 GPS DE AÇO INICIADO PARA: $entregadorNome');

    // 4. Começa a escutar as coordenadas e enviar pro Firestore em Tempo Real
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
          
      debugPrint('📍 Nova coordenada: ${position.latitude}, ${position.longitude} (Heading: ${position.heading})');

      // 🔥 Manda pro Firestore! O seu React na web vai ver isso instantaneamente.
      FirebaseFirestore.instance.collection('entregadores_ativos').doc(entregadorNome).set({
        'lat': position.latitude,
        'lng': position.longitude,
        'heading': position.heading, // Usado para girar o ícone da moto lá no mapa do cliente!
        'speed': position.speed,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); // merge: true evita apagar outros dados que já estejam lá
      
    });
  }

  /// Para o rastreio (Ideal para quando ele termina o expediente)
  static void stopTracking() {
    if (_positionStream != null) {
      _positionStream!.cancel();
      _positionStream = null;
    }
    isTracking = false;
    debugPrint('🛑 GPS DE AÇO DESLIGADO.');
  }
}