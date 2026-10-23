import http.server
import json
import os
import sys
from datetime import datetime, timezone

PORT = int(os.environ.get("PORT", "9099"))
LOG_FILE = os.environ.get("LOG_FILE", "/var/log/alerts.log")

os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

class AlertHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length).decode("utf-8")
        
        timestamp = datetime.now(timezone.utc).isoformat()
        log_line = f"[ALERT_RECEIVED] timestamp={timestamp} remote={self.client_address[0]} payload={body}\n"
        
        # Print to stdout for Docker logs and Promtail / Loki
        sys.stdout.write(log_line)
        sys.stdout.flush()
        
        # Append to file
        try:
            with open(LOG_FILE, "a", encoding="utf-8") as f:
                f.write(log_line)
        except Exception as e:
            sys.stderr.write(f"Error writing to {LOG_FILE}: {e}\n")
            
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b"{\"status\":\"received\"}")

    def log_message(self, format, *args):
        pass

if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", PORT), AlertHandler)
    print(f"[ALERT_SINK] Listening on port {PORT}...", flush=True)
    server.serve_forever()
