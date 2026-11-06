#!/usr/bin/env bash
# Builds a static storefront listing where each product photo should sit exactly on the
# marketplace's frame. Every photo loads and every frame draws, but two photos are placed a few
# pixels off their frames, which only a per-item measure shows.
set -euo pipefail

mkdir -p site
cat > TICKET.md <<'MD'
# ABC-1: Marketplace listing photos

The marketplace rejects a listing when a product photo isn't exactly inside its frame. The
listing page draws each frame (dashed) and places the photo on it; every photo must sit on its
frame, edge to edge.
MD

# One card per product: the frame and the photo are both absolutely placed in a 240x240 card.
# frame left/top/size, then photo left/top/size.
card() {
  local name="$1" fl="$2" ft="$3" fs="$4" pl="$5" pt="$6" ps="$7" colour="$8"
  cat <<HTML
    <figure class="card">
      <div class="frame" style="left: ${fl}px; top: ${ft}px; width: ${fs}px; height: ${fs}px"></div>
      <div class="photo" role="img" aria-label="${name}" style="left: ${pl}px; top: ${pt}px; width: ${ps}px; height: ${ps}px; background: ${colour}">${name}</div>
      <figcaption>${name}</figcaption>
    </figure>
HTML
}

{
  cat <<'HTML'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Listing photos</title>
    <style>
      body { font-family: system-ui, sans-serif; margin: 24px; }
      .grid { display: grid; grid-template-columns: repeat(4, 240px); gap: 24px; }
      .card { position: relative; width: 240px; height: 270px; margin: 0; }
      .frame { position: absolute; border: 2px dashed #333; box-sizing: border-box; }
      .photo { position: absolute; display: grid; place-items: center; color: #fff; font-weight: 600; }
      figcaption { position: absolute; top: 246px; left: 0; font-size: 14px; }
    </style>
  </head>
  <body>
    <h1>Listing photos</h1>
    <div class="grid">
HTML
  card "Canvas tote" 20 20 200 20 20 200 "#5b7f6a"
  card "Ceramic mug" 20 20 200 20 20 200 "#7a5b8f"
  card "Desk lamp" 20 20 200 32 20 200 "#8f6a3c"
  card "Linen notebook" 20 20 200 20 34 200 "#3c6a8f"
  cat <<'HTML'
    </div>
  </body>
</html>
HTML
} > site/listing.html
