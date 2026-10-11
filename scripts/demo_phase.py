#!/usr/bin/env python3
"""Where to cut a recording of the widget-demo preview so the clip starts 0.3 s into a cycle.

  scripts/demo_phase.py <raw.mov> --skip 3 --period 12 --expand-at 4.0

Prints the cut time in seconds. The demo's list wells out at `--expand-at` seconds into every
cycle; the panel then covers the left part of the frame for less than half of the cycle. So the
per-pixel median of one period is the collapsed widget, and the first frame that differs from it
on the left is the expansion. This replaces a guess of screencapture's start-up delay, which
varies by a second or more.
"""
import argparse
import subprocess
import sys

import numpy as np

FPS = 20
WIDTH = 96


def expanded_flags(frames: np.ndarray) -> np.ndarray:
    """frames: (n, h, w) greyscale. True where the left part differs from the median frame."""
    left = frames[:, :, : int(frames.shape[2] * 0.7)].astype(np.float32)
    reference = np.median(left, axis=0)
    diff = np.abs(left - reference).mean(axis=(1, 2))
    threshold = max(4.0, float(np.percentile(diff, 50)) * 3)
    return diff > threshold


def cut_from_flags(flags, fps: float, skip: float, period: float, expand_at: float, lead: float = 0.3) -> float:
    """flags[i]: expanded at skip + i / fps. Returns the cut (>= skip) at `lead` s into a cycle."""
    rising = [i for i in range(1, len(flags)) if flags[i] and not flags[i - 1]]
    if not rising:
        raise ValueError("the list never wells out in the recording")
    expand_time = skip + rising[0] / fps
    cycle_start = expand_time - expand_at
    return round(skip + (cycle_start + lead - skip) % period, 3)


def read_frames(path: str, skip: float, period: float) -> np.ndarray:
    """One period (plus a second) from `skip`, as small greyscale frames."""
    size = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "stream=width,height",
         "-of", "csv=p=0", path], check=True, capture_output=True, text=True,
    ).stdout.strip().split(",")
    height = int(round(int(size[1]) * WIDTH / int(size[0]) / 2) * 2)
    video = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-ss", str(skip), "-t", str(period + 1), "-i", path,
         "-vf", f"fps={FPS},scale={WIDTH}:{height},format=gray", "-f", "rawvideo", "-"],
        check=True, capture_output=True,
    )
    data = np.frombuffer(video.stdout, dtype=np.uint8)
    frame = WIDTH * height
    return data[: len(data) // frame * frame].reshape(-1, height, WIDTH)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("raw")
    parser.add_argument("--skip", type=float, required=True)
    parser.add_argument("--period", type=float, required=True)
    parser.add_argument("--expand-at", type=float, required=True)
    args = parser.parse_args()
    frames = read_frames(args.raw, args.skip, args.period)
    print(cut_from_flags(expanded_flags(frames), FPS, args.skip, args.period, args.expand_at))
    return 0


if __name__ == "__main__":
    sys.exit(main())
