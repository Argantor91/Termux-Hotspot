import os
import sys
import secrets
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
from urllib.parse import parse_qs

# --- Configuration ---
GATEWAY_IP = os.environ.get('GATEWAY_IP', '10.0.0.1')
PREFIX = os.environ.get('PREFIX', '/data/data/com.termux/files/usr')
PASS_FILE = os.path.join(PREFIX, 'tmp/hp_pass')

# 1. SECURE PASSWORD LOAD (Fail closed if missing)
try:
    with open(PASS_FILE, 'r') as f:
        CORRECT_PASSWORD = f.read().strip()
    if not CORRECT_PASSWORD:
        raise ValueError("Empty password file")
except Exception as e:
    print(f"[FATAL] Cannot read password file: {e}. Exiting.")
    sys.exit(1)

# 2. HTML Templates
PORTAL_HTML = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Hotspot Login</title>
<style>
body {{ font-family: -apple-system, sans-serif; background: #f0f2f5; margin: 0; display: flex; justify-content: center; align-items: center; height: 100vh; }}
.card {{ background: white; padding: 30px; border-radius: 16px; box-shadow: 0 10px 25px rgba(0,0,0,0.1); width: 90%; max-width: 350px; text-align: center; }}
input {{ width: 100%; padding: 12px; margin: 10px 0; border: 1px solid #ddd; border-radius: 8px; box-sizing: border-box; }}
button {{ width: 100%; padding: 12px; background: #0084ff; color: white; border: none; border-radius: 8px; font-size: 16px; font-weight: bold; cursor: pointer; }}
</style></head><body><div class="card"><h2>Wi-Fi Login</h2>
<form action="/login" method="POST"><input type="password" name="password" placeholder="Password" required autofocus>
<button type="submit">Connect</button></form></div></body></html>"""

SUCCESS_HTML = "<html><body style='text-align:center; padding-top:50px; font-family:sans-serif;'><h1>✅ Success!</h1><p>You are now connected.</p></body></html>"

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    def server_bind(self):
        self.socket.setsockopt(1, 2, 1) # SO_REUSEADDR
        super().server_bind()

class RequestHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass # Suppress default logging to keep Termux terminal clean

    def do_GET(self):
        # Captive Portal Detection Interception
        # If the OS probes these URLs, redirect them to our portal to force the popup
        probe_domains = ['connectivitycheck.gstatic.com', 'generate_204.google.com', 
                         'captive.apple.com', 'detectportal.firefox.com']
        
        host_header = self.headers.get('Host', '').split(':')[0]
        if host_header in probe_domains:
            self.send_response(302)
            self.send_header('Location', f'http://{GATEWAY_IP}/')
            self.end_headers()
            return

        # Serve the main portal
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(PORTAL_HTML.encode('utf-8'))

    def do_POST(self):
        if self.path != '/login':
            self.send_response(404)
            self.end_headers()
            return

        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length).decode('utf-8')
        params = parse_qs(post_data)
        user_password = params.get('password', [''])[0]

        # SECURE COMPARISON (Prevents timing attacks)
        if secrets.compare_digest(user_password, CORRECT_PASSWORD):
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(SUCCESS_HTML.encode('utf-8'))
        else:
            self.send_response(401)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b"<html><body style='text-align:center; font-family:sans-serif;'><h1>❌ Incorrect Password</h1><a href='/'>Try again</a></body></html>")

if __name__ == '__main__':
    print(f"[*] Captive Portal active on http://{GATEWAY_IP}:8080")
    server = ThreadedHTTPServer(('0.0.0.0', 8080), RequestHandler)
    server.serve_forever()
