# Raspberry Pi 3 B+

Configuração de serviços para **Raspberry Pi 3 Model B+** utilizando **Raspberry Pi OS 64-bit (ARM64)**.

O projeto automatiza a instalação e configuração de:

* **Docker / Docker Compose**
* **Uptime Kuma 2** — monitoramento de serviços
* **Glances 4** — monitoramento de recursos do sistema
* **Tailscale** — VPN, Exit Node e Subnet Router

## Instalação

```bash
curl -fsSL https://raw.githubusercontent.com/jctech9/Raspberry-Pi-3-B-Plus/main/install.sh | sudo bash
```

O instalador valida o sistema, instala as dependências necessárias e configura os serviços automaticamente.

## Documentação

Guias individuais disponíveis no repositório:

* `Uptime Kuma e Docker.md`
* `Glances 4.md`
* `Tailscale.md`

## Acesso

Após a instalação:

* **Uptime Kuma:** `http://IP-DO-RASPBERRY:3001`
* **Glances:** `http://IP-DO-RASPBERRY:61208`
