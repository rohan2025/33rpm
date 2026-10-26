# 33rpm launch kit

Everything below is a draft: edit freely before posting. Images are in this folder.

## Before you post (checklist)

- [ ] Record a 15–30 s screen video (shot list below). This is the single most important asset.
- [ ] Build the release: `scripts/package.sh` → `build/release/33rpm-1.0.0.dmg` and `33rpm-bridge-1.0.0.zip`.
- [x] Download page: https://github.com/rohan2025/33rpm/releases/latest (public repo, MIT license, v1.0.0 DMG attached).
- [ ] Optional: submit `33rpm-bridge-1.0.0.zip` to the Chrome Web Store ($5 one-time developer fee, review takes a few days)
      so people can install the extension with one click instead of "Load unpacked".
- [ ] Optional: Apple Developer Program ($99/yr) + notarization removes the "can't verify developer" warning.
      Without it, people open it via System Settings → Privacy & Security → Open Anyway (explained in the DMG's Read Me).
- [ ] Try the DMG on a second Mac or a fresh user account if you can.

## Demo video shot list (Cmd+Shift+5 → Record Selected Portion)

Set Size → Full, Scene → Evening, ambient effects on. Close windows so the desktop shows.

1. **0–4 s** Nothing playing: the quiet room, worn sleeve on the wall, arm at rest.
2. **4–9 s** Press play in YouTube Music: arm swings onto the record, record spins up, album art fades onto the label and the sleeve.
3. **9–14 s** Skip a song: the old sleeve arcs into the crate, the new one appears.
4. **14–20 s** Hover the crate and flip through a few sleeves; click one to play it.
5. **20–25 s** Point at the turntable → controls fade in → pause (record slows to a stop, arm lifts).
6. **25–30 s** Switch to Rainy Window from the menu bar, play again.

Tip: export at 1080p, trim in QuickTime (Cmd+T), keep it silent or add a short music bed you have rights to.

## X (Twitter)

**Post** (with the video):

> I made my Mac desktop into a little listening room 🎶
>
> 33rpm puts a turntable on your wallpaper that plays along with YouTube Music: the record spins at 33⅓, the arm tracks the song, and every track you play ends up in the crate.
>
> Free, open source, runs 100% locally.

**Reply thread:**

1. > Details I'm weirdly proud of:
   > • the tonearm creeps inward as the song plays
   > • the record eases to a stop when you pause
   > • old sleeves arc into a wooden crate, hover to flip through, click to replay
   > • dust drifts in the lamp light 🕯️
2. > Click the turntable to pause, click a song on the "Up Next" card on the wall to jump to it. Three rooms: Evening, Rainy Window, Minimal.
3. > How it works: a tiny Chrome extension reads what YouTube Music is playing and sends it to a native Swift app over localhost. No accounts, no analytics, ~0% CPU (it's all Core Animation).
4. > Download (macOS 14+, free): https://github.com/rohan2025/33rpm

## Product Hunt

- **Name:** 33rpm
- **Tagline** (≤60): `A turntable on your Mac desktop that plays along with YouTube Music`
- **Description** (≤260):
  > 33rpm turns your Mac wallpaper into a cozy listening room. A record spins at 33⅓ with your current album on the label, the arm tracks the song, played sleeves stack in a crate you can flip through, and you can pause or skip right from the desktop.
- **Topics:** Mac, Music, Design Tools (or Productivity)
- **Thumbnail:** `ph-thumbnail-240.png`
- **Gallery (1270×760, these are 2× so they stay sharp):** `1-evening.jpg`, `2-crate-browse.jpg`, `3-rainy-window.jpg`, `4-minimal.jpg`, `5-idle.jpg`, plus the video.
- **Pricing:** Free
- **Links:** Website / download: https://github.com/rohan2025/33rpm
- **Maker's first comment:**
  > Hi Product Hunt 👋 I listen to YouTube Music all day and missed the ritual of a record player, so I built one into my desktop.
  >
  > It's a native Swift app (Core Animation, so it sits at ~0% CPU) plus a small Chrome extension that tells it what's playing. Everything stays on your Mac: no account, no analytics, no cloud.
  >
  > Things to try: hover the crate to flip through what you've played and click a sleeve to replay it, click the turntable to pause, and switch to the Rainy Window room at night.
  >
  > The rooms are AI-generated and you can drop in your own art; each scene is just a folder of PNGs and a JSON file. Would love to hear which room you'd want next!

## Chrome Web Store listing (for 33rpm-bridge-1.0.0.zip)

- **Name:** 33rpm Bridge
- **Summary** (≤132): `Shows what's playing in YouTube Music on the 33rpm turntable for macOS. Talks only to the 33rpm app on your own computer.`
- **Category:** Entertainment
- **Description:**
  > 33rpm Bridge connects YouTube Music to 33rpm, a free macOS app that puts an animated turntable on your desktop.
  >
  > It reads the current song (title, artist, album art, play state and position) and the Up Next queue from your YouTube Music tab and sends it to the 33rpm app over a local connection (127.0.0.1) protected by a pairing token. 33rpm can send back play/pause, next, previous and "play this song".
  >
  > Nothing is sent anywhere else. No accounts, no analytics, no tracking.
- **Single purpose:** Relay YouTube Music playback state to the user's local 33rpm desktop app and accept playback commands from it.
- **Permission justifications:**
  - `storage`: saves the pairing token and port the user enters.
  - `alarms`: wakes the background worker to reconnect to the local app if it restarts.
  - `scripting`: re-attaches to already-open YouTube Music tabs after install, and switches songs inside the YouTube Music page when the user picks one in 33rpm.
  - Host `https://music.youtube.com/*`: reads the now-playing info and queue on YouTube Music, and nowhere else.
  - Connects only to `ws://127.0.0.1` (the user's own computer).
- **Privacy / data usage:** Collects no user data. Nothing is sold, transferred or used for anything other than the single purpose above.
- **Images:** icon `extension/icon128.png`, screenshots `cws-screenshot-1..3.png` (1280×800), small promo tile `cws-promo-440x280.png`.

## Notes

- The screenshots use fictional album covers and track names (made from the app's own room photos), so no real artists appear.
- If you open-source it, the room art and covers in `Scenes/` and `Assets/` were generated for this project with ChatGPT.
