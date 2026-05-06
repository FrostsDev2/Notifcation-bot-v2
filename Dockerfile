
from flask import Flask, render_template, request, redirect, flash
import threading
import imaplib
import email
import re
import time
from twilio.rest import Client

app = Flask(__name__)
app.secret_key = "change-me"

alerts = []

CHECK_INTERVAL = 5

def extract_links(text):
    return re.findall(r'https?://\S+', text)

def send_sms(alert, message):
    client = Client(alert["twilio_sid"], alert["twilio_token"])

    client.messages.create(
        body=message,
        from_=alert["twilio_number"],
        to=alert["phone"]
    )

def monitor(alert):
    seen = set()

    while True:
        try:
            imap = imaplib.IMAP4_SSL(alert["imap_server"])
            imap.login(alert["email"], alert["password"])

            imap.select("INBOX")

            _, messages = imap.search(None, "UNSEEN")

            for email_id in messages[0].split():

                if email_id in seen:
                    continue

                seen.add(email_id)

                _, msg_data = imap.fetch(email_id, "(RFC822)")

                for response_part in msg_data:

                    if isinstance(response_part, tuple):

                        msg = email.message_from_bytes(response_part[1])

                        sender = msg.get("From", "")
                        subject = msg.get("Subject", "")

                        if alert["sender"].lower() not in sender.lower():
                            continue

                        body = ""

                        if msg.is_multipart():
                            for part in msg.walk():
                                content_type = part.get_content_type()

                                if content_type == "text/plain":
                                    body += part.get_payload(decode=True).decode(errors="ignore")
                        else:
                            body = msg.get_payload(decode=True).decode(errors="ignore")

                        links = extract_links(body)

                        sms = f"Specs Alert!\n\n{subj(subject)}"

                        if links:
                            sms += "\n\nLinks:\n"
                            sms += "\n".join(links[:3])

                        send_sms(alert, sms)

            imap.logout()

        except Exception as e:
            print("ERROR:", e)

        time.sleep(CHECK_INTERVAL)

def subj(s):
    return s[:120]

@app.route("/", methods=["GET", "POST"])
def dashboard():

    if request.method == "POST":

        alert = {
            "name": request.form["name"],
            "email": request.form["email"],
            "password": request.form["password"],
            "imap_server": request.form["imap_server"],
            "sender": request.form["sender"],
            "phone": request.form["phone"],
            "twilio_sid": request.form["twilio_sid"],
            "twilio_token": request.form["twilio_token"],
            "twilio_number": request.form["twilio_number"]
        }

        alerts.append(alert)

        thread = threading.Thread(target=monitor, args=(alert,))
        thread.daemon = True
        thread.start()

        flash("Alert added successfully!")

        return redirect("/")

    return render_template("index.html", alerts=alerts)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
