App Entregadores - AG 

É um aplicativo desenvolvido para os entregadores da empresa Ao Gosto Carnes, permitindo gerenciar entregas de forma prática, eficiente e integrada com uma API.

Ele oferece funcionalidades como escaneamento de QR codes de cupons, acompanhamento de entregas pendentes e concluídas, visualização de taxas de entrega e envio de relatórios.

Funcionalidades
Login Seguro

Acesso via PIN de 4 dígitos.

Escaneamento de QR Code

Registra entregas ao escanear QR codes.

Coleta informações como ID do pedido, bairro, endereço, taxa de entrega, entre outros.

Dashboard

Exibe um resumo do dia:

Quantidade de entregas pendentes e concluídas.

Subtotal das taxas de entrega.

Tempo médio de entrega (comparado com o dia anterior).

Gerenciamento de Entregas

Lista de entregas pendentes e concluídas.

Opções para marcar entrega como concluída ou excluir pedidos escaneados incorretamente.

Visualização de detalhes do pedido, incluindo endereço e contato.

Abertura de endereços no Google Maps ou Waze.

Envio automático de mensagens via WhatsApp para clientes, como “Saiu para entrega” ou “Entrega concluída”.

Relatórios

Captura e envio de fotos como relatórios para a API.

Atualização de Dados

Botão para atualizar o painel e carregar novos dados da API.

Logs

Geração de logs locais para monitoramento.

Upload de logs para o servidor.

Como Funciona

Login: O entregador insere um PIN de 4 dígitos para acessar o app.

Dashboard: Exibe resumo das entregas do dia, com opções para escanear QR codes, ver relatórios ou atualizar dados.

Escaneamento: O QR code do cupom é escaneado, registrando o pedido na API e enviando mensagem automática ao cliente.

Gerenciamento:

Visualização de entregas pendentes e concluídas.

Marcação de entregas como concluídas (com envio de mensagem) ou exclusão de pedidos incorretos.

Abertura do endereço no Google Maps ou Waze.

Relatórios: O entregador tira uma foto com a câmera e envia como relatório para a API.

Atualização: O app verifica automaticamente novas versões e notifica o entregador caso haja atualização disponível.

Tecnologias

Flutter: Framework para desenvolvimento do app.

API: Integração com backend via HTTP para gerenciar entregas e relatórios.

WhatsApp API: Envio de mensagens automáticas aos clientes.

Mobile Scanner: Escaneamento de QR codes.

SharedPreferences: Armazenamento local de dados do entregador.

Path Provider: Gerenciamento de logs locais.
