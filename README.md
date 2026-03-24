# 🥩 Ao Gosto | Delivery Engine

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" />
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" />
</p>

Aplicativo de logística e roteirização de alta performance construído para a operação de entregas da **Ao Gosto**. Desenhado com foco absoluto na experiência do entregador (UX), operação em tempo real e eficiência de rotas.

## 🚀 O Problema Resolvido
Sistemas de delivery genéricos não oferecem o nível de controle SLA e roteirização dinâmica que uma operação premium de carnes exige. Este aplicativo elimina a fricção entre a central de despacho e o entregador, automatizando a atribuição de rotas via QR Code e oferecendo telemetria em tempo real.

## ✨ Features de Nível Enterprise

* **SLA Dashboard (Tempo Real):** O aplicativo escuta o Firestore via Stream e altera dinamicamente a interface. Pedidos com risco de atraso ganham bordas neon (Laranja > 1h / Vermelho > 2h), criando um senso de urgência visual instintivo.
* **Smart Routing (Zero Cost):** Algoritmo de roteirização múltipla que agrupa até 10 endereços pendentes e injeta como *Waypoints* diretamente no Google Maps via URL Scheme, gerando a rota mais rápida sem custos de API de terceiros.
* **Live GPS Tracking:** Mapa nativo (OpenStreetMap + CartoDB Dark Theme) com pin pulsante do entregador. Inclui "Visão Estratégica" (`FitBounds`) que calcula a caixa delimitadora (`BoundingBox`) para enquadrar o motoboy e todos os pedidos simultaneamente.
* **Scanner QR Code Atômico:** Leitor de comandas embutido com extração inteligente de Regex/URI. Possui feedback háptico (vibração), animações de estado (Laser/Pulse) e sistema de *Debounce* para evitar múltiplas leituras.
* **Comunicação 1-Click:** Geração dinâmica de links de WhatsApp com mensagens pré-formatadas utilizando o nome do cliente e do entregador, acelerando o contato na porta da entrega.

## 🛠️ Arquitetura e Stack

* **Framework:** Flutter (Mobile Nativo)
* **Baas:** Firebase (Firestore para Real-time Database, Storage para Mídias)
* **Gerenciamento de Estado:** State Stateful Management com Streams Assíncronas
* **Geolocalização:** `geolocator` para tracking de hardware e `flutter_map` para renderização de tiles.
* **Cache Local:** `shared_preferences` para resiliência offline de dados estáticos do perfil.

## 👨‍💻 Autor
Desenvolvido por ** Raiky Câmara ** ([@raikyrk](https://github.com/raikyrk)) **Guilherme Trajano** ([@trajanoo93](https://github.com/trajanoo93)).