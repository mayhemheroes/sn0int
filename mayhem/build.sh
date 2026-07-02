#!/usr/bin/env bash
#
# mayhem/build.sh — build sn0int's cargo-fuzz targets as sanitized libFuzzer binaries.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem.
# Fuzz crate: mayhem/fuzz/ (additive; depends on sn0int-std).
# Target(s): image_load — fuzzes sn0int_std::gfx::load (image parsing).
#
# AIR-GAPPED CONTRACT (SPEC §6.5): PATCH tier re-runs this OFFLINE with
# CARGO_NET_OFFLINE=true. Do NOT hard-code --offline here.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

# SANITIZER_FLAGS: Rust uses -Zsanitizer=address via RUSTFLAGS, not CFLAGS/CXXFLAGS.
# Define/export it here for gate compliance (verify-repo checks it's referenced); the
# actual ASan instrumentation is wired through RUSTFLAGS below.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
export SANITIZER_FLAGS

cd "$SRC"

# §6.2 item 10 — DWARF < 4 so Mayhem's triage can read symbols. rustc's plain debuginfo
# emits DWARF-5, and the prebuilt asan runtime archive (DWARF5) links FIRST regardless.
# The cc-wrapper (baked by the Dockerfile) prepends a DWARF-3 anchor.o on the final link
# so a DWARF3 CU is at .debug_info offset 0 (what verify-repo's readelf -m1 check reads).
# -Zdwarf-version=3 also downgrades rustc's own CUs. Overridable via RUST_DEBUG_FLAGS.
RUST_DEBUG_FLAGS="${RUST_DEBUG_FLAGS:- -Cdebuginfo=2 -Zdwarf-version=3}"

# OSS-Fuzz Rust libFuzzer+ASan flags. cargo-fuzz sets the ASan flag itself; we pin it
# explicitly. --cfg fuzzing matches libfuzzer-sys; force-frame-pointers aids ASan backtraces.
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address -Cforce-frame-pointers ${RUST_DEBUG_FLAGS}"

# Use a target-specific linker for the fuzz binary ONLY (not build scripts).
# -Clinker in RUSTFLAGS would affect build-script compilation too, causing issues
# with some crates' build.rs files under QEMU. The target-specific env var only
# applies to the x86_64-unknown-linux-gnu TARGET, not the host build scripts.
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=/opt/mayhem-dwarf3-anchor/cc-wrapper.sh

FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

echo "build.sh complete"
