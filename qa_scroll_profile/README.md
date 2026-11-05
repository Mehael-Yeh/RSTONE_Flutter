# QA-only Android scroll profile proxy — receipt schema 2

## Scope and status

This is a seven-file payload for an isolated `qa/profile-scroll-*` branch only.
The workflow replaces `.github/workflows/test.yml` on that QA branch; do not
merge it into App main. No remote upload, dispatch or Android execution is
implied by this package. Local self-tests use explicitly synthetic command
stubs and timings; they are not Flutter, emulator or phone performance results.

Approved App baseline: `8c77edb71cd32a287302d5d24d6faed07a3a855d`.
Reviewed App candidate: `f6f44977c94c71144a31792f42cb6a3c18b6ec81`.
These must remain distinct exact SHAs, not moving branches or tags.

The shared toolchain remains Flutter 3.32.8 / Dart 3.8.1, Java 17 and one
API 35 x86_64 emulator in one job. This does NOT reproduce OPPO PKX110,
ColorOS, Android 16, physical GPU, touch latency or real-device FPS.

## Why a separate runtime lock is necessary

The source lock's SDK minimum can exceed the approved SDK (the known original
lock states Dart >=3.11.0 and Flutter >=3.38.0). `flutter pub get` under the
approved older SDK may legitimately resolve a different dependency graph.
Schema 1 rejected that necessary temporary change and could not run this QA.
Schema 2 permits only a temporary `pubspec.lock` change in each isolated QA
checkout. It NEVER upgrades a production pubspec/lock or claims the original
production pins were compiled when the resolved bytes differ.

The historical compatible graph had 22 hosted-package changes and seven
SDK-package changes. These are context, NOT measured constants: this runner
captures whatever the actual pub resolution produces, and reports the full
original/resolved package records and SDK constraints. A different delta is
reported as observed, not rewritten to match a historical count.

## Transaction and evidence protocol

1. Require exact source checkout identities, initially clean tracked/untracked
   source, no signing key.properties, equal original source-lock bytes, and
   trusted identical synthetic harness bytes. Real font SHA256 is recorded.
2. Preserve each side's original lock bytes as `<side>.source.lock` with SHA256
   and size. Execute real `flutter pub get` in that isolated checkout.
3. Reject any tracked migration other than `pubspec.lock`; unsupported Android
   Gradle or SDK migrations are NOT silently accepted or restored over source.
4. Save actual `<side>.runtime.lock` bytes, SHA256 and size. Capture the real
   `flutter pub deps --json` package names, versions and sources. Read actual
   package_config.json root locations and package pubspec name/version, verify
   hosted/SDK/root origins, and retain a path-free normalized graph in
   `<side>.graph.json`, explicitly bound to the runtime-lock SHA256.
5. Check that every resolved locked package agrees with the graph and actual
   package configuration; only hosted and Flutter-SDK sources are supported.
   The restricted lock-mapping parser validates all fields, not selected lines;
   unknown layout/source/syntax fails closed. Complete raw locks are retained.
6. Candidate runtime lock must exactly equal baseline runtime lock before its
   profile starts. Do NOT copy one side's resolved lock onto the other side.
7. Execute Full-only `flutter drive --profile --no-pub` against the unchanged
   Dart harness. Check actual Flutter/Dart identity immediately before/after
   compilation, and recheck runtime lock, package graph and configuration after.
8. In a `finally` block, restore the exact original source-lock bytes even when
   pub get, profile, renderer capture or evidence validation fails. Require the
   restored before/after hashes equal, and all tracked source clean. Generated
   ignored build output and the injected untracked QA harness are allowed;
   non-lock tracked modifications are never globally ignored. Hard process
   termination (SIGKILL/host loss) cannot execute Python finally; discard such
   ephemeral checkouts and do not accept incomplete evidence.
9. Only completed sides receive receipt entries. A missing side, partial receipt,
   unknown renderer, missing real FrameTiming or any evidence mismatch fails.

Receipt schema 2 includes both exact App sources and the QA checkout SHA;
source lock before/after; original and runtime lock references; runtime hashes
before/after compilation; graph reference; full original-to-resolved delta and
`compiled_original_pins` boolean. The checker rejects schema 1, absent evidence,
wrong size/hash, cross-side/duplicate/traversal/symlink evidence paths, false
original-pin claims, mismatched runtime graphs/locks/SDKs, and source-lock drift.

The parent must independently bind the artifact run to the approved QA tooling
HEAD and these payload hashes, and supply independently approved App SHAs.
A receipt's self-declared QA SHA is not an external signature. Artifact files
are evidence from the trusted job, not cryptographic proof of execution against
a malicious producer. Never use the synthetic unit-test fixture as acceptance.

## Measurement semantics (unchanged)

The real page uses fixed synthetic product/formula fixtures, 244 and 500 items,
sorted and unsorted; two warmups, three repeats; the fixed drag/fling/ScrollEnd
protocol and real YaHei font. Raw Flutter FrameTiming timestamps/durations are
preserved. p50/p95/p99 use nearest rank. Over-budget means
`max(build_us,raster_us) > floor(1e6 / recorded_refresh_hz + 0.5)`;
not sum(build,raster), not an assumed 60Hz or an invented FPS conversion.
Renderer must have actual rendering-backend log evidence. Missing frame data
or unavailable renderer is unsupported, never a synthetic performance fallback.
Sequential baseline-then-candidate ordering, emulator/GPU/thermal noise remain.

## Local verification (stdlib only; no SDK/dependency install)

From the payload directory:

```sh
python3 -B -m unittest test_verify -v
```

The original five tests and all 23 original negative controls remain. Additional
runtime-lock, graph, parser and transaction tests include a real temporary Git
checkout plus SYNTHETIC pub-get/drive stubs. No Android device is touched.
The stubs deliberately resolve source/runtime locks differently and verify
restoration. Test file writes are scoped to temporary directories beside itself.

## Running the approved job and verifying returned artifacts

The branch-only workflow runs self-tests first, then uses the existing pinned
SDK/emulator setup. No second SDK, production secret, dataEnvironment, release,
publish command or APK artifact is added. Credentials are not persisted by
checkout. Artifact collection includes only `evidence/`; no APK/business assets.
Raw pub/drive diagnostic logs can contain ephemeral runner paths; review logs
before sharing publicly. Normalized dependency evidence contains no host paths.

The job's actual runner command (inside that existing single emulator job):

```sh
python3 qa-tooling/qa_scroll_profile/run_compare.py \
  --baseline 8c77edb71cd32a287302d5d24d6faed07a3a855d \
  --candidate f6f44977c94c71144a31792f42cb6a3c18b6ec81 \
  --workspace "$GITHUB_WORKSPACE"
```

After receiving a real artifact, from the trusted local payload directory:

```sh
python3 -B verify.py ARTIFACT_DIRECTORY \
  --baseline 8c77edb71cd32a287302d5d24d6faed07a3a855d \
  --candidate f6f44977c94c71144a31792f42cb6a3c18b6ec81 \
  --payload payload
```

Inspect `comparison.json` dependency deltas alongside raw source/runtime locks.
A successful comparison isolates App changes under equal actually resolved QA
dependencies, not performance under the original incompatible production pins.
No Android/cloud/OPPO conclusion exists until real execution and parent checks.
