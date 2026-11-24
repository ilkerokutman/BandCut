# BandCut — App Review Response (Guideline 2.1(a))

Use the text below as a reply in App Store Connect. The download URL is already filled in.

---

## Sample file for review

**Download link:** https://github.com/ilkerokutman/BandCut/releases/download/review-sample/bandcut_review_sample.wav

We have prepared a real band rehearsal WAV file for review:

- **File:** `assets/sample/sample.wav`
- **Format:** RIFF/WAVE, 44.1 kHz, 16-bit, stereo PCM
- **Duration:** 16 minutes 15 seconds
- **Size:** 164 MB

This is a continuous segment cut from an actual rehearsal recording. When imported into BandCut, the app analyzes it and detects **3 distinct song takes**:

| Track     | Start    | End      | Duration | Notes                                |
|-----------|----------|----------|----------|--------------------------------------|
| **Take 1** | 0:01:17  | 0:06:26  | 5:09     | Full-band passage                    |
| **Take 2** | 0:06:43  | 0:10:38  | 3:55     | After a short gap / chatter          |
| **Take 3** | 0:11:34  | 0:15:05  | 3:30     | After a short gap / chatter          |

The regions between takes contain the typical inter-song chatter, tuning, and room noise that BandCut is designed to filter out.

## How to test the app with the sample

1. Launch **BandCut**.
2. Click **Import WAV** and select the downloaded sample file.
3. The app analyzes the file in a background isolate and draws the waveform.
4. After analysis, three tracks (**Take 1**, **Take 2**, **Take 3**) appear in the list.
5. Select one or more tracks, optionally rename them, and click **Export MP3s**.
6. Choose an output folder; the app exports each selected track as a separate MP3 using the bundled FFmpeg/LAME encoder.

No account, login, or internet connection is required.

## Hosting the sample on GitHub Releases

**Done.** The WAV file is already hosted as a GitHub Release asset under the `review-sample` tag.

**Repository:** `ilkerokutman/BandCut`  
**Release page:** https://github.com/ilkerokutman/BandCut/releases/tag/review-sample  
**Direct download URL:** https://github.com/ilkerokutman/BandCut/releases/download/review-sample/bandcut_review_sample.wav

This keeps the 164 MB file out of the git history while providing a permanent direct-download URL that Apple can reuse on future reviews.

**Important:** do not commit the WAV file into the repository itself. Release assets are the right place for large binary files.

## Other hosting options

If you prefer not to use GitHub, you can also use:

- **Personal CDN / S3 / R2**: a direct HTTP(S) link to the file.
- **Google Drive / Dropbox / OneDrive**: only use these if you can generate a stable direct-download link that does not require sign-in. Test the link in an incognito window first.

Avoid temporary transfer services such as WeTransfer or file.io. Apple requires the file to remain available for future reviews.

## Previous answers still apply

- **App purpose and target audience:** BandCut is a lightweight macOS audio utility for musicians and bands who want to split long continuous rehearsal WAV recordings into individual MP3 tracks without opening a full DAW.
- **Setup instructions:** Launch the app, import a WAV file, review detected tracks, and export MP3s.
- **External services:** None. Audio analysis and MP3 encoding run locally on the Mac using the bundled FFmpeg and LAME binaries inside the App Sandbox.
- **Regional differences:** None. The app functions identically in all regions.
- **Regulated industry / protected material:** The app does not operate in a regulated industry or include protected third-party material.

---

## Suggested App Review Information notes

Paste the following into the **Notes** field of the App Review Information section:

```
Sample WAV file for review: https://github.com/ilkerokutman/BandCut/releases/download/review-sample/bandcut_review_sample.wav

The sample is a real 16m15s band rehearsal recording (44.1kHz/16-bit/stereo WAV, 164 MB). When imported into BandCut, it automatically detects 3 song takes separated by inter-song chatter and tuning.

To test: launch BandCut, click Import WAV, select the downloaded file, wait for the waveform/analysis to finish, then select the detected tracks and click Export MP3s. No login or network access is required.
```

---

## Alternative synthetic sample

If the review team needs a smaller or deterministically reproducible file, we also have a synthetic 4m30s sample (`tools/generate_review_sample.py`) that contains three clean "song" segments, a short false start, and quiet chatter gaps. It detects exactly 3 tracks and is only 45 MB. Let us know if you would prefer that one instead.
