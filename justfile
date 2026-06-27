# Project commands. Run `just --list` to see them all.

# Interactive release: pick patch/minor/major, roll the CHANGELOG, tag & push.
release:
    elixir scripts/release.exs

# Run the test suite (builds the NIF locally).
test:
    DEBKIT_BUILD=1 mix test

# Format Elixir + Rust.
fmt:
    mix format
    cd native/debkit && cargo fmt

# Lint Rust.
clippy:
    cd native/debkit && cargo clippy --all-targets -- -D warnings
