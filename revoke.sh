#!/bin/bash

# === Revoca y elimina certificados VPN de clientes ===
# Compatible con estructura auto-vpn.sh y webhook.py

set -euo pipefail

CLIENT_NAME="$1"
EASYRSA_DIR="/root/openvpn-ca"
CLIENTS_DIR="/root/clients-configs"
CRL_PATH="/etc/openvpn/crl.pem"

if [[ -z "$CLIENT_NAME" ]]; then
    echo "[!] Debes especificar el nombre del cliente."
    exit 1
fi

echo "[*] Revocando cliente: $CLIENT_NAME"

cd "$EASYRSA_DIR"

# Revocar el certificado
./easyrsa --batch revoke "$CLIENT_NAME"

# Regenerar la CRL
./easyrsa gen-crl

# Mover la CRL al directorio de OpenVPN
cp "$EASYRSA_DIR/pki/crl.pem" "$CRL_PATH"
chown nobody:nogroup "$CRL_PATH"
chmod 644 "$CRL_PATH"

# Borrar archivos del cliente
rm -f "$EASYRSA_DIR/pki/reqs/${CLIENT_NAME}.req"
rm -f "$EASYRSA_DIR/pki/issued/${CLIENT_NAME}.crt"
rm -f "$EASYRSA_DIR/pki/private/${CLIENT_NAME}.key"
rm -f "$CLIENTS_DIR/${CLIENT_NAME}.ovpn"

echo "✅ Cliente '$CLIENT_NAME' revocado y archivos eliminados."
