# Performance

## September 22, 2026: local performance improvements

Compared the unchanged sources at `d0c9705cc815fc0fd4b76f30cac7e069589376fb`
with the uncommitted local candidate on the same Mac, running macOS 27.0
build 26A428. Both benchmark executables compile the real sources with Swift
release optimization (`-O`). Fixtures use temporary documents, private defaults,
and a private pasteboard. The installed app and the user's document were not
changed.

The candidate caches counts and serialized Markdown, limits spacing updates to
nearby paragraphs, parses Markdown once, generates clipboard formats once,
normalizes owned paste buffers in place, and discards unused endpoint response
chunks. It adds no package dependency, polling timer, or background process.

### Editing, loading, copying, and saving

Times below are medians in milliseconds after one warm-up, with 11 measured
iterations per operation, or seven for rendering, paste normalization, and
whole-pad copying. The 25,250-word document contains 2,500 paragraphs, including
headings, bold text, and links. These measure synchronous code paths; they are
not cold-launch or key-to-screen latency measurements.

| Operation, 25,250 words | Before | After |
| --- | ---: | ---: |
| Insert a character, counts visible | 50.898 | 4.974 |
| Insert a character, counts hidden | 7.817 | 0.185 |
| Move the caret, counts visible | 21.212 | 0.026 |
| Restyle spacing after one edit | 8.152 | 0.015 |
| Render Markdown | 818.005 | 303.046 |
| Serialize Markdown | 66.412 | 49.938 |
| Copy the whole pad, including clipboard verification | 148.544 | 48.657 |
| Save again without edits | 78.912 | 0.002 |
| Normalize mixed rich text | 69.340 | 71.773 |

With a 5,050-word document, typing with counts visible fell from 10.080 to
1.113 ms; rendering fell from 163.360 to 61.333 ms; whole-pad copying fell from
28.947 to 9.773 ms. An unchanged save still checks file metadata, so replacing,
deleting, or externally modifying the saved file triggers the usual save path.

The mixed rich-text normalization fixture was 3.5% slower in this run. Its
memory benefit is measured separately below; this is not a claim that every
individual operation became faster.

### Peak memory during large operations

Each memory fixture runs in a separate process. Memory is the physical footprint
reported by `vmmap`, rather than RSS or the app's disk size.

| Fixture | Before peak | After peak |
| --- | ---: | ---: |
| Rich paste: 12,500 paragraphs, 926,390 UTF-16 units | 30.9 MiB | 19.6 MiB |
| Endpoint: 100 MiB synthetic response | 206.4 MiB | 5.14 MiB |

The large rich-paste run took 151.4 ms before and 140.3 ms after, with 36.6% less
peak memory. Those timings are individual runs, not medians. Paragraph compaction
uses bounded 256-paragraph buffers and releases temporary attributed strings
between chunks.

The endpoint fixture served 64 KiB chunks from a temporary localhost server.
Both transfers completed successfully. The candidate keeps response memory
bounded by discarding chunks, but still waits for the full transfer and reports
late transport failures. This deliberately oversized response demonstrates
memory behavior; it does not represent a typical endpoint response.

### Hidden idle

The packaged local app ran the isolated short-draft fixture with
`--runtime-acceptance --measure-idle-only`. After `APARTE_IDLE_READY` and five
seconds of settling, five samples two seconds apart all showed 0.0% CPU. RSS was
114,512, 114,192, 114,144, 114,080, and 114,080 KiB. The physical footprint was
32.1 MiB, with a 32.9 MiB peak and no network sockets. The baseline fixture was
32.6 MiB, with a 33.2 MiB peak and 0.0% CPU in all five samples.

This harness initializes acceptance-test settings and a short draft. It does
not measure ordinary startup with Sparkle, a long editing session, or an exact
signed release. Remeasure the shipping artifact before release.

### Verification and reproduction

All 111 core tests passed. The packaged runtime harness passed 325 checks and
failed the existing `settings-resets-shortcut-to-option-space` check: macOS
reported that another app had reserved the shortcut. The same failure occurred
before these changes, so `make check` is not fully green on this machine.
Strict local app signature verification and diff checks passed separately.
The sandboxed Universal 2 candidate also passed packaging and structure
validation, including its signatures, architectures, entitlements, and updated
privacy manifest. Swift 6.4 reused one output path for both architecture builds;
the packaging script now copies each slice before building the next. This was
local validation, without installation, signing for distribution, or upload.

New regression coverage includes same-length replacements, selection counts,
undo, formatting cache invalidation, failed-save retry, external file changes,
paragraph splits and merges, batch boundaries, late endpoint failures, redirects,
and cancellation. A comparison of 413 Markdown fixtures against the baseline
matched rendered text, exported Markdown, and effective attributes. Typing and
selection counts were also exercised in an isolated native preview. Full manual
release acceptance remains separate.

Run the synthetic timing suite against the current sources:

```sh
./scripts/benchmark-performance.sh
./scripts/benchmark-performance.sh "$PWD" --memory-paste
```

To compare another source snapshot, supply its directory as the first argument.
The snapshot needs the `Sources` tree; the benchmark harness comes from the
current checkout. Endpoint memory measurement accepts only a synthetic loopback
URL, served separately:

```sh
./scripts/benchmark-performance.sh "$PWD" --memory-endpoint http://127.0.0.1:PORT/benchmark
```

## September 11, 2026: published version 1.3.0

Measured the exact published Universal 2 app, version 1.3.0, build 9, copied to
`/private/tmp/aparte-v130-live-measure.Box78m/Aparte.app`. Its executable launched
normally with `CFFIXED_USER_HOME` and `HOME` isolated, initializing `AppDelegate`
and Sparkle's real scheduler. The pre-existing Aparte process, PID 95101, was
left untouched. Only the measurement process, PID 49386, was terminated afterward.

After 15 seconds of settling, all five samples showed 0.0% CPU and 97,264 KiB
resident memory. `vmmap` reported a 28.9 MiB physical footprint and a 29.3 MiB
peak. There were no persistent child processes or network sockets at measurement
time. This ordinary-startup run provides the release idle measurement with the
updater initialized; it does not measure an active update download or installation.

The public DMG and feed were downloaded through the latest-release URLs and
byte-verified. Checks passed for the checksum, Developer ID and hardened runtime,
Universal 2, notarization, Gatekeeper, updater configuration, and archive and feed
signatures using the signing key in Keychain. Public DMG SHA-256:
`13938e844c33ba27e192a243ee97caf14ac23219ac4ba214527ed53c12ec4118`.

## V1 idle measurement

Measured August 30, 2026 on a Mac17,9 with Apple M5 Pro, macOS 26.5.2 build 25F84. The tested build was the ad-hoc signed release app at source commit `bc985e2` from the canonical project path.

The app was launched with its pad hidden and left idle. It has one Carbon hotkey registration and no repeating timer, polling loop, network task, or visible window at idle.

Five samples two seconds apart:

| Sample | CPU | RSS |
| --- | ---: | ---: |
| 1 | 0.0% | 93,280 KiB |
| 2 | 0.0% | 89,216 KiB |
| 3 | 0.0% | 89,216 KiB |
| 4 | 0.0% | 89,216 KiB |
| 5 | 0.0% | 89,120 KiB |

`vmmap -summary` reported a 22.8 MiB physical footprint and a 23.7 MiB peak physical footprint. macOS `ps` RSS includes shared mapped pages and settled at 89,120 KiB, or 87.0 MiB, so both figures are kept rather than presenting unlike memory counters as one number. `lsof -a -p "$PID" -i` returned no network socket.

The measured idle CPU requirement passes. All five samples were 0.0%.

## App Store candidate preflight

Measured September 3, 2026 against the ad-hoc signed, sandboxed universal candidate produced by `make check-app-store`. The first sample, taken about one second after launch, was 2.2% CPU and 98,256 KiB RSS. The next four samples, two seconds apart, were 0.0% CPU. RSS ranged from 98,256 to 99,376 KiB and ended at 98,992 KiB, or about 96.7 MiB. `lsof` reported zero network sockets.

This is preflight evidence, not the final Store measurement. Repeat it after signing the exact package intended for upload.

## Commands

```sh
open -n dist/Aparte.app
pgrep -x Aparte
for sample in 1 2 3 4 5; do
  ps -o %cpu=,rss= -p "$PID"
  sleep 2
done
vmmap -summary "$PID"
```

`$PID` above is the process ID returned by `pgrep`. Do not reuse a recorded process ID on another run.

The first launch with a fresh defaults domain shows the pad, so press Escape (or set `Aparte.hasLaunched`) before sampling idle CPU.

## Release rule

Remeasure the packaged release after adding any background feature, updater, sync, parser dependency, or persistent observer. Hidden idle CPU must still settle near 0%, and a memory increase needs a concrete explanation.

## September 7 writing tools, local candidate

Measured the uncommitted local candidate based on `601fd15`, built by
`make check`, on the same macOS 26.5.2 machine. The isolated runtime fixture
opened a short draft with the counter enabled, hid the pad, and waited without
polling. It did not open the user's document or change their login items.

Command: `dist/Aparte.app/Contents/MacOS/Aparte --runtime-acceptance --measure-idle-only`.
After `APARTE_IDLE_READY`, five `ps` samples two seconds apart were:

| Sample | CPU | RSS |
| --- | ---: | ---: |
| 1 | 0.0% | 93,040 KiB |
| 2 | 0.0% | 93,040 KiB |
| 3 | 0.0% | 93,024 KiB |
| 4 | 0.0% | 93,104 KiB |
| 5 | 0.0% | 93,120 KiB |

`vmmap -summary` reported a 21.0 MiB physical footprint and 21.1 MiB peak.
`lsof -a -p "$PID" -i` reported zero network sockets. These measurements are for
the short-draft fixture, not a maximum memory bound. The full runtime stress
fixture, which exercises a long document, zoom, and undo, retained a 118.2 MiB
physical footprint afterward and peaked at 327.4 MiB, with 0.0% hidden idle CPU.

The new features add no package dependency, repeating timer, network task, or
helper process. A signed release still needs measurement against its exact
shipping package.

## 1.1.0 published download

Measured the signed GitHub `v1.1.0` download, version 1.1.0 build 6, from
release commit `4792204`. DMG SHA-256:
`d3331fdd72a8e0f6711a5836a5490b03b7afb4cefa0b1578b5017962697efaf8`.

Command: `dist/released-1.1.0/Aparte.app/Contents/MacOS/Aparte --runtime-acceptance --measure-idle-only`.
After `APARTE_IDLE_READY`, five `ps` samples two seconds apart each reported
0.0% CPU and 91,552 KiB RSS. `vmmap -summary` reported a 19.9 MiB physical
footprint and 20.1 MiB peak. `lsof -a -p "$PID" -i` reported zero network sockets.
The short-draft fixture and limits described above still apply.

The downloaded app also passed all 122 runtime acceptance checks. The DMG
passed checksum verification, strict signature verification, stapled
notarization validation, and Gatekeeper assessment of both the image and app.
