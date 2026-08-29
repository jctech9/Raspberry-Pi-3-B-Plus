# Glances 4 — Docker no Raspberry Pi OS 64-bit (ARM64)

Este guia instala o Glances 4 com interface web no Raspberry Pi 3 B+ usando
Raspberry Pi OS 64-bit e a plataforma Docker `linux/arm64`. Execute os blocos
na ordem e use `sudo` conforme indicado.

## 1. Verificar a arquitetura e o Docker

Confira a arquitetura informada pelo sistema de pacotes:

```bash
dpkg --print-architecture

```

O resultado precisa ser:

```text
arm64
```

Confira também a arquitetura informada pelo kernel:

```bash
uname -m

```

O resultado precisa ser:

```text
aarch64
```

> **Atenção:** no Raspberry Pi OS 64-bit, `dpkg` mostra `arm64` e `uname`
> normalmente mostra `aarch64`. Se aparecer `armhf` ou `armv7l`, o sistema
> operacional é 32 bits e você não deve continuar com esta instalação.

Verifique se o Docker e o Docker Compose estão disponíveis:

```bash
sudo docker --version
sudo docker compose version

```

## 2. Criar a configuração do Glances

O segundo comando está codificado em Base64 para impedir que o terminal altere
a indentação ou tente executar as linhas do arquivo YAML separadamente. Copie e
execute a linha inteira de uma só vez.

```bash
sudo mkdir -p /opt/glances

```

```bash
printf '%s' 'c2VydmljZXM6CiAgZ2xhbmNlczoKICAgIGltYWdlOiBuaWNvbGFyZ28vZ2xhbmNlczo0LjUuNgogICAgcGxhdGZvcm06IGxpbnV4L2FybTY0CiAgICBjb250YWluZXJfbmFtZTogZ2xhbmNlcwogICAgcmVzdGFydDogdW5sZXNzLXN0b3BwZWQKICAgIHBpZDogaG9zdAogICAgcG9ydHM6CiAgICAgIC0gIjYxMjA4OjYxMjA4IgogICAgZW52aXJvbm1lbnQ6CiAgICAgIEdMQU5DRVNfT1BUOiAiLXciCiAgICB2b2x1bWVzOgogICAgICAtIC86L3Jvb3RmczpybwogICAgICAtIC92YXIvcnVuL2RvY2tlci5zb2NrOi92YXIvcnVuL2RvY2tlci5zb2NrOnJvCiAgICAgIC0gL2V0Yy9sb2NhbHRpbWU6L2V0Yy9sb2NhbHRpbWU6cm8K' | base64 -d | sudo tee /opt/glances/compose.yaml >/dev/null

```

Confira se o arquivo foi criado corretamente:

```bash
sudo cat /opt/glances/compose.yaml

```

Valide a configuração antes de iniciar o contêiner:

```bash
sudo docker compose -f /opt/glances/compose.yaml config >/dev/null && echo "Configuração válida"

```

## 3. Iniciar o Glances

```bash
sudo docker compose -f /opt/glances/compose.yaml up -d

```

Verifique se o contêiner está funcionando:

```bash
sudo docker compose -f /opt/glances/compose.yaml ps

```

## 4. Confirmar a versão instalada

```bash
sudo docker exec glances glances --version

```

A saída deve começar com `Glances version: 4` ou indicar uma versão `4.x`.

## 5. Acessar a interface web

Descubra o endereço IP do Raspberry Pi:

```bash
hostname -I

```

Abra no navegador, substituindo `IP-DO-RASPBERRY` pelo endereço exibido:

```text
http://IP-DO-RASPBERRY:61208
```

Exemplo: `http://192.168.1.50:61208`.

## 6. Monitorar o Glances no Uptime Kuma

No Uptime Kuma, crie um monitor do tipo **HTTP(s)** com o endereço:

```text
http://IP-DO-RASPBERRY:61208/api/4/status
```

Substitua `IP-DO-RASPBERRY` pelo IP local do Raspberry Pi.

## 7. Ver os logs

```bash
sudo docker compose -f /opt/glances/compose.yaml logs -f

```

Use `Ctrl+C` para sair dos logs sem interromper o Glances.

## 8. Parar, iniciar ou reiniciar

Parar:

```bash
sudo docker compose -f /opt/glances/compose.yaml stop

```

Iniciar novamente:

```bash
sudo docker compose -f /opt/glances/compose.yaml start

```

Reiniciar:

```bash
sudo docker compose -f /opt/glances/compose.yaml restart

```

## 9. Atualizar dentro da versão 4

Este guia fixa a imagem `nicolargo/glances:4.5.6` para impedir uma atualização
automática para uma futura versão principal. Para atualizar, consulte a versão
`4.x` mais recente no Docker Hub, altere o campo `image` no arquivo
`/opt/glances/compose.yaml` e execute:

```bash
sudo docker compose -f /opt/glances/compose.yaml pull
sudo docker compose -f /opt/glances/compose.yaml up -d
sudo docker image prune -f

```

Confirme a versão depois da atualização:

```bash
sudo docker exec glances glances --version

```

> **Segurança:** a montagem de `/var/run/docker.sock` permite que o Glances
> exiba os contêineres Docker. Não exponha a porta `61208` diretamente à
> internet; limite o acesso à rede local ou use o Tailscale. Se não quiser
> visualizar contêineres no Glances, remova essa montagem do arquivo Compose.

## Referências

- [Documentação oficial do Glances com Docker](https://glances.readthedocs.io/en/latest/docker.html)
- [Imagens oficiais do Glances no Docker Hub](https://hub.docker.com/r/nicolargo/glances/tags)
