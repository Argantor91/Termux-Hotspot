from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs
import os

# Get the permanent gateway IP set by hotspot.sh
GATEWAY_IP = os.environ.get('GATEWAY_IP', '192.168.1.1')

PORTAL_HTML = f"""<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Connect to Hotspot</title>
    <style>
        body {{ font-family: sans-serif; text-align: center; padding: 20px; background: #f4f4f4; }}
        .card {{ background: white; padding: 20px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); max-width: 300px; margin: 0 auto; }}
        input {{ width: 100%; padding: 10px; margin: 10px 0; border: 1px solid #ddd; border-radius: 5px; box-sizing: border-box; }}
        button {{ width: 100%; padding: 10px; background: #007bff; color: white; border: none; border-radius: 5px; cursor: pointer; font-size: 16px; }}
        a {{ color: #007bff; text-decoration: none; margin-top: 10px; display: block; }}
    </style>
</head>
<body>
    <div class="card">
        <h2>Termux Hotspot</h2>
        <p>Enter password to connect:</p>
        <form action="/login" method="POST">
            <input type="password" name="password" placeholder="Password" required>
            <button type="submit">Connect</button>
        </form>
        <a href="http://{GATEWAY_IP}/info">Network Info & Settings</a>
    </div>
</body>
</html>
"""

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # Basic routing for future functions
        if self.path == '/info':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(f"<html><body><h1>Info at {GATEWAY_IP}</h1></body></html>".encode())
        else:
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(PORTAL_HTML.encode())

    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        form = parse_qs(post_data.decode('utf-8'))
        password = form.get('password', [''])[0]
        
        expected_pass = os.environ.get('HOTSPOT_PASSWORD', '12345678')
        
        if password == expected_pass:
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b'<html><body><h1>Connected!</h1></body></html>')
        else:
            self.send_response(401)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b'<html><body><h1>Wrong Password!</h1></body></html>')

def run(server_class=HTTPServer, handler_class=RequestHandler, port=8080):
    print(f"Starting Captive Portal on port {port}...")
    server = server_class(('0.0.0.0', port), handler_class)
    server.serve_forever()

if __name__ == '__main__':
    run()
