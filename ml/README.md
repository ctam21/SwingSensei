Phase model (BiLSTM) training

1) Collect data
   - Export labeled swings from the app (Export Features JSON). Copy JSONs to ml/datasets/phases_user/.
   - Optional: Process GolfDB with BlazePose to create the same JSON format and put into ml/datasets/phases_golfdb/.

2) Train BiLSTM
   - Install: pip install -r ml/requirements.txt
   - Run: python ml/train_phases_lstm.py --data ml/datasets/phases_user/ --out ml/outputs/phase_bilstm.pt

   The script learns from per-frame features (xy + velocities + angles) and 8-phase labels.

3) Export to CoreML (coming next)
   - Convert the trained .pt to CoreML for on-device use, then add the .mlmodel to GolfAI/GolfAI/Models.

SwingSensei ML pipeline (club keypoints + ball)

Directory layout
- ml/
  - datasets/
    - club_keypoints/  # YOLO-pose format after export
    - ball/            # YOLO detection format after export
  - config/
    - club_keypoints.yaml   # dataset config for YOLOv8 pose (3–4 keypoints)
    - ball.yaml              # dataset config for YOLOv8 detect
  - train_club_keypoints.py  # trains and exports CoreML
  - train_ball.py            # trains and exports CoreML

Requirements
- Python 3.10+
- pip install -r requirements.txt

Labeling (Label Studio)
1) Launch Label Studio (pip install label-studio; label-studio start).
2) Create project "Club Keypoints" with 3–4 keypoints inside a single bounding box:
   - butt (grip end)
   - mid (mid-shaft)
   - face (leading edge near hosel)
   - toe (optional)
3) Create project "Ball" with a single class: ball. Boxes tight around the golf ball/tee.
4) Export to YOLO format (for keypoints export to COCO keypoints or Ultralytics keypoints JSON; the script accepts both).
5) Place exported folders into ml/datasets/club_keypoints and ml/datasets/ball.

Training
Club keypoints (YOLOv8 pose):
  python ml/train_club_keypoints.py --data ml/config/club_keypoints.yaml --epochs 60 --img 640

Ball detector (YOLOv8 detect):
  python ml/train_ball.py --data ml/config/ball.yaml --epochs 40 --img 640

Exported models
- Outputs will be written to ml/outputs/*.mlmodel
- Copy ClubKeypoints.mlmodel into Xcode at GolfAI/Models/ (create the folder if needed). Xcode will compile to .mlmodelc and bundle it.
- Ball model usage is optional for now (we ship a classical fallback). If trained, add BallDetector.mlmodel similarly.

iOS integration
- Club keypoints are loaded by GolfAI/ClubKeypointDetector.swift (searches for ClubKeypoints.mlmodelc in the app bundle).
- In processing, we write predicted points to joints 101.. and draw them in PoseOverlayView.

Notes
- Start with ~1000 labeled frames for club keypoints and ~500 for ball across varied lighting/cameras.
- Keep clip-level constant: each clip has near-constant club length. The app enforces length continuity via Kalman + constraints.


