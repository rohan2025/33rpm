# 33rpm launch kit

Everything below is a draft: edit freely before posting. Images are in this folder.

## Before you post (checklist)

- [x] Demo video recorded (Cap). A silent web version is at the top of the website (`docs/demo.mp4`).
- [ ] Build the release: `scripts/package.sh` → `build/release/33rpm-1.2.2.dmg` and `33rpm-bridge-1.2.2.zip`.
- [x] Website: https://rohan2025.github.io/33rpm/ (GitHub Pages from `docs/`; download button gets the latest release).
- [x] Chrome Web Store: live at https://chromewebstore.google.com/detail/33rpm-bridge/biiiggaibbnengablmcboeaehlhmffnj
- [ ] Optional: Apple Developer Program ($99/yr) + notarization removes the "can't verify developer" warning.
      Without it, people open it via System Settings → Privacy & Security → Open Anyway (explained in the DMG's Read Me).
- [ ] Try the DMG on a second Mac or a fresh user account if you can.

## Links to post (tagged, so GoatCounter shows which post brought people)

Use these instead of the bare website link. The tag only says where the click came from, nothing about the person.

- X: `https://rohan2025.github.io/33rpm/?ref=x`
- LinkedIn: `https://rohan2025.github.io/33rpm/?ref=linkedin`
- Reddit: `https://rohan2025.github.io/33rpm/?ref=reddit`
- Hacker News: `https://rohan2025.github.io/33rpm/?ref=hn`
- Product Hunt: `https://rohan2025.github.io/33rpm/?ref=producthunt`

Numbers: website visits and button clicks at https://33rpm.goatcounter.com, app downloads with `scripts/stats.sh`,
extension installs in the Chrome Web Store dashboard.

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

Attach the video to the main post. The link goes in the first reply, because X shows posts with links to fewer people.
Every post below is under 280 characters.

**Main post** (with the video):

```
I turned my Mac desktop into a little listening room 🎶

33rpm puts a turntable on your wallpaper that plays along with YouTube Music. The record spins, the stereo shows the song, and every track ends up in a crate you can flip through.

Free and open source. Link below 👇
```

**Reply 1:**

```
Download (free, macOS 14+): https://rohan2025.github.io/33rpm/?ref=x

You'll also need the Chrome extension, which is linked on the page. Setup takes about 2 minutes.
```

**Reply 2:**

```
Details I'm weirdly proud of:
• the arm creeps inward as the song plays
• the record eases to a stop when you pause
• the stereo's dot-matrix display shows the title
• played sleeves drop into the crate, and you can click one to play it again
```

**Reply 3:**

```
How it works: a small Chrome extension reads what YouTube Music is playing and sends it to a native Swift app on your Mac over localhost.

No account, no analytics, ~0% CPU. It's all Core Animation.
```

**Reply 4:**

```
Three rooms so far: Evening, Rainy Window and Minimal. Each one is just a folder of images, so you can make your own.

Which room should I build next?
```

## LinkedIn

Attach the video. Put the link in the first comment, because LinkedIn shows posts with links to fewer people. The first
two lines are what people see before "...see more", so they carry the post.

**Post:**

```
I missed putting on a record, so I built a turntable into my Mac desktop. 🎶

I listen to YouTube Music all day while I work. It's convenient, but I missed the little ritual of a record player: the sleeve, the needle dropping, a stack of what you've played growing next to it.

So I made 33rpm, a free macOS app that puts a small listening room on your wallpaper and plays along with whatever's on YouTube Music:

→ The record spins at 33⅓ with the album art on the label
→ The arm creeps inward as the song plays
→ A vintage stereo shows the song on a dot-matrix display, and its knobs pause and skip
→ Every song you play drops into a wooden crate you can flip through and replay
→ Three rooms: Evening, Rainy Window and Minimal

Under the hood it's a native Swift app (Core Animation, so it sits at ~0% CPU) and a small Chrome extension that tells it what's playing. Everything stays on your Mac: no account, no analytics, no cloud.

It's open source, and the extension is on the Chrome Web Store, so setup takes about two minutes.

Download link in the first comment. I'd love to hear which room you'd want next. 👇

#buildinpublic #macos #swift #opensource
```

**First comment** (post it right after):

```
Download for Mac (free): https://rohan2025.github.io/33rpm/?ref=linkedin
Source code: https://github.com/rohan2025/33rpm
```

## Product Hunt

- **Name:** 33rpm
- **Tagline** (≤60): `A turntable on your Mac desktop that plays along with YouTube Music`
- **Description** (≤260):
  > 33rpm turns your Mac wallpaper into a cozy listening room. A record spins at 33⅓ with your current album on the label, the arm tracks the song, played sleeves stack in a crate you can flip through, and you can pause or skip right from the desktop.
- **Topics:** Mac, Music, Design Tools (or Productivity)
- **Thumbnail:** `ph-thumbnail-240.png`
- **Gallery (1270×760, these are 2× so they stay sharp):** `1-evening.jpg`, `2-crate-browse.jpg`, `3-rainy-window.jpg`, `4-minimal.jpg`, `5-idle.jpg`, plus the video.
- **Pricing:** Free
- **Links:** Website / download: https://rohan2025.github.io/33rpm/?ref=producthunt · Source: https://github.com/rohan2025/33rpm
- **Maker's first comment:**
  > Hi Product Hunt 👋 I listen to YouTube Music all day and missed the ritual of a record player, so I built one into my desktop.
  >
  > It's a native Swift app (Core Animation, so it sits at ~0% CPU) plus a small Chrome extension that tells it what's playing. Everything stays on your Mac: no account, no analytics, no cloud.
  >
  > Things to try: hover the crate to flip through what you've played and click a sleeve to replay it, click the turntable to pause, and switch to the Rainy Window room at night.
  >
  > The rooms are AI-generated and you can drop in your own art; each scene is just a folder of PNGs and a JSON file. Would love to hear which room you'd want next!

## Chrome Web Store listing (for 33rpm-bridge-1.2.2.zip)

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
  - `storage`: saves the pairing token the user enters.
  - `alarms`: wakes the background worker to reconnect to the local app if it restarts.
  - `scripting`: re-attaches to already-open YouTube Music tabs after install, and switches songs inside the YouTube Music page when the user picks one in 33rpm.
  - Host `https://music.youtube.com/*`: reads the now-playing info and queue on YouTube Music, and nowhere else.
  - Connects only to `ws://127.0.0.1` (the user's own computer).
- **Privacy / data usage:** Collects no user data. Nothing is sold, transferred or used for anything other than the single purpose above.
- **Privacy policy URL:** https://github.com/rohan2025/33rpm/blob/main/PRIVACY.md
- **Homepage URL:** https://rohan2025.github.io/33rpm/ · **Support URL:** https://github.com/rohan2025/33rpm/issues
- **Images:** icon `extension/icon128.png`, screenshots `cws-screenshot-1..3.png` (1280×800), small promo tile `cws-promo-440x280.png`.

## Notes

- The screenshots use fictional album covers and track names (made from the app's own room photos), so no real artists appear.
- If you open-source it, the room art and covers in `Scenes/` and `Assets/` were generated for this project with ChatGPT.
