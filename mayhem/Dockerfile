# Build Stage
FROM ubuntu:22.04 AS builder

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl build-essential pkg-config libsqlite3-dev libseccomp-dev libsodium-dev

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly
ENV PATH="/root/.cargo/bin:${PATH}"
RUN cargo install cargo-fuzz

ADD . /src
WORKDIR /src/sn0int-std/fuzz

RUN cargo fuzz build image_load && \
    mv target/x86_64-unknown-linux-gnu/release/image_load /image_load

RUN RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" \
    cargo build --release && \
    mv target/release/image_load /image_load_no_inst

# Package Stage
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y libsodium23 libsqlite3-0 libseccomp2
COPY --from=builder /image_load /image_load_no_inst /
