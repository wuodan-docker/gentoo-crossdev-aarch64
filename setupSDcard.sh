#!/bin/bash

set -e

TARGET=aarch64-unknown-linux-gnu

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
REPO=wuodan
IMAGE=$(basename $DIR)
TAG=latest
FULL_TAG=${REPO}/${IMAGE}:${TAG}
DATETIME=$(date '+%Y%m%d%H%M%S')

# bunch of tests
if		[ -z "${1}" ]; then
	(
		echo "Please supply mountpoint of SDcard like:"
		echo "./setupSDcard.sh /mnt/gentoo"
	) 1>&2
	exit 1
elif	[ ! -d "${1}" ] \
		|| [ ! -w "${1}" ]; then
	(
		echo "Supplied mountpoint ${1} is not a writable directory"
		echo "Are you using sudo?"
	) 1>&2
	exit 1
elif	[ "$(ls -A "${1}")" != "boot" ] \
		|| [ -n "$(ls -A "${1}"/boot)" ]; then
	echo "Mountpoint must contain an empty boot directory and nothing else!" 1>&2
	exit 1
fi

echo "Run image with target-path as volume on container"
echo "Copying /usr/${TARGET}/* to target-path ..."
echo "Write log to : ${DIR}/log/setupSDcard.${DATETIME}.log"
echo "Go do something else ;)"
docker run -it --name ${IMAGE}_setupSDcard \
	-v "${1}":/mnt/gentoo \
	${FULL_TAG} \
		rsync --archive --progress --quiet \
			--exclude=/usr/${TARGET}/mnt \
			--exclude=/usr/${TARGET}/proc \
			--exclude=/usr/${TARGET}/dev \
			--exclude=/usr/${TARGET}/sys \
			--exclude=/usr/${TARGET}/run \
			--exclude=/usr/${TARGET}/tmp \
			--exclude=/usr/${TARGET}/var/tmp \
			--exclude=/usr/${TARGET}/var/run \
			--exclude=/usr/${TARGET}/var/lock \
			/usr/${TARGET}/ \
			/mnt/gentoo 2>&1 \
	| tee ${DIR}/log/setupSDcard.${DATETIME}.log

echo "Sync ..."
echo "Go do something else ;)"
sync

echo "Cleanup intermediate container"
docker container rm ${IMAGE}_setupSDcard

echo DONE
