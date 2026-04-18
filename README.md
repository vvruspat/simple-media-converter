# Simple Media Converter

> Convert WAV to MP3. Drop, click, done.

A minimal native macOS app for converting WAV files to MP3 — fast, clean, and without any setup. Built for musicians, producers, and audio engineers who want proper dithering and full control over output quality.

![Simple Media Converter](https://whitesquirrel.digital/smc/marketing.png)

## Download

**[⬇ Download v2.0 for macOS](https://github.com/vvruspat/simple-media-converter/releases/download/v2.0/SimpleMediaConverter-2.0.dmg)**

Open the DMG → drag to Applications → done. No Gatekeeper warnings.

Requirements: macOS 14+ · Apple Silicon

## Features

- **Drag & drop** — drop WAV files directly into the window (16 / 24 / 32-bit)
- **Parallel conversion** — all files convert simultaneously using available CPU cores
- **Per-file progress bars** with real-time feedback
- **Presets** — named settings saved between sessions, switch in one click
- **Bitrate** — 128 / 256 / 320 kbps CBR via libmp3lame
- **Dithering** — Shibata ★, Lipshitz, Triangular HP, Rectangular, and more
- **Output folder** — save next to source or pick any destination
- **Filename templates** — `{name}`, `{bitrate}`, `{dither}`, `{date}` placeholders
- **Finder reveal** — converted files open in Finder automatically
- **Self-contained** — ffmpeg is bundled, nothing to install

## Screenshots

| Queue | Preset settings | Done |
|-------|----------------|------|
| ![Queue](https://whitesquirrel.digital/smc/screenshot-queue.png) | ![Presets](https://whitesquirrel.digital/smc/screenshot-preset.png) | ![Done](https://whitesquirrel.digital/smc/screenshot-done.png) |

## How it works

The app shells out to a bundled `ffmpeg` binary with the following pipeline:

```
aresample=dither_method=shibata,aformat=sample_fmts=s16p
```

The explicit `s16p` format forces bit-depth reduction from the source WAV (24/32-bit) to 16-bit before LAME encodes to MP3, which is what actually triggers psychoacoustic dithering. Without it, ffmpeg passes 32-bit float to LAME and dithering has no effect.

## Building

```bash
# Dev build + run
./build.sh

# Notarized release DMG (requires Developer ID cert + notarytool profile)
./release.sh
```

### Prerequisites

- Xcode Command Line Tools
- Swift 5.9+
- Homebrew (for ffmpeg — bundled automatically during build)

### First-time notarization setup

```bash
./setup_notarize.sh
```

## Tech stack

- **SwiftUI** + `@Observable` (macOS 14+)
- **ffmpeg** bundled via `dylibbundler`
- `withTaskGroup` for parallel conversion
- `withCheckedContinuation` for non-blocking process wait
- CoreGraphics for icon generation

## License

MIT
