# Performance

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
