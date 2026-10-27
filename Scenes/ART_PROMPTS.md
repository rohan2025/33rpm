# Making the scene art with AI

> The shipped scenes were made exactly this way in ChatGPT. To restyle a scene while keeping the turntable
> where it is, ask ChatGPT to **edit the existing room photo** ("keep the exact same composition, camera angle
> and every object in the same position… only change the mood to …"). The record and tonearm then line up
> with no changes to scene.json.

The app ships with drawn placeholders. Replace them by dropping PNGs named after each slot into
`Scenes/Evening/` (menu bar → **Open Scenes Folder**). The desktop updates within a second, no rebuild needed.

Works with ChatGPT image generation, Midjourney, Ideogram, Firefly, Flux, etc.

## Recommended: one painted room + a few live pieces

Separate AI images rarely share the same lighting and angle, which is what makes a collage look fake.
So generate **one photoreal room** with everything static baked in, and keep only the moving
pieces separate:

| File | What it is | Why separate |
|---|---|---|
| `background.png` | The whole room, including the console, plant, lamp and the turntable body with an empty platter | One image, one light source, so it looks real |
| `record.png` | Top-down vinyl | Spins |
| `tonearm.png` | Top-down tonearm | Moves |
| `crate.png` | Front of the wooden crate | Old sleeves slide in behind it (step 4) |

Then in `Scenes/Evening/scene.json`, hide the placeholder pieces your painting already contains by
adding `"hidden": true` to `plant`, `console`, `deck_base`, `platter` and `lid`.
Finally, line the record up with the painted platter (see "Aligning" below).

### Shared style line

Paste this at the end of every prompt so the pieces match:

> photorealistic, late evening, warm amber lamp light, deep soft shadows, cinematic, moody, subtle film grain,
> 35mm photograph, rich walnut and brushed brass tones

### background.png — 3:2, at least 3000×2000 (3840×2560 if you use Full size)

> Interior photograph of a cosy living room at night. A low mid-century walnut record console stands against a
> dark plaster wall, seen from slightly above and a little to the side (camera at standing height, looking down
> about 30°). On the console, left of centre, sits a matte black turntable with brushed brass trim. The platter
> is **empty: no record, no tonearm, no dust cover**. Behind the turntable, empty wall space where an album
> sleeve could lean. On the right of the console, empty space for a small wooden crate. A brass floor lamp with
> a fabric shade on the far right casts a warm pool of light on the wall. A potted plant beside the console.
> Nothing on the wall. [style line]

If the AI still draws a tonearm or record, erase it with a generative-fill / magic-eraser tool
(ChatGPT edit, Photoshop, Canva, or Pixelmator).

### record.png — square, 2000×2000, transparent

> Top-down orthographic product photo of a black vinyl LP record, perfectly circular and centred, filling the
> frame. Fine concentric grooves with a soft sheen, a plain dark centre with no printed label, small spindle
> hole. Isolated on a transparent background. [style line]

The album art label is added on top by the app, covering the centre 36%.

### tonearm.png — tall, 400×2000, transparent

> Top-down orthographic product photo of a turntable tonearm laid perfectly vertical. A round pivot base with
> a black counterweight at the **top**, a thin brushed-brass arm tube going straight down, and a black
> headshell with a cartridge at the **bottom**. Centred and isolated on a transparent background. [style line]

In `scene.json`, set the tonearm's `anchor` to the pivot's position as a fraction of the image,
for example `[0.5, 0.08]` if the pivot centre is 8% down from the top.

### crate.png — 3:2, 1200×800, transparent

> Front view of a small wooden record crate made of warm oak slats with gaps between them, open at the top,
> seen from slightly above to match a room photographed from standing height. Isolated on a transparent
> background. [style line]

### Other scenes

Each scene folder takes its own `background.png` (and any other slots); the others fall back to placeholders.

- **RainyWindow** — same prompt as Evening, but: *"a tall window on the left wall shows a rainy night city
  with blurred warm and cool lights, rain on the glass, cooler blue-grey room tones, the floor lamp dimmer"*.
  Keep the window around the top-left third so the rain effect (`rain` frame in its scene.json) lines up.
- **Minimal** — *"a single low light-oak shelf against a plain warm-grey wall, soft overhead light,
  lots of empty space, nothing else in the room"*. The turntable and crate go on the shelf.

### ambient.mp4 (optional) — 5–15 s seamless loop, 1920×1080 or larger

Subtle motion only: rain running down glass, slow city bokeh, a candle flame on black. It's blended with
`screen` by default, so dark areas disappear and only the light shows. Keep it small (H.264/HEVC, a few MB).

### Optional

- `default_label.png` (square): a vintage cream record label with "33⅓", shown when nothing is playing.
- `sleeve_shadow.png`: optional. The app already casts a soft shadow away from `crate.lightFrom`; add this slot only for a custom one.
- `lamp_glow.png`: a soft radial light, transparent edges. If your painted room already glows, set its
  `opacity` low (0.2–0.3) so it adds flicker without washing out the scene.

## Transparent backgrounds

If your AI tool won't output transparency, generate on plain white, then in Finder right-click the
PNG → **Quick Actions → Remove Background** (macOS 14+).

## Aligning the live pieces with the painting

1. Set the deck to cover the painted platter: in `scene.json` adjust `deck.center` (canvas points,
   the canvas is 1500×1000 regardless of image size) and `deck.tilt` until the record's ellipse matches the
   painted platter. Lower tilt = rounder, higher = flatter.
2. Render a preview without touching the desktop:
   ```bash
   build/33rpm.app/Contents/MacOS/33rpm --snapshot ~/Desktop/check.png --playing --progress 0.3
   ```
3. Adjust the `record` and `tonearm` frames inside `deck.layers` until the record sits on the platter
   and the tonearm pivot sits where the painted arm base would be. Use `tonearm.startAngle` / `endAngle`
   so the stylus starts at the outer edge and ends just outside the label.

## The receiver

The vintage receiver in the console was generated with FLUX.1 Kontext (edit: "inside the open middle shelf of the
console, place a vintage 1970s hi-fi receiver…"), cut out to `Assets/receiver_patch.png` with its display blanked,
and composited into each room by `scripts/composite_receiver.py`. If you replace a room photo, rerun the script
or remove the `receiver` block from that scene's scene.json.
