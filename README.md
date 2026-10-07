# BandCut

**BandCut** is a native macOS desktop application built specifically for silent-stage band rehearsals, direct-input multi-track recordings, and long jam sessions.

When rehearsing with in-ear monitors, direct modelers, and electronic drums, full-session recordings are usually captured as a single continuous 2–3 hour `.wav` file. Standard silence-detection algorithms fail in these environments because inter-song chatter, tuning, and false starts carry enough signal to prevent static silence gates from triggering.

BandCut uses a **dual-stage RMS amplitude algorithm** to automatically filter out chatter, isolate full-band song takes, draw an interactive visual waveform, and batch-export labeled tracks directly to high-quality MP3s via FFmpeg.

## Screenshots

### Session review and track selection

![BandCut session review](assets/ss/Screenshot%202026-10-06%20at%2017.35.55.png)

### Precision waveform editing at 128× zoom

![BandCut precision waveform](assets/ss/Screenshot%202026-10-06%20at%2017.34.24.png)

---

## 🌟 Features

* **Multi-Hour WAV Processing:** Fast, memory-efficient decoding of multi-gigabyte `.wav` files off the main UI thread using Dart Background Isolates.
* **Smart Chatter & Talk Filtering:** Dual-stage RMS thresholding distinguishes full-band playing (>-22 dB) from inter-song speech, tuning, and room noise.
* **Interactive Waveform Visualizer:** High-resolution sample-peak rendering with a live playhead, timeline ruler, horizontal navigation, and up to 128× zoom.
* **Audio Preview & Scrubbing:** Click or click-drag with 100 ms precision to audit cut boundaries before export via `just_audio`.
* **Track Editing:** Rename, add, delete, include/exclude, and fine-tune start/end boundaries directly in the session UI.
* **False Start Rejection:** Automatically discards brief audio bursts, instrument checks, and false starts under 40 seconds.
* **Batch MP3 Export:** Non-destructive slicing and high-quality VBR encoding (`libmp3lame`) powered by the bundled universal FFmpeg engine.

---

## 🛠️ Tech Stack

* **UI Framework:** Flutter Desktop (macOS target)
* **Language:** Dart 3.x
* **Audio Decoding:** Native `wav` parser + Dart `compute` Isolates
* **Playback Engine:** `just_audio` (CoreAudio integration)
* **Export Pipeline:** `FFmpeg` CLI process runner (`libmp3lame`)

---

## 📋 Prerequisites

Ensure your macOS environment has the following installed:

1. **Flutter SDK** (Version 3.19.0 or higher)
   ```bash
   flutter doctor
   ```
2. **Xcode Command Line Tools**
   ```bash
   xcode-select --install
   ```

FFmpeg is bundled with BandCut; users do not need to install it separately.

---

## 🚀 Getting Started

```bash
git clone https://github.com/ilkerokutman/BandCut.git
cd BandCut
flutter pub get
flutter run -d macos
```

---

## 🏗️ Building the macOS App

```bash
flutter build macos --release
```

Your compiled application bundle will be located at:
`build/macos/Build/Products/Release/BandCut.app`

> BandCut is sandboxed for Mac App Store distribution. WAV input and MP3 output access is granted only through user-selected file and directory pickers.

---

## 📖 Pipeline Overview

```
┌──────────────────┐     ┌───────────────────────┐     ┌────────────────────────┐     ┌───────────────────────┐
│  Continuous WAV  │ ──> │ Background Isolate    │ ──> │ Interactive Waveform   │ ──> │ FFmpeg Batch          │
│  Session File    │     │ Speech/Chatter Filter │     │ Review, Edit & Label   │     │ MP3 Export Engine     │
└──────────────────┘     └───────────────────────┘     └────────────────────────┘     └───────────────────────┘
```

1. **Import:** Select a continuous WAV recording.
2. **Analyze:** A background worker generates downsampled peak geometry and identifies full-band takes.
3. **Review & Label:** Audit regions, rename track titles, and preview boundaries using the visual waveform.
4. **Export:** Export individual MP3 files straight to your chosen directory.

---

## 📄 License

BandCut is distributed under the MIT License. See `LICENSE` for details.

The bundled FFmpeg executable is licensed under LGPL v2.1 or later and LAME
is licensed under LGPL v2.0 or later. Corresponding license and source
provenance files are included with the bundled executable under
`macos/Runner/Resources/ffmpeg/licenses`.
