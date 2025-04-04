# Guía Completa para Crear tu Propio Servidor OpenVPN con Subscripciones Mensuales Usando Stripe

Este proyecto te permite montar tu propio servidor OpenVPN en un VPS Ubuntu 22.04/24.04 con:
- Instalador automático.
- Creación de clientes por suscripción mensual.
- Webhook para gestionar pagos y revocaciones automáticas.

---

## Requisitos

- VPS Ubuntu 22.04 o 24.04
- Dominio o IP estática (opcional pero recomendado)
- Cuenta de Stripe y claves API

---

## Instalación del Servidor VPN

1. **Conéctate al VPS:**
```bash
ssh root@TU_IP
```

2. **Descarga el instalador:**
```bash
git clone https://github.com/tuusuario/openvpn-stripe
cd openvpn-stripe
chmod +x installer.sh
```

3. **Ejecuta el instalador:**
```bash
./installer.sh
```

4. **Cuando finalice, crea un cliente manual si lo deseas:**
```bash
./installer.sh add-client cliente1
```

---

## Configuración del Webhook de Stripe

1. **Edita `Stripe Openvpn Webhook.py`:**
- Coloca tu `STRIPE_SECRET_KEY` y `WEBHOOK_SECRET`.

2. **Instala dependencias:**
```bash
apt install python3-flask python3-pip -y
pip3 install stripe
```

3. **Ejecuta el webhook:**
```bash
python3 Stripe\ Openvpn\ Webhook.py
```
(O puedes ponerlo como servicio o usar `tmux`)

4. **Configura el endpoint en Stripe:**
- URL: `https://tu_dominio.com/webhook`
- Eventos: `invoice.payment_succeeded`, `invoice.payment_failed`

---

## Automatizar Revocación de Clientes Expirados

Crea un cron job:
```bash
crontab -e
```
Y añade:
```bash
0 * * * * curl -X POST http://localhost:4242/revoke-expired
```
Esto revisa cada hora las suscripciones caducadas.

---

## Enviar Archivos VPN por Correo

El webhook usa `mutt` para enviar el archivo `.ovpn` generado tras el pago:

Asegúrate de configurar `/etc/ssmtp/ssmtp.conf` o Postfix para usar SMTP de Gmail (con App Password si es necesario).

---

## Seguridad y Buenas Prácticas

- Los clientes se generan con claves propias.
- Se usa `tls-crypt` para cifrado extra.
- El script bloquea acceso tras caducidad.
- Límites de conexiones y UFW están aplicados.

---

## TODO y Mejoras Futuras

- Panel web para visualizar clientes activos
- Soporte para WireGuard
- Logs enriquecidos y notificaciones Telegram

---

## Licencia

MIT. Usa y mejora libremente. Crédito opcional si lo compartes ;)

---

¡Listo! Con esto puedes vender acceso a tu VPN de forma automática.

