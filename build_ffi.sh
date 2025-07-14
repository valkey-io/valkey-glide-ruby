#!/bin/bash

set -e  # Exit immediately if any command fails

# Path to Rust repo
RUST_REPO_DIR="../valkey-glide"
RUBY_GEM_LIB_DIR="../../valkey-glide-ruby/lib/valkey"

echo "🔄 Updating Valkey Glide FFI..."

# Clone or update Rust repo
if [ ! -d "$RUST_REPO_DIR" ]; then
  echo "📦 Cloning valkey-glide..."
  git clone https://github.com/valkey-io/valkey-glide.git "$RUST_REPO_DIR"
else
  echo "📥 Pulling latest valkey-glide updates..."
  cd "$RUST_REPO_DIR" && git pull origin main && cd -
fi

# Build Rust ffi
echo "🔧 Building Rust FFI..."
cd "$RUST_REPO_DIR/ffi"
cargo build --release

# Copy built .so or .dylib to Ruby gem lib folder
cp target/release/libglide_ffi.* "$RUBY_GEM_LIB_DIR"

echo "✅ Done! Copied shared library to:"
ls -lh "$RUBY_GEM_LIB_DIR"/libglide_ffi.*
