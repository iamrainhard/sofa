#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/site/images
cp website/index.html website/style.css build/site/
cp docs/images/{icon,home,remote,onboarding}.png build/site/images/
touch build/site/.nojekyll
