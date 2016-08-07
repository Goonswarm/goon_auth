#!/bin/bash
set -ue

readonly REV=$(git rev-parse --short HEAD)
readonly IMAGE="gcr.io/goonswarm-1303/goon-auth:${REV}"

echo "Deploying goon_auth revision ${REV}..."

kubectl set image deployment/goon-auth "goon-auth=${IMAGE}"
