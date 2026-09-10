from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
import os
import secrets

# --- Configuration ---
# Load the permanent gateway IP set by hotspot.sh
GATEWAY_IP = os.environ.get('GATEWAY_IP', '192.168.1.1')
# Load the secured password from the temporary file
PASS_FILE = os.environ.get('PREFIX', '/data/data/com.termux/files/usr') + '/tmp/hp_pass'

# Modern, Responsive HTML Template
PORTAL_HTML = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hotspot Login</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe|", sans-serif; background: #f0f2f5; margin: 0; display: flex; justify-content: center; align-items: center; height: 100vh; }}
        .card {{ background: white; padding: 30px; border-radius: 16px; box-shadow: 0 10px 25px rgba(0,0,0,0.1); width: 90%; max-width: 350px; text-align: center; }}
        h2 {{ color: #1c1e21; margin-bottom: 10px; }}
        p {{ color: #606770; margin-bottom: 20px; }}
        input {{ width: 100%; padding: 12px; margin: 10px 0; border: 1px solid #ddd; border-radius: 8px; box-sizing: border-box; font-size: 16px; }}
        button {{ width: 100%; padding: 12px; background: #0084ff; color: white; border: none; border-radius: 8px; font-size: 16px; font-weight: bold; cursor: pointer; transition: background 0.2s; }}
        button:hover {{ background: #0073e6; }}
        .footer {{ margin-top: 20px; font-size: 12px; color: #90949c; }}
    </style>
</head>
<body>
    <div class="card">
        <h2>Wi-Fi Login</h2>
        <p>Enter your password to connect</p>
        <form action="/login" method="POST">
            <input type="password" name="password" placeholder="Password" required autofocus>
            <button type="submit">Connect</button>
        </form>
        <div class="footer">Gateway: {GATEWAY_IP}</div>
    </div>
</body>
</html>
"""

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    """Allows the server to handle multiple concurrent requests (Non-blocking)."""
    daemon_threads = True
    def server_bind(self):
        # Allows immediate restart of the server without waiting for TIME_WAIT
        self.socket.setsockopt(1, 2, 1) # SO_REUSEADDR
        super().server_bind()

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Serve the HTML portal."""
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(PORTAL_HTML.encode('utf-8'))

    def do_POST(self):
        """Handle the login attempt."""
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode('utf-8')
        
        # Parse the password from form data
        from urllib.parse import parse_qs
        params = parse_qs(post_data)
        user_password = params.get('password', [''])[0]

        # 1. Load correct password from secure file
        try:
            with open(PASS_FILE, 'r') as f:
                correct_password = f.read().strip()
        except FileNotFoundError:
            correct_password = "12345678" # Fallback

        # 2. SECURE COMPARISON: Use secrets.compare_digest to prevent timing attacks
        if secrets.compare_digest(user_password, correct_password):
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b"<html><body style='text-align:center; padding-top:50px; font-family:sans-serif;'><h1>✅ Success!</h1><p>You are now connected.</p></body></html>")
        else:
            self.send_response(401)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b"<html><body style='text-align:center; padding-top:50px; font-family:sans-serif;'><h1>❌ Error</h1><p>Incorrect password.</p><a href='/'>Try again</a></body></html>")

def run(server_class=ThreadedHTTPServer, handler_class=RequestHandler, port=8080):
    print(f"[*] Starting Multi-threaded Captive Portal on port {port}...")
    server = server_class(('0.0.0.0', port), handler_class)
    server.serve_forever()

if __name__ == '__main__':
    run()
