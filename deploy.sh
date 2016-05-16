#!/bin/bash
set -ue

readonly REV=$(git rev-parse --short HEAD)
readonly IMAGE="gcr.io/goonswarm-1303/goon-auth:${REV}"

echo "Deploying goon_auth revision ${REV}..."

kubectl rolling-update goon-auth --image "${IMAGE}"
