#!/bin/bash

set -e

TARGET=aarch64-unknown-linux-gnu

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
REPO=wuodan
IMAGE=$(basename $DIR)
TAG=latest
FULL_TAG=${REPO}/${IMAGE}:${TAG}
DATETIME=$(date '+%Y%m%d%H%M%S')

CONTAINER=${IMAGE}_qemu-chroot_${DATETIME}

echo "Running docker container named '${CONTAINER}' ..."
docker run -it --name "${CONTAINER}" --privileged wuodan/gentoo-crossdev-aarch64:latest qemu-chroot.sh

echo "Container stopped"
echo "The result is container '${CONTAINER}'"
echo "Use docker commit to create a new image ..."

echo DONE
