"""
serve_assets.py — HTTP server for beta distribution.

Serves the Flutter asset files so testers' iPhones fetch live deal data
instead of a stale bundled snapshot.

Usage:
  python serve_assets.py

Then expose publicly with ngrok:
  ngrok http 8080 --domain=YOUR-DOMAIN.ngrok-free.app
"""
import http.server
import socketserver
from pathlib import Path

PORT = 8080
ASSETS_DIR = Path(__file__).resolve().parent / "promo_viewer" / "assets"


class AssetHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ASSETS_DIR), **kwargs)

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def log_message(self, fmt, *args):
        print(f"[{self.log_date_time_string()}] {fmt % args}")


if __name__ == "__main__":
    if not ASSETS_DIR.exists():
        print(f"[ERROR] Assets folder not found: {ASSETS_DIR}")
        raise SystemExit(1)

    files = [f.name for f in ASSETS_DIR.iterdir() if f.is_file()]
    print(f"Serving {ASSETS_DIR}")
    print(f"Files: {', '.join(files)}")
    print(f"Local:  http://localhost:{PORT}/all_promotions.json")
    print()
    print("To expose publicly, run in a second terminal:")
    print(f"  ngrok http {PORT} --domain=YOUR-DOMAIN.ngrok-free.app")
    print()

    with socketserver.TCPServer(("", PORT), AssetHandler) as httpd:
        httpd.allow_reuse_address = True
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.")
