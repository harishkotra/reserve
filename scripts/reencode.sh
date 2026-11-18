#!/usr/bin/env bash
# Re-times the already-rendered slides to the narration (no Chrome pass).
set -euo pipefail
cd "$(dirname "$0")/.."
D=assets/slides; OUT=assets/video
rm -rf "$OUT/clips"; mkdir -p "$OUT/clips"
declare -a DUR=(6 8 7 9 7.5 7.5 8 8 6)
i=0
for f in "$D"/0*.png; do
  ffmpeg -y -loglevel error -loop 1 -i "$f" -t "${DUR[$i]}" \
    -vf "scale=1920:1080,zoompan=z='min(1.0+0.00035*on,1.03)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1920x1080:fps=30,format=yuv420p" \
    -c:v libx264 -preset medium -crf 18 "$OUT/clips/$(printf %02d $i).mp4"
  i=$((i+1))
done
: > "$OUT/list.txt"; for c in "$OUT"/clips/*.mp4; do echo "file '$PWD/$c'" >> "$OUT/list.txt"; done
ffmpeg -y -loglevel error -f concat -safe 0 -i "$OUT/list.txt" -c copy "$OUT/reserve-demo-silent.mp4"
ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/reserve-demo-silent.mp4"
