# Performance

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

## Release rule

Remeasure the packaged release after adding any background feature, updater, sync, parser dependency, or persistent observer. Hidden idle CPU must still settle near 0%, and a memory increase needs a concrete explanation.
