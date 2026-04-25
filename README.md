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


============= ROADMAP GERAL ==================

Este aplicativo é a ferramenta de campo da nossa frota própria, responsável por roteirização, bipagem de pacotes, rastreamento GPS em tempo real e fechamento financeiro diário.

Leia com atenção antes de codar.

---

## 🛠️ Stack Tecnológico
* **Framework:** Flutter (Dart)
* **Backend (BaaS):** Firebase (Firestore, Storage)
* **Updates OTA:** Shorebird (Permite subir atualizações em background sem passar pelas lojas).
* **GPS & Background:** `geolocator`, `permission_handler`
* **QR Scanner:** `mobile_scanner`

---

## 📂 Arquitetura e Mapa de Arquivos Principais

O projeto não usa um gerenciador de estado complexo e engessado (como Redux), baseando-se bastante na reatividade em tempo real do próprio Firebase (`StreamBuilder`) e estados locais (`StatefulWidget`).

Os arquivos que você mais vai manipular estão divididos assim:

* `lib/screens/`
  * `dashboard_screen.dart`: A tela inicial (Home). Mostra o botão "Ficar Online", o saldo do dia, botão de scanner e navegação.
  * `corridas_tab.dart`: O Kanban do motoboy. Tem as abas "Em Andamento" e "Concluídas". É aqui que moram os cronômetros de SLA e os botões de ação (WhatsApp, Maps, Concluir).
  * `scanner_screen.dart`: A câmera. Lê o QR Code da nota fiscal e atualiza o Firestore amarrando o pedido ao entregador.
  * `profile_tab.dart`: Perfil do usuário. Contém o motor de **Diagnóstico de Saúde do App** (GPS, Notificações) e dados do veículo.
* `lib/services/`
  * `location_service.dart`: **O CORAÇÃO DO RASTREIO.** Inicia o Foreground Service no Android/iOS e envia a latitude/longitude pro Firestore a cada 10 segundos.

---

## 🧠 Lógicas de Negócios (Como o app pensa)

### 1. Fluxo de Corridas
O aplicativo **não cria** pedidos. Ele reage ao nosso sistema OMS e lê a coleção `pedidos` no Firestore.
* **Filtro de Visibilidade:** A tela `CorridasTab` só exibe os pedidos onde `entregador == nome_do_motoboy_logado` E o status não seja "Cancelado" ou "Concluído".
* **Associação (Scanner):** Ao ler o QR Code, o `scanner_screen.dart` faz um UPDATE no pedido: altera o status para `Saiu pra Entrega` e adiciona o nome do motoboy. Instantaneamente, o pedido pipoca na aba de corridas.

### 2. Lógica Financeira (O Saldo da Tela Inicial)
O "Saldo do Dia" que o entregador vê na tela inicial é a soma de duas coleções no Firebase:
1. **Taxas de App:** Uma query na coleção `pedidos` buscando pedidos concluídos de hoje do entregador, somando o campo `pagamento.taxa_entrega`.
2. **Taxas Extras:** Uma query na coleção `entregadores_extras` (onde a central joga bônus avulsos para o entregador).
*O fechamento do dia (quando ele fica offline) tira uma foto da maquininha de cartão, sobe para o `Firebase Storage` e cria um documento na coleção `fechamentos` para a auditoria do Financeiro.*

---

## 🚨 HOTFIXES PENDENTES 

Temos alguns relatos de campo da nossa frota que precisam de atuação cirúrgica. Aqui está o mapa da mina para você investigar e resolver:

### 🐛 Bug 1: Perda de Estado no Background (O App "reseta")
* **Relato:** *"Quando saio do app para mexer em outro e volto, a corrida some e o app pede para começar tudo de novo."*
* **Onde investigar:** `lib/screens/dashboard_screen.dart` e `lib/screens/corridas_tab.dart`.
* **Causa Provável:** O Flutter (ou o SO do Android) está matando a `Activity` para economizar memória (Lifecycle). Como a corrida ativa está presa apenas em variáveis locais da memória RAM (no `setState`), ao voltar, o app redesenha a tela do zero.
* **Como resolver:** Você precisará implementar persistência de estado. Use o `WidgetsBindingObserver` para escutar o ciclo de vida do app (`AppLifecycleState.resumed`). Salve o estado atual da corrida usando `SharedPreferences` para que, ao recarregar, a tela leia o disco local e puxe a corrida automaticamente em vez de exigir nova bipagem.

### 🐛 Bug 2: GPS falhando após muito tempo
* **Onde investigar:** `lib/services/location_service.dart`.
* **Causa Provável:** O *Doze Mode* (Modo de economia de bateria) de alguns Androids (especialmente Xiaomi/Motorola) está matando o nosso *Foreground Service*.
* **Como resolver:** Garantir que o plugin `geolocator` está configurado com as notificações persistentes corretamente e orientar no app (via `permission_handler`) para o motoboy remover o aplicativo da otimização de bateria do Android (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`).

---

## 🚀 ROADMAP E FEATURES (O que vamos construir)

### 🗺️ Feature 1: Mapa Interativo de Múltiplas Entregas
* **Relato:** *"Ter a opção de mapa com as localizações de cada entrega, para o motoboy selecionar qual ele vai fazer primeiro."*
* **Como e Onde Implementar:** 1. Crie uma nova tela ou modal chamado `lib/screens/mapa_rotas_screen.dart`.
  2. Adicione o pacote `Maps_flutter` ou `flutter_map` (se preferir OpenStreetMap).
  3. No arquivo `corridas_tab.dart`, você verá que já existe uma lista com todos os endereços não-concluídos. Você precisará extrair as propriedades `latitude` e `longitude` do objeto `endereco` salvo no Firestore.
  4. Plote os marcadores (Pins) no mapa. Ao clicar num Pin, abra um BottomSheet para ele iniciar a navegação daquele ponto específico.

---

## 🧙‍♂️ Dica de Ouro (OTA Updates)
Sempre que fizer um hotfix rápido (alteração apenas em arquivos `.dart`), **não** precisamos gerar um novo APK e mandar para os entregadores.
1. Altere o código.
2. Atualize a variável `_otaPatchVersion` no `profile_tab.dart`.
3. Rode o comando `shorebird patch android` no seu terminal.
4. O app vai se atualizar sozinho no celular dos motoboys no próximo *Cold Start* (quando fecharem e abrirem o app).

## 👨‍💻 Autor
Desenvolvido por ** Raiky Câmara ** ([@raikyrk](https://github.com/raikyrk)) **Guilherme Trajano** ([@trajanoo93](https://github.com/trajanoo93)).