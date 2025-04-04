#!/bin/bash
# === Instalador Interactivo Mejorado para OpenVPN ===
# Compatible con Ubuntu 22.04 y 24.04
# Modo modular, TLS configurable (auth o crypt) y con logs de actividad

set -euo pipefail

### Variables globales
CLIENTS_DIR="${HOME}/clients-configs"
OPENVPN_CA_DIR="${HOME}/openvpn-ca"
TLS_MODE_FILE="/etc/openvpn/tls_mode"
YOUR_IP="${YOUR_IP:-}"  # Si no está definida, se solicitará

# Definimos la ruta donde se debe colocar la configuración del servidor
SERVER_CONF_DIR="/etc/openvpn/server"
SERVER_CONF_FILE="${SERVER_CONF_DIR}/server.conf"

### Funciones auxiliares

function get_ip() {
  local ip
  read -rp "[*] Introduce tu IP: " ip
  if [[ -z "$ip" ]]; then
    echo "[!] No se ha introducido una IP válida." >&2
    exit 1
  fi
  YOUR_IP="$ip"
}

function check_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "[!] Este script debe ejecutarse como root." >&2
    exit 1
  fi
}

function check_os() {
  if ! grep -q -E "Ubuntu 2[24]" /etc/os-release; then
    echo "[!] Este script solo funciona en Ubuntu 22 o 24." >&2
    exit 1
  fi
}

function install_packages() {
  echo -e "\n>>> Instalando paquetes necesarios..."
  apt update && apt install -y openvpn easy-rsa ufw curl wget mutt iptables-persistent
}

function setup_easy_rsa() {
  echo ">>> Inicializando Easy-RSA..."
  if [ -d "$OPENVPN_CA_DIR" ]; then
    echo "[!] El directorio $OPENVPN_CA_DIR ya existe."
    read -rp "¿Deseas sobrescribirlo? (s/N): " resp
    if [[ "$resp" =~ ^[sS]$ ]]; then
      rm -rf "$OPENVPN_CA_DIR"
    else
      echo "[*] Usando directorio existente."
      return
    fi
  fi
  make-cadir "$OPENVPN_CA_DIR"
  cd "$OPENVPN_CA_DIR"
  ./easyrsa init-pki
  echo ">>> Generando CA..."
  ./easyrsa build-ca nopass
}

function build_server_cert() {
  echo ">>> Generando certificado del servidor..."
  cd "$OPENVPN_CA_DIR"
  ./easyrsa gen-req server nopass
  ./easyrsa sign-req server server
}

function build_dh_and_tls() {
  echo ">>> Generando Diffie-Hellman..."
  cd "$OPENVPN_CA_DIR"
  ./easyrsa gen-dh

  echo -e "\n>>> Selecciona el tipo de protección TLS extra:"
  echo "   1) tls-auth (más compatible)"
  echo "   2) tls-crypt (más seguro)"
  select tlsopt in "tls-auth" "tls-crypt"; do
    case $REPLY in
      1)
        openvpn --genkey secret ta.key
        TLS_MODE="auth"
        break
        ;;
      2)
        openvpn --genkey secret ta.key
        TLS_MODE="crypt"
        break
        ;;
      *)
        echo "[!] Opción inválida, intenta de nuevo."
        ;;
    esac
  done
  echo "$TLS_MODE" > "$TLS_MODE_FILE"

  echo ">>> Generando crl.pem..."
  ./easyrsa gen-crl
  cp pki/crl.pem /etc/openvpn/crl.pem
  chmod 644 /etc/openvpn/crl.pem
}

function copy_server_files() {
  echo ">>> Copiando certificados y claves a /etc/openvpn..."
  cd "$OPENVPN_CA_DIR"
  cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/dh.pem /etc/openvpn/
  cp ta.key /etc/openvpn/
}

function configure_server() {
  echo ">>> Configurando servidor OpenVPN..."
  mkdir -p "$SERVER_CONF_DIR"

  if [ -f /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz ]; then
    gunzip -c /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz > "$SERVER_CONF_FILE"
    sed -i 's|ca ca.crt|ca /etc/openvpn/ca.crt|' "$SERVER_CONF_FILE"
    sed -i 's|cert server.crt|cert /etc/openvpn/server.crt|' "$SERVER_CONF_FILE"
    sed -i 's|key server.key|key /etc/openvpn/server.key|' "$SERVER_CONF_FILE"
    sed -i 's|dh dh.pem|dh /etc/openvpn/dh.pem|' "$SERVER_CONF_FILE"
    sed -i 's/;user nobody/user nobody/' "$SERVER_CONF_FILE"
    sed -i 's/;group nogroup/group nogroup/' "$SERVER_CONF_FILE"

    if [[ "$TLS_MODE" == "auth" ]]; then
      sed -i 's|^;tls-auth ta.key 0|tls-auth /etc/openvpn/ta.key 0|' "$SERVER_CONF_FILE"
      sed -i 's|^tls-crypt|#tls-crypt|' "$SERVER_CONF_FILE"
    else
      sed -i 's|^;tls-crypt ta.key|tls-crypt /etc/openvpn/ta.key|' "$SERVER_CONF_FILE"
      sed -i 's|^tls-auth|#tls-auth|' "$SERVER_CONF_FILE"
    fi

    grep -q "^log-append" "$SERVER_CONF_FILE" || echo "log-append /var/log/openvpn.log" >> "$SERVER_CONF_FILE"
    grep -q "^status" "$SERVER_CONF_FILE" || echo "status /var/log/openvpn-status.log" >> "$SERVER_CONF_FILE"
    grep -q "^verb" "$SERVER_CONF_FILE" || echo "verb 3" >> "$SERVER_CONF_FILE"
    grep -q "^crl-verify" "$SERVER_CONF_FILE" || echo "crl-verify /etc/openvpn/crl.pem" >> "$SERVER_CONF_FILE"
  else
    cat <<EOF > "$SERVER_CONF_FILE"
port 1194
proto udp
dev tun
ca /etc/openvpn/ca.crt
cert /etc/openvpn/server.crt
key /etc/openvpn/server.key
dh /etc/openvpn/dh.pem
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist /etc/openvpn/ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
cipher AES-256-CBC
user nobody
group nogroup
persist-key
persist-tun
topology subnet
data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC
data-ciphers-fallback AES-256-CBC
EOF
    if [[ "$TLS_MODE" == "auth" ]]; then
      echo "tls-auth /etc/openvpn/ta.key 0" >> "$SERVER_CONF_FILE"
    else
      echo "tls-crypt /etc/openvpn/ta.key" >> "$SERVER_CONF_FILE"
    fi
    echo "crl-verify /etc/openvpn/crl.pem" >> "$SERVER_CONF_FILE"
    echo "log-append /var/log/openvpn.log" >> "$SERVER_CONF_FILE"
    echo "status /var/log/openvpn-status.log" >> "$SERVER_CONF_FILE"
    echo "verb 3" >> "$SERVER_CONF_FILE"
  fi
}

function enable_forwarding_and_nat() {
  sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
  sysctl -p
  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
  netfilter-persistent save
}

function configure_ufw() {
  ufw allow OpenSSH
  ufw allow 1194/udp
  sed -i '/^DEFAULT_FORWARD_POLICY=/c\DEFAULT_FORWARD_POLICY="ACCEPT"' /etc/default/ufw
  grep -q 10.8.0.0 /etc/ufw/before.rules || {
    sed -i "/^*filter/i *nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE\nCOMMIT" /etc/ufw/before.rules
  }
  ufw --force enable
}

function start_openvpn() {
  systemctl enable openvpn-server@server
  systemctl start openvpn-server@server
  systemctl status openvpn-server@server --no-pager
}

function generate_client() {
  local CLIENT_NAME="$1"
  mkdir -p "$CLIENTS_DIR"
  cd "$OPENVPN_CA_DIR"
  ./easyrsa gen-req "$CLIENT_NAME" nopass
  ./easyrsa sign-req client "$CLIENT_NAME"
  local CLIENT_CONF="$CLIENTS_DIR/${CLIENT_NAME}.ovpn"
  cat <<EOF > "$CLIENT_CONF"
client
dev tun
proto udp
remote $YOUR_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3
key-direction 1
<ca>
$(cat /etc/openvpn/ca.crt)
</ca>
<cert>
$(cat $OPENVPN_CA_DIR/pki/issued/$CLIENT_NAME.crt)
</cert>
<key>
$(cat $OPENVPN_CA_DIR/pki/private/$CLIENT_NAME.key)
</key>
<tls-crypt>
$(cat /etc/openvpn/ta.key)
</tls-crypt>
EOF
  echo "✅ Cliente creado en: $CLIENT_CONF"
}

### Flujo principal
check_root
check_os
[[ -z "$YOUR_IP" ]] && get_ip
install_packages
setup_easy_rsa
build_server_cert
build_dh_and_tls
copy_server_files
configure_server
enable_forwarding
configure_ufw
start_openvpn

echo -e "\n✅ OpenVPN instalado. Ejecuta '$0 add-client NOMBRE' para generar clientes."

if [[ "${1:-}" == "add-client" ]]; then
  shift
  [[ -z "${1:-}" ]] && { echo "Uso: $0 add-client <nombre>"; exit 1; }
  generate_client "$1"
fi
