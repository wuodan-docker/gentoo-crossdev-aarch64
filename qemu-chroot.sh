#!/bin/bash

set -e

TARGET=aarch64-unknown-linux-gnu
TARGET_PATH=/usr/${TARGET}

[ -d /proc/sys/fs/binfmt_misc ] || modprobe binfmt_misc
[ -f /proc/sys/fs/binfmt_misc/register ] || mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc

# fails with 'File exists'
# echo ':aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/usr/bin/qemu-aarch64:' > /proc/sys/fs/binfmt_misc/register

mount --types proc none ${TARGET_PATH}/proc
mount -o bind /sys ${TARGET_PATH}/sys
mount -o bind /dev ${TARGET_PATH}/dev
mount -o bind /dev/pts ${TARGET_PATH}/dev/pts

touch /run/openrc/softlevel
/etc/init.d/qemu-binfmt start

if [ "${1}" == "setup" ]; then

	echo "Adding services to default runlevel ..."
	cat << EOF | chroot ${TARGET_PATH} 
rc-update add btattach default
rc-update add dhcpcd default
rc-update add sshd default
EOF

	echo "You should reset passwords with 'passwd && passwd pi' in chroot ..."
fi

echo "Entering chroot ..."
chroot ${TARGET_PATH} /bin/bash --login
echo "Left chroot ..."

umount	${TARGET_PATH}/sys \
		${TARGET_PATH}/proc \
		${TARGET_PATH}/dev/pts \
		${TARGET_PATH}/dev

if [ "${1}" == "setup" ]; then
	bash
fi
