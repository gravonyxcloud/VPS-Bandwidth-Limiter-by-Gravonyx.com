# 🚀 VPS Bandwidth Limiter & Optimizer by Gravonyx.com

Gerencie o tráfego e turbine a performance da sua VPS Linux com uma interface profissional, otimizações de kernel de última geração e persistência automática.

---

## 🛠 Instalação e Atualização Rápida

Copie e cole o comando abaixo no seu terminal como **root**:

``bash
wget -qO limitar_banda.sh [https://raw.githubusercontent.com/gravonyxcloud/VPS-Bandwidth-Limiter-by-Gravonyx.com/main/limitar_banda.sh](https://raw.githubusercontent.com/gravonyxcloud/VPS-Bandwidth-Limiter-by-Gravonyx.com/main/limitar_banda.sh) && chmod +x limitar_banda.sh && ./limitar_banda.sh``

---

✨ O que há de novo na Versão 4.3 Ultra Pro
Diferente de scripts simples, esta ferramenta foca em estabilidade e velocidade real:

🌀 Auto-Update & Upgrade: O script garante que sua VPS esteja segura executando apt update e upgrade automaticamente antes de iniciar.

📊 Progresso em Tempo Real: Barra de carregamento visual para acompanhar a atualização do sistema.

🚀 TCP BBR (Google): Ativa o algoritmo de controle de congestionamento mais moderno do mundo, reduzindo drasticamente a latência e o "bufferbloat".

🌐 DNS Performance: Configura automaticamente os servidores da Cloudflare (1.1.1.1) e Google (8.8.8.8) para resoluções de rotas instantâneas.

📏 Deteção de Banda Real: O script lê o hardware da sua VPS (via ethtool) e identifica se você tem 100Mb, 1Gb ou mais, ajustando as mensagens de sistema dinamicamente.

🛡 Funcionalidades Principais
Controle de Banda Bilateral: Limite Download (Ingress), Upload (Egress) ou ambos simultaneamente.

Persistência Automática: Configura o crontab e cria scripts de inicialização em /usr/local/bin/ para que as regras sobrevivam a reboots.

Gestor de Regras: Detecta se já existe um limite ativo e permite editar ou remover sem deixar "lixo" no sistema.

Limpeza Total (Reset): Opção de desinstalação que restaura as configurações de rede padrão do fabricante e remove otimizações de kernel.

Compatibilidade Total: Otimizado para VPS Contabo, DigitalOcean, AWS, Google Cloud e servidores locais rodando Ubuntu ou Debian.

🔍 Entendendo a Otimização
O script utiliza o Traffic Control (TC) do Linux com hierarquia HTB (Hierarchical Token Bucket) para garantir que o limite de velocidade seja preciso e não cause picos de lag.

Ao ativar a otimização de Kernel, o script ajusta os buffers de recepção e envio (rmem e wmem) e ativa o algoritmo BBR, permitindo que a VPS processe mais dados com menor latência em conexões de longa distância.

📄 Licença
Este projeto está sob a licença MIT. Sinta-se à vontade para usar e modificar, mantendo sempre os créditos à Gravonyx.com.

Suporte e Créditos: Desenvolvido por: Gravonyx.com Versão: 4.3 Ultra Pro
