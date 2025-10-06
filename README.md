# Ao Gosto Carnes - App de Entregadores

## Descrição
Aplicativo para entregadores gerenciarem pedidos de forma prática e eficiente.  
Permite escanear QR codes, acompanhar entregas, visualizar taxas e enviar relatórios, tudo integrado com uma API.

## Funcionalidades
- **Login Seguro:** PIN de 4 dígitos.
- **Escaneamento de QR Code:** Registra ID do pedido, bairro, endereço, taxa de entrega.
- **Dashboard:**
  - Quantidade de entregas pendentes e concluídas
  - Subtotal das taxas de entrega
  - Tempo médio de entrega
- **Gerenciamento de Entregas:**
  - Marcar entregas como concluídas
  - Excluir entregas incorretas
  - Abrir endereço no Google Maps ou Waze
- **Relatórios:** Captura e envia fotos como relatórios
- **Atualização de Dados:** Botão para atualizar painel e carregar novos dados da API
- **Logs:** Geração de logs locais e envio para servidor

## Como Funciona
1. **Login:** Entregador insere PIN de 4 dígitos
2. **Dashboard:** Resumo das entregas do dia
3. **Escaneamento:** QR code registra pedido e envia mensagem automática ao cliente
4. **Gerenciamento:** Marcação de entregas e navegação até o endereço
5. **Relatórios:** Captura de fotos enviadas à API
6. **Atualização:** Verifica novas versões e notifica o entregador

## Tecnologias
- Flutter
- API HTTP
- WhatsApp API
- Mobile Scanner
- SharedPreferences
- Path Provider

## Observações
- Otimizado para Android
- Requer câmera e internet
