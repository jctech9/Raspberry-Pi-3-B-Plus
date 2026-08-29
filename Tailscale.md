# =============================================================================
# Tailscale — exit node + subnet router
# =============================================================================
# Execute os blocos na ordem. Todos os comandos precisam de sudo.
# =============================================================================


# -----------------------------------------------------------------------------
# 1. Instalar o Tailscale e fazer login
# -----------------------------------------------------------------------------
curl -fsSL https://tailscale.com/install.sh | sh

sudo tailscale up


# -----------------------------------------------------------------------------
# 2. Habilitar o encaminhamento de pacotes (IPv4 e IPv6)
# -----------------------------------------------------------------------------
sudo tee /etc/sysctl.d/99-tailscale.conf >/dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

sudo sysctl -p /etc/sysctl.d/99-tailscale.conf


# -----------------------------------------------------------------------------
# 3. Anunciar o exit node e as sub-redes
# -----------------------------------------------------------------------------
sudo tailscale set \
  --advertise-exit-node \
  --advertise-routes=192.168.0.0/16

# Alternativa: várias redes de uma vez.
# Atenção: este comando SUBSTITUI as rotas anunciadas acima, não soma.
sudo tailscale set \
  --advertise-exit-node \
  --advertise-routes=192.168.1.0/24,192.168.2.0/24


# -----------------------------------------------------------------------------
# 4. Aprovar no admin console
# -----------------------------------------------------------------------------
# O exit node e as rotas só ficam ativos depois de aprovados em:
# https://login.tailscale.com/admin/machines
