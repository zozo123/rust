#!/usr/bin/env bash
# Build stage1 rustc for pinned EverInit A/B.
# variant=base|candidate
#
# Candidate applies a PINNED patch file from .github/pinned/ (SHA-256 verified).
# Never fetch a live pull/N.patch URL — that is mutable and breaks archival A/B.
set -euo pipefail

VARIANT="${1:?variant base|candidate}"
BASE_SHA="${BASE_SHA:-09ee43b2d6055539771bee8ac30a6e56eb4db773}"
CANDIDATE_HEAD="${CANDIDATE_HEAD:-e7339de13da94243e4e0f0ee173be9be44164ab2}"
PATCH_REL="${PATCH_REL:-.github/pinned/160033-e7339de13da.patch}"
PATCH_SHA256_EXPECT="${PATCH_SHA256_EXPECT:-92eb41d1b3b928c827874d463c9f55aed9e38604bf0c69d7e75f1f3509d3f0dc}"
OUT_TGZ="${OUT_TGZ:-stage1-${VARIANT}.tar.gz}"
WORKFLOW_SHA="${GITHUB_SHA:-unknown}"

echo "==> variant=$VARIANT base_sha=$BASE_SHA candidate_head=$CANDIDATE_HEAD workflow_sha=$WORKFLOW_SHA"
df -h || true

sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL || true

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential cmake ninja-build pkg-config libssl-dev python3 git curl ca-certificates

if ! command -v rustc >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
fi
# shellcheck disable=SC1091
source "$HOME/.cargo/env" 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"

# Resolve pinned patch path (workflow checks out fork first)
REPO_ROOT="$(pwd)"
if [[ ! -f "$PATCH_REL" ]]; then
  # When script is run from checkout root
  if [[ -f "$GITHUB_WORKSPACE/$PATCH_REL" ]]; then
    PATCH_REL="$GITHUB_WORKSPACE/$PATCH_REL"
  fi
fi
PATCH_ABS="$(cd "$(dirname "$PATCH_REL")" && pwd)/$(basename "$PATCH_REL")"
if [[ ! -f "$PATCH_ABS" ]]; then
  echo "missing pinned patch: $PATCH_REL" >&2
  exit 2
fi
GOT_SHA="$(sha256sum "$PATCH_ABS" | awk '{print $1}')"
if [[ "$GOT_SHA" != "$PATCH_SHA256_EXPECT" ]]; then
  echo "PATCH SHA-256 mismatch:" >&2
  echo "  expect $PATCH_SHA256_EXPECT" >&2
  echo "  got    $GOT_SHA" >&2
  exit 3
fi
echo "pinned patch ok sha256=$GOT_SHA"

rm -rf rust
git init rust
cd rust
git remote add origin https://github.com/rust-lang/rust.git
git fetch --depth 2 origin "${BASE_SHA}"
git checkout --force FETCH_HEAD
git rev-parse HEAD
git rev-parse HEAD^1
ACTUAL_BASE="$(git rev-parse HEAD)"

if [[ "$VARIANT" == "candidate" ]]; then
  echo "==> applying pinned patch (dirty tree; HEAD stays at base for CI LLVM)"
  if ! git apply --3way "$PATCH_ABS"; then
    git apply "$PATCH_ABS"
  fi
  git status --short | head -40
  echo "HEAD still $(git rev-parse HEAD) (base; intentional for download-ci-llvm)"
elif [[ "$VARIANT" != "base" ]]; then
  echo "unknown variant: $VARIANT" >&2
  exit 2
fi

# CI LLVM probe
code="$(curl -s -o /dev/null -w '%{http_code}' \
  "https://ci-artifacts.rust-lang.org/rustc-builds/${ACTUAL_BASE}/rust-dev-nightly-x86_64-unknown-linux-gnu.tar.xz" || true)"
echo "CI LLVM probe for ${ACTUAL_BASE}: HTTP ${code}"

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
./build/host/stage1/bin/rustc -vV | tee "../rustc-vv-${VARIANT}.txt"

cd ..
tar -C rust/build/host -czf "$OUT_TGZ" stage1
ls -lh "$OUT_TGZ"

# Identity sidecar for measure jobs
cat > "identity-${VARIANT}.json" <<JSON
{
  "variant": "${VARIANT}",
  "base_sha": "${ACTUAL_BASE}",
  "candidate_head": "${CANDIDATE_HEAD}",
  "patch_sha256": "${GOT_SHA}",
  "patch_file": "$(basename "$PATCH_ABS")",
  "workflow_sha": "${WORKFLOW_SHA}",
  "rustc_vv": $(python3 -c 'import json; print(json.dumps(open("rustc-vv-'"${VARIANT}"'.txt").read()))')
}
JSON
cat "identity-${VARIANT}.json"
echo "built $OUT_TGZ"
