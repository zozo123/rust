#!/usr/bin/env bash
# Build stage1 rustc for EverInit A/B.
# variant=base|candidate
#
# Candidate applies rust-lang/rust#160033 as a dirty tree so HEAD stays at
# BASE_SHA (which has download-ci-llvm artifacts). Checking out the PR tip
# SHAs directly 404s CI LLVM.
set -euo pipefail

VARIANT="${1:?variant base|candidate}"
BASE_SHA="${BASE_SHA:-09ee43b2d6055539771bee8ac30a6e56eb4db773}"
PR_PATCH_URL="${PR_PATCH_URL:-https://github.com/rust-lang/rust/pull/160033.patch}"
OUT_TGZ="${OUT_TGZ:-stage1-${VARIANT}.tar.gz}"

echo "==> variant=$VARIANT base_sha=$BASE_SHA"
df -h || true

# Free disk on GHA runners
sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL || true

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential cmake ninja-build pkg-config libssl-dev python3 git curl ca-certificates

if ! command -v rustc >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
fi
# shellcheck disable=SC1091
source "$HOME/.cargo/env" 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"
rustc -V
cargo -V
python3 -V

rm -rf rust
# depth 2 so bootstrap can git rev-parse HEAD^1
git init rust
cd rust
git remote add origin https://github.com/rust-lang/rust.git
# Fetch the base commit with enough history for parent
git fetch --depth 2 origin "${BASE_SHA}"
git checkout --force FETCH_HEAD
git rev-parse HEAD
git rev-parse HEAD^1

if [[ "$VARIANT" == "candidate" ]]; then
  echo "==> applying #160033 patch (dirty tree; HEAD stays at base for CI LLVM)"
  curl -fsSL "$PR_PATCH_URL" -o /tmp/160033.patch
  if ! git apply --3way /tmp/160033.patch; then
    echo "3way apply failed; trying plain apply"
    git apply /tmp/160033.patch
  fi
  git status --short | head -50
  echo "HEAD still $(git rev-parse HEAD) (base; intentional for download-ci-llvm)"
elif [[ "$VARIANT" == "base" ]]; then
  echo "==> base: clean tree at $(git rev-parse HEAD)"
else
  echo "unknown variant: $VARIANT" >&2
  exit 2
fi

# Confirm CI LLVM artifact exists for HEAD
HEAD_SHA="$(git rev-parse HEAD)"
code="$(curl -s -o /dev/null -w '%{http_code}' \
  "https://ci-artifacts.rust-lang.org/rustc-builds/${HEAD_SHA}/rust-dev-nightly-x86_64-unknown-linux-gnu.tar.xz" || true)"
echo "CI LLVM probe for ${HEAD_SHA}: HTTP ${code}"
if [[ "$code" != "200" ]]; then
  echo "WARNING: CI LLVM may not be available for this SHA; build may fail or rebuild LLVM"
fi

cat > bootstrap.toml <<'TOML'
change-id = 99999999
profile = "compiler"

[llvm]
download-ci-llvm = true

[build]
docs = false
extended = false
tools = []

[rust]
channel = "dev"
download-rustc = false
debug = false
debuginfo-level = 0
debuginfo-level-rustc = 0
debuginfo-level-std = 0
incremental = false
dist-src = false
lld = false
llvm-tools = false

[dist]
src-tarball = false
TOML

python3 x.py build --stage 1 library -j"$(nproc)"
./build/host/stage1/bin/rustc -vV

cd ..
tar -C rust/build/host -czf "$OUT_TGZ" stage1
ls -lh "$OUT_TGZ"
echo "built $OUT_TGZ"
