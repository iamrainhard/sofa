#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/site/images
cp website/index.html website/style.css website/appcast.xml build/site/
cp docs/images/{icon,home-transparent,remote-transparent,onboarding-transparent,sofa-social-v2}.png build/site/images/
touch build/site/.nojekyll
