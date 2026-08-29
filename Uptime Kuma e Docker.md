# Uptime Kuma — instalação com Docker

Execute os blocos na ordem. Todos os comandos precisam de `sudo`.

## 1. Atualizar o sistema

```bash
sudo apt update
sudo apt full-upgrade -y

```

## 2. Instalar o Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker

```

Verifique se o Docker e o Docker Compose foram instalados corretamente:

```bash
sudo docker --version
sudo docker compose version

```

## 3. Criar a configuração do Uptime Kuma

```bash
sudo mkdir -p /opt/uptime-kuma
sudo tee /opt/uptime-kuma/compose.yaml >/dev/null <<'EOF'
services:
  uptime-kuma:
    image: louislam/uptime-kuma:2
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - uptime-kuma-data:/app/data

volumes:
  uptime-kuma-data:
EOF

```

## 4. Iniciar o Uptime Kuma

```bash
sudo docker compose -f /opt/uptime-kuma/compose.yaml up -d

```

Verifique se o contêiner está funcionando:

```bash
sudo docker compose -f /opt/uptime-kuma/compose.yaml ps

```

## 5. Acessar a interface

Descubra o endereço IP do Raspberry Pi:

```bash
hostname -I

```

Abra no navegador, substituindo `IP-DO-RASPBERRY` pelo endereço exibido:

```text
http://IP-DO-RASPBERRY:3001
```

Exemplo: `http://192.168.1.50:3001`.

Na primeira tela, escolha o idioma e crie a conta de administrador.

## 6. Atualizar o Uptime Kuma

```bash
sudo docker compose -f /opt/uptime-kuma/compose.yaml pull
sudo docker compose -f /opt/uptime-kuma/compose.yaml up -d
sudo docker image prune -f

```

## 7. Ver os logs

```bash
sudo docker compose -f /opt/uptime-kuma/compose.yaml logs -f

```

Use `Ctrl+C` para sair dos logs sem interromper o Uptime Kuma.

## 8. Fazer backup dos dados

> **Atenção:** pare o Uptime Kuma antes de copiar os dados para garantir um
> backup consistente. Durante esse período, o monitoramento ficará indisponível.

```bash
sudo docker compose -f /opt/uptime-kuma/compose.yaml stop
sudo docker run --rm \
  -v uptime-kuma_uptime-kuma-data:/data:ro \
  -v /opt/uptime-kuma:/backup \
  alpine sh -c 'tar -czf /backup/uptime-kuma-backup.tar.gz -C /data .'
sudo docker compose -f /opt/uptime-kuma/compose.yaml start

```

O backup será salvo em:

```text
/opt/uptime-kuma/uptime-kuma-backup.tar.gz
```

> **Nota:** a porta `3001` ficará acessível na rede local. Para acesso pela
> internet, prefira usar uma VPN como o Tailscale em vez de encaminhar essa
> porta diretamente no roteador.

