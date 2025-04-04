from flask import Flask, request, jsonify
import subprocess
import os
import stripe
from datetime import datetime, timedelta
import json

app = Flask(__name__)

# Configura tus claves
stripe.api_key = "sk_test_XXXXXXXXXXXXXXXXXXXXXXXX"
endpoint_secret = "whsec_XXXXXXXXXXXXXXXXXXXXXXXX"
SUBSCRIPTION_FILE = "/root/VPN/scripts/subscriptions.json"
REVOKE_SCRIPT = "/root/VPN/scripts/revoke.sh"


def load_subscriptions():
    if not os.path.exists(SUBSCRIPTION_FILE):
        return {}
    with open(SUBSCRIPTION_FILE, "r") as f:
        return json.load(f)


def save_subscriptions(data):
    with open(SUBSCRIPTION_FILE, "w") as f:
        json.dump(data, f, indent=4)


@app.route("/webhook", methods=["POST"])
def stripe_webhook():
    payload = request.data
    sig_header = request.headers.get("Stripe-Signature")
    try:
        event = stripe.Webhook.construct_event(payload, sig_header, endpoint_secret)
    except stripe.error.SignatureVerificationError:
        return "Firma no válida", 400

    subscriptions = load_subscriptions()

    if event["type"] == "invoice.payment_succeeded":
        customer_email = event["data"]["object"].get("customer_email")
        if customer_email:
            client_name = customer_email.split("@")[0].replace(".", "_")
            subprocess.run(["/root/VPN/scripts/installer.sh", "add-client", client_name])
            subprocess.run([
                "mutt", "-s", "VPN", "-a", f"/root/clients-configs/{client_name}.ovpn", "--", customer_email
            ], input=b"Gracias por tu pago. Te enviamos tu archivo VPN.\n")
            subscriptions[client_name] = {
                "email": customer_email,
                "expires_at": (datetime.utcnow() + timedelta(days=30)).isoformat()
            }
            save_subscriptions(subscriptions)

    elif event["type"] == "invoice.payment_failed":
        customer_email = event["data"]["object"].get("customer_email")
        if customer_email:
            client_name = customer_email.split("@")[0].replace(".", "_")
            subprocess.run([REVOKE_SCRIPT, client_name])
            if client_name in subscriptions:
                del subscriptions[client_name]
                save_subscriptions(subscriptions)

    return jsonify(success=True)


@app.route("/revoke-expired", methods=["POST"])
def revoke_expired():
    now = datetime.utcnow()
    subscriptions = load_subscriptions()
    updated = False

    for client, data in list(subscriptions.items()):
        expiry = datetime.fromisoformat(data["expires_at"])
        if now > expiry:
            subprocess.run([REVOKE_SCRIPT, client])
            del subscriptions[client]
            updated = True

    if updated:
        save_subscriptions(subscriptions)

    return jsonify(revoked=True)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=4242)
