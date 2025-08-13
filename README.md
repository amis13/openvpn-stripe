# 🔧 Monta tu propio servidor VPN con OpenVPN + Stripe

Este proyecto te permite desplegar un servidor VPN con autenticación de suscripción mensual mediante [Stripe](https://stripe.com). Los clientes reciben automáticamente su archivo `.ovpn` por correo tras el pago, y si no renuevan, el acceso es revocado automáticamente.

---

## 📁 Estructura del Proyecto

```
/
├── auto-vpn.sh                 # Instalador y gestor de clientes OpenVPN
├── webhook.py                  # Webhook Flask para pagos con Stripe
├── revoke.sh                   # Revoca certificados
├── subscriptions.json          # Base de datos de suscripciones
├── /root/clients-configs/      # Archivos .ovpn de los clientes
└── /root/openvpn-ca/           # Infraestructura Easy-RSA
```

---

## 🛠️ Requisitos

- Ubuntu 22.04 o 24.04
- Cuenta de Stripe con producto/plan mensual creado
- Acceso root
- IP pública o dominio

Instala dependencias:

```bash
sudo apt update
sudo apt install -y openvpn easy-rsa ufw curl iptables-persistent net-tools mutt python3-pip
pip3 install flask stripe
```

---

## ⚖️ Instalación OpenVPN

Ejecuta el script auto instalador:

```bash
chmod +x auto-vpn.sh
sudo ./auto-vpn.sh
```

Para añadir clientes manualmente:

```bash
sudo ./auto-vpn.sh add-client nombre_cliente
```

---

## 🔐 Webhook de Stripe

1. Renombra y ejecuta:

```bash
python3 webhook.py
```

2. Para modo servicio, crea:

```ini
# /etc/systemd/system/stripe-webhook.service
[Unit]
Description=Stripe Webhook para OpenVPN
After=network.target

[Service]
ExecStart=/usr/bin/python3 webhook.py
WorkingDirectory=/root/openvpn-stripe
Restart=always
User=root

[Install]
WantedBy=multi-user.target
```

Activa:

```bash
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable stripe-webhook
sudo systemctl start stripe-webhook
```

---

## 💳 Configura Stripe

1. Crea un producto con suscripción mensual
2. Ve a Developers → Webhooks
3. Endpoint: `http://TU_IP_O_DOMINIO:4242/webhook`
4. Copia la "Signing secret" y colócala en `webhook.py`
5. Usa enlaces Checkout de Stripe para vender la VPN

---

## 📧 Envío automático por correo

Crea `~/.muttrc` para Gmail:

```bash
set from = "tucorreo@gmail.com"
set realname = "VPN Server"
set smtp_url = "smtp://tucorreo@gmail.com@smtp.gmail.com:587/"
set smtp_pass = "clave_app_o_contraseña"
```

---

## 🔄 Revocar clientes vencidos

El webhook expone `/revoke-expired`. Puedes automatizarlo con cron:

```bash
sudo crontab -e
```

Y agregar:

```
0 0 * * * curl -X POST http://localhost:4242/revoke-expired
```

Esto revoca clientes no renovados cada día a la medianoche.

---

## 🚀 ¡Y listo!

Tu servidor VPN está ahora completamente automatizado con Stripe. 

Aceptas pagos, se crean clientes y se revocan al vencimiento.

---

📁 Repositorio: [https://github.com/tuusuario/openvpn-stripe-server](https://github.com/tuusuario/openvpn-stripe-server)
