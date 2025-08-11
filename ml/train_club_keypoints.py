import argparse
from pathlib import Path
from ultralytics import YOLO
import coremltools as ct


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--data', required=True)
    parser.add_argument('--epochs', type=int, default=60)
    parser.add_argument('--img', type=int, default=640)
    parser.add_argument('--model', default='yolov8n-pose.pt')
    parser.add_argument('--out', default='ml/outputs/ClubKeypoints.mlmodel')
    args = parser.parse_args()

    model = YOLO(args.model)
    results = model.train(data=args.data, epochs=args.epochs, imgsz=args.img)
    best = Path(results.save_dir) / 'weights/best.pt'

    # Export to CoreML
    exported = YOLO(best).export(format='coreml', imgsz=args.img, dynamic=False)
    mlmodel = ct.models.MLModel(exported)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(out_path))
    print(f'Saved CoreML model to {out_path}')


if __name__ == '__main__':
    main()


