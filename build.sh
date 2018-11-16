#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
REPO=wuodan
IMAGE=$(basename $DIR)
TAG=latest
FULL_TAG=${REPO}/${IMAGE}:${TAG}
DATETIME=$(date '+%Y%m%d%H%M%S')

# echo "Refreshing base images"
# for base in $(sed -En 's#^[[:space:]]*FROM[[:space:]]+([^ \t]+)#\1#p' ${DIR}/Dockerfile | sed -E 's#\t# #g' | cut -d ' ' -f 1); do
	# docker pull ${base}
# done

mkdir -p ${DIR}/log
echo "Build intermediate image, write log to : ${DIR}/log/docker-build.${DATETIME}.log"
docker build --tag ${REPO}/${IMAGE}:docker.build $DIR 2>&1 | tee ${DIR}/log/docker-build.${DATETIME}.log

echo "Run intermediate image in priviledged mode for setup in qemu-chroot"
echo "Write log to : ${DIR}/log/qemu-chroot.${DATETIME}.log"
docker run -it --privileged --name ${IMAGE}_qemu-chroot ${REPO}/${IMAGE}:docker.build qemu-chroot.sh setup 2>&1 \
	| tee ${DIR}/log/qemu-chroot.${DATETIME}.log

echo "Create image from container of last step"
docker commit ${IMAGE}_qemu-chroot ${FULL_TAG}

echo "Cleanup intermediate container"
docker container rm ${IMAGE}_qemu-chroot

echo "Untag intermediate image"
docker rmi ${REPO}/${IMAGE}:docker.build

echo "Push image ..."
docker push ${FULL_TAG}

echo "Done"
