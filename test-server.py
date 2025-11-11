from flask import Flask, jsonify
import random
import time

app = Flask(__name__)

# Variable global para controlar el estado del servidor
server_mode = "healthy"  # healthy, error503, error404

@app.route('/')
def home():
    return jsonify({
        "status": "running",
        "mode": server_mode,
        "timestamp": time.time()
    })

@app.route('/health')
def health():
    """Endpoint principal a monitorizar"""
    if server_mode == "error503":
        return jsonify({"error": "Service Unavailable"}), 503
    elif server_mode == "error404":
        return jsonify({"error": "Not Found"}), 404
    else:
        return jsonify({"status": "healthy"}), 200

@app.route('/set-mode/<mode>')
def set_mode(mode):
    """Endpoint para cambiar el estado del servidor"""
    global server_mode
    if mode in ["healthy", "error503", "error404"]:
        server_mode = mode
        return jsonify({"message": f"Mode set to {mode}"}), 200
    return jsonify({"error": "Invalid mode"}), 400

@app.route('/random-error')
def random_error():
    """Simula errores aleatorios (para pruebas avanzadas)"""
    status_code = random.choice([200, 200, 200, 503, 404])
    return jsonify({"random_status": status_code}), status_code

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
