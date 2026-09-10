from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
import os
import secrets

# Configuration
GATEWAY_IP = os.environ.get('GATEWAY_IP', '192.168.1.1')
PASS_FILE = os.environ.get('PREFIX', '/data/data/com.termux/files/usr') + '/tmp/hp_pass'

PORTAL_HTML = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Termux Hotspot</title>
    <style>
        body {{ font-family: -apple-system, sans-serif; text-align: center; background: #f4f4f4; padding: 20px; }}
        .card {{ background: white; padding: 30px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); max-width: 350px; margin: 0 auto; }}
        input {{ width: 100%; padding: 12px; margin: 15px 0; border: 1px solid #ddd; border-radius: 8px; box-sizing: border-box; font-size: 16px; }}
        button {{ width: 100%; padding: 12px; background: #007bff; color: white; border: none; border-radius: 8px; font-size: 16px; cursor: pointer; }}
        button:active {{ background: #0056b3; }}
        .info {{ font-size: 12px; color: #888; margin-top: 20px; }}
    </style>
</head>
<body>
    <div class="card">
        <h2>📶 Hotspot Login</h2>
        <p>Please enter the Wi-Fi password</p>
        <form action="/login" method="POST">
            <input type="password" name="password" placeholder="Password" required autofocus>
            <button type="submit">Connect</button>
        </form>
        <div class="info">Gateway: {GATEWAY_IP}</div>
    </div>
</body>
</html>
"""

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    """Handles multiple requests simultaneously."""
    daemon_threads = True

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(PORTAL_HTML.encode())

    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode('utf-8')
        
        # Extract password from form data
        from urllib.parse import parse_qs
        params = parse_qs(post_data)
        user_pass = params.get('password', [''])[0]

        # Secure Password Retrieval
        try:
            with open(PASS_FILE, 'r') as f:
                correct_pass = f.read().strip()
        except FileNotFoundError:
            correct_pass = "12345678" # Fallback

        # Secure Timing-Attack resistant comparison
        if secrets.compare_digest(user_pass, correct_pass):
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b"<html><body style='text-align:center; padding:50px;'><h1>✅ Connected!</h1><p>You can now browse the internet.</p></body></html>")
        else:
            self.send_response(401)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b"<html><body style='text-align:center; padding:50px;'><h1>❌ Wrong Password</h1><a href='/'>Try again</a></body></html>")

def run():
    server = ThreadedHTTPServer(('0.0.0.0', 8080), RequestHandler)
    print(f"[*] Captive Portal running on port 8080 (Threaded)")
    server.serve_forever()

if __name__ == '__main__':
    run()
