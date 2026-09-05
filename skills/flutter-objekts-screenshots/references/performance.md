# Diagnose screenshot cost

Start with one requested scenario and separate setup, rendering, and output
costs. Keep heavy benchmarks outside ordinary tests.

| Observation | Next action |
| --- | --- |
| Ordinary tests load screenshot fonts or create PNGs | Inspect default test discovery and shared setup; keep new capture scenarios in top-level `screenshot_test/`. Retain ordinary assertions and any fonts those assertions need. |
| First run is slow, reruns are quicker | Record dependency resolution and cold compilation separately. Reuse the resolved environment; avoid `flutter clean` in the capture loop. |
| Images are much larger than needed | Use explicit `pixelRatio: 1` for review PNGs; device configurations otherwise default to native device density. Pixel count grows with the square of the ratio. Preserve golden settings and requested fidelity. |
| Many sequential images spend time encoding | Batch related states, awaiting each capture before the next UI mutation. A single image may not benefit from batch worker startup. |
| Capture hangs around animation | Assert readiness and pump the required frames. Control repeating animations or use a bounded wait with a clear failure, rather than increasing timeouts blindly. |
| Memory or CPU spikes | Start with two pending captures. Try one on constrained workers and measure. Multiple test files can each run their own workers; try a smaller runner `--concurrency` only for the screenshot command. |
| Too many variants repeat setup | Run the requested test file or name and one representative device first. Expand the matrix for actual review requirements. |
| Images differ between reruns | Check fonts, image fixtures, clocks, locale, theme, animation phase, SDK, and platform before blaming encoding. |
| Reruns fail with filename collisions | Use stable unique names with `overwrite: true` for review artifacts. Separate output roots for simultaneous runs. |

## Measure without hiding the work

1. Record the SDK, machine, device configurations, pixel ratio, capture count,
   pending-capture limit, and runner concurrency.
2. Measure ordinary-test and screenshot commands separately. Report cold startup
   separately from a repeated run. A package-wide test command is not a
   screenshot-only timing.
3. For an encoding comparison, reuse identical fixtures, states, dimensions,
   and resolution. Warm up both paths, alternate their execution order, and
   compare several samples by median only when performance investigation is
   requested. Time through the awaited batch completion, including PNG output.
4. Check decoded pixels when comparing sequential and batch correctness;
   different PNG encoders can produce different bytes for identical pixels.
   Separate this verification cost from capture timing.
5. Report observed times with their conditions. The package repository has an
   explicit benchmark under `example/benchmark/`; its performance threshold is
   not a universal promise for other apps or workers.

## Sources

- [Objekts package and public usage](https://github.com/putrautama007/flutter_objekts)
- [Flutter test configuration selection](https://api.flutter.dev/flutter/flutter_test/)
- [Flutter pumpAndSettle behavior](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pumpAndSettle.html)

Check the installed objekts exports and SDK when these sources differ from the
consuming app's version.
