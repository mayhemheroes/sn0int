# Build Stage
FROM ghcr.io/evanrichter/cargo-fuzz:latest as builder

## Dependencies
RUN apt update && apt install -y build-essential pkg-config libsqlite3-dev libseccomp-dev libsodium-dev

## Add source code to the build stage.
ADD . /src
WORKDIR /src

RUN echo building instrumented harnesses && \
    bash -c "pushd sn0int-std/fuzz && cargo +nightly -Z sparse-registry fuzz build && popd" && \
    mv sn0int-std/fuzz/target/x86_64-unknown-linux-gnu/release/image_load /image_load && \
    echo done

RUN echo building non-instrumented harnesses && \
    export RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" && \
    bash -c "pushd sn0int-std/fuzz && cargo +nightly -Z sparse-registry build --release && popd" && \
    mv sn0int-std/fuzz/target/release/image_load /image_load_no_inst && \
    echo done

# Package Stage
FROM rustlang/rust:nightly

COPY --from=builder /image_load /image_load_no_inst /
COPY --from=builder /usr/lib/x86_64-linux-gnu/libsodium.so.23 /usr/lib/x86_64-linux-gnu/
