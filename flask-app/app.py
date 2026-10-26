import os
from flask import Flask, jsonify

app = Flask(__name__)

VERSION = os.getenv("APP_VERSION", "dev")

@app.get("/")
def home():
    return jsonify(
        application="Registry Blue-Green Demo",
        version=VERSION,
        status="running"
    )

@app.get("/health")
def health():
    return jsonify(
        status="healthy",
        version=VERSION
    ), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
