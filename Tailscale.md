
#___________________________instalar o Tailscale e fazer login____________________________________#
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up


#_______________________encaminhamento de pacotes________________________________________________#

sudo tee /etc/sysctl.d/99-tailscale.conf >/dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

sudo sysctl -p /etc/sysctl.d/99-tailscale.conf


#_____________________Anuncie o exit node e as sub-redes________________________________________#
sudo tailscale set \
  --advertise-exit-node \
  --advertise-routes=192.168.0.0/16
#____________________Para anunciar várias redes______________________________________________#
sudo tailscale set \
--advertise-exit-node \
--advertise-routes=192.168.1.0/24,192.168.2.0/24
    


