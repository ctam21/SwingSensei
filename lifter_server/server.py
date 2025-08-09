from flask import Flask, request, jsonify
import numpy as np

app = Flask(__name__)

@app.post("/lift")
def lift():
    data = request.get_json(force=True)
    poses = np.array(data.get("poses2d", []), dtype=float)
    fps = float(data.get("fps", 20.0))
    # Validate shape [T,17,2]
    if poses.ndim != 3 or poses.shape[1] != 17 or poses.shape[2] != 2:
        return jsonify({"poses2d_stabilized": data.get("poses2d", [])})
    # Simple temporal moving average smoothing (window 5)
    T = poses.shape[0]
    out = poses.copy()
    w = 5
    for t in range(T):
        s = max(0, t - w//2)
        e = min(T, t + w//2 + 1)
        out[t] = poses[s:e].mean(axis=0)
    return jsonify({"poses2d_stabilized": out.tolist()})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5050)
