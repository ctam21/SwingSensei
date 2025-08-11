import argparse
import json
from pathlib import Path
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader


class PhaseDataset(Dataset):
    def __init__(self, json_files, window=120):
        self.samples = []
        for jf in json_files:
            data = json.loads(Path(jf).read_text())
            feats = np.array(data["features"], dtype=np.float32)  # [T, D]
            T = feats.shape[0]
            phases = data["phases"]
            # Build per-frame labels from phase indices using simple ranges
            labels = np.zeros((T,), dtype=np.int64)
            order = ["address","takeaway","midBackswing","top","midDownswing","impact","followThrough","finish"]
            idxs = [max(0, int(phases[k])) for k in order]
            for c in range(len(order)):
                start = idxs[c]
                end = idxs[c+1] if c+1 < len(order) else T-1
                labels[start:max(start+1,end+1)] = c
            # Slice into windows
            for s in range(0, T, window):
                e = min(T, s+window)
                x = feats[s:e]
                y = labels[s:e]
                self.samples.append((x, y))

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, i):
        x, y = self.samples[i]
        return torch.from_numpy(x), torch.from_numpy(y)


class BiLSTM(nn.Module):
    def __init__(self, input_dim, hidden=96, layers=2, num_classes=8):
        super().__init__()
        self.lstm = nn.LSTM(input_size=input_dim, hidden_size=hidden, num_layers=layers, batch_first=True, bidirectional=True)
        self.head = nn.Linear(hidden*2, num_classes)

    def forward(self, x):  # x: [B,T,D]
        out, _ = self.lstm(x)
        logits = self.head(out)  # [B,T,C]
        return logits


def pad_collate(batch):
    xs, ys = zip(*batch)
    lens = [t.shape[0] for t in xs]
    maxT = max(lens)
    D = xs[0].shape[1]
    X = torch.zeros((len(xs), maxT, D), dtype=torch.float32)
    Y = torch.full((len(xs), maxT), fill_value=-100, dtype=torch.long)
    for i, (x,y) in enumerate(batch):
        T = x.shape[0]
        X[i,:T,:] = x
        Y[i,:T] = y
    return X, Y


def train(args):
    files = [str(p) for p in Path(args.data).glob('**/swing_features_*.json')]
    if len(files) == 0:
        raise RuntimeError(f"No JSONs found under {args.data}")
    ds = PhaseDataset(files, window=args.window)
    dl = DataLoader(ds, batch_size=args.batch_size, shuffle=True, collate_fn=pad_collate)

    # Infer feature dim from first file
    with open(files[0]) as f:
        d0 = json.load(f)
    input_dim = len(d0["features"][0])

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    model = BiLSTM(input_dim=input_dim, hidden=args.hidden, layers=args.layers).to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr)
    crit = nn.CrossEntropyLoss(ignore_index=-100)

    model.train()
    for epoch in range(args.epochs):
        total = 0.0
        n = 0
        for X, Y in dl:
            X = X.to(device)
            Y = Y.to(device)
            opt.zero_grad()
            logits = model(X)  # [B,T,C]
            loss = crit(logits.view(-1, logits.shape[-1]), Y.view(-1))
            loss.backward()
            opt.step()
            total += loss.item()
            n += 1
        print(f"epoch {epoch+1}: loss={total/max(1,n):.4f}")

    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    torch.save({"state": model.state_dict(), "input_dim": input_dim, "hidden": args.hidden, "layers": args.layers}, args.out)
    print(f"Saved PyTorch model: {args.out}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True, help='Dir with exported swing_features_*.json')
    ap.add_argument('--out', default='ml/outputs/phase_bilstm.pt')
    ap.add_argument('--epochs', type=int, default=15)
    ap.add_argument('--batch_size', type=int, default=8)
    ap.add_argument('--hidden', type=int, default=96)
    ap.add_argument('--layers', type=int, default=2)
    ap.add_argument('--lr', type=float, default=1e-3)
    ap.add_argument('--window', type=int, default=120)
    args = ap.parse_args()
    train(args)


if __name__ == '__main__':
    main()


