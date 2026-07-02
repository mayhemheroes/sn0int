# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile — sn0int (Rust / cargo-fuzz).
# Builds the image_load fuzz target from mayhem/fuzz/ against sn0int-std.
#
# Build (from the repo root, on the `mayhem` branch):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       -t sn0int-commit:test .

FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (never an ENV — an empty ENV breaks clang). build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
# Undefaulted (no '=') so the base ENV default flows through unless --build-arg overrides it.
ARG SANITIZER_FLAGS

# ── System dependencies ──────────────────────────────────────────────────────
# sodiumoxide uses pkg-config to locate libsodium; hlua-badtouch links lua5.3.
USER root
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        pkg-config \
        libsodium-dev \
        liblua5.3-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Rust toolchain @ a FIXED, lockable, $HOME-independent prefix ─────────────
# nightly-2025-07-01 (rustc 1.90.0-nightly): needed for
#   - time@0.3.53 requires rustc >= 1.88.0
#   - zerocopy@0.8.x uses stdarch_x86_avx512 (stabilized in 1.90.0 cycle)
# No rust-version constraint in sn0int's Cargo.toml; edition 2021 is fine.
ARG RUST_CHANNEL=nightly-2025-07-01
ARG CARGO_FUZZ_VERSION=0.12.0

ENV RUSTUP_HOME=/opt/toolchains/rust/rustup \
    CARGO_HOME=/opt/toolchains/rust/cargo \
    PATH=/opt/toolchains/rust/cargo/bin:${PATH}

RUN install -d /opt/toolchains/rust \
 && curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh \
 && sh /tmp/rustup-init.sh -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_CHANNEL}" \
 && rustup component add rust-src --toolchain "${RUST_CHANNEL}" \
 && cargo install cargo-fuzz --version "${CARGO_FUZZ_VERSION}" --locked \
 && rm -f /tmp/rustup-init.sh \
 && chown -R 2000:2000 /opt/toolchains/rust

# ── DWARF<4 anchor (SPEC §6.2 item 10) ─────────────────────────────────────
# cargo fuzz build links librustc-nightly_rt.asan.a (DWARF5) first in .debug_info;
# -Zdwarf-version=3 only downgrades rustc's own CUs. Compile a tiny DWARF-3 anchor.o
# and prepend it via a cc-wrapper so a DWARF3 CU sits at .debug_info offset 0.
RUN install -d /opt/mayhem-dwarf3-anchor \
 && printf 'int mayhem_dwarf3_anchor = 0;\n' > /opt/mayhem-dwarf3-anchor/anchor.c \
 && clang -g -gdwarf-3 -c /opt/mayhem-dwarf3-anchor/anchor.c -o /opt/mayhem-dwarf3-anchor/anchor.o \
 && printf '#!/usr/bin/env bash\nexec clang /opt/mayhem-dwarf3-anchor/anchor.o "$@"\n' \
      > /opt/mayhem-dwarf3-anchor/cc-wrapper.sh \
 && chmod 0755 /opt/mayhem-dwarf3-anchor/cc-wrapper.sh \
 && chmod 0644 /opt/mayhem-dwarf3-anchor/anchor.o

# Source enters from the build CONTEXT (CI checkout): the FULL repo (incl. .git) → /mayhem.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Populates $CARGO_HOME (online, this first build) and builds the sanitized fuzz target(s).
RUN bash mayhem/build.sh

# No mayhem/test.sh — sn0int-std has no standalone functional test suite suitable for RL.
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — skipping"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
