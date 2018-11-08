FROM wuodan/gentoo-crossdev:latest

ARG KERNEL_BRANCH=rpi-4.14.y
ARG STAGE3_DATE=20180907

ARG TARGET=aarch64-unknown-linux-gnu
ARG ARCH=arm64
ARG STAGE3_FILE="stage3-${ARCH}-${STAGE3_DATE}.tar.bz2"

ARG TARGET_PATH=/usr/${TARGET}
ARG RPI_PATH=/raspberrypi

# create toolchain
RUN crossdev --stable -t "${TARGET}" --init-target && \
	echo "cross-${TARGET}/gcc cxx multilib fortran -mudflap nls openmp -sanitize -vtv" >> /etc/portage/package.use/crossdev && \
	crossdev --stable -t "${TARGET}" && \
# need sys-devel/bc this to build kernel somehow
	emerge -qu  sys-devel/bc && \
# install stage3 arm64
	mkdir -p ${TARGET_PATH} && \
	cd ${TARGET_PATH} && \
	curl -s -o "${STAGE3_FILE}" "http://distfiles.gentoo.org/experimental/${ARCH}/${STAGE3_FILE}" && \
	curl -s -o "${STAGE3_FILE}.DIGESTS" "http://distfiles.gentoo.org/experimental/${ARCH}/${STAGE3_FILE}.DIGESTS" && \
	sha512sum "${STAGE3_FILE}" | cut -f 1 -d " " | grep -q -f - "${STAGE3_FILE}.DIGESTS" && \
	rm -f "${STAGE3_FILE}.DIGESTS" && \
	tar xpf "${STAGE3_FILE}" --xattrs-include='*.*' --numeric-owner && \
	rm "${STAGE3_FILE}" && \
	rm -rf ${TARGET_PATH}/tmp/* && \
# copy host /usr/portage while omitting packages and distfiles
	rsync -aq /usr/portage ./usr --exclude distfiles/* --exclude packages/* && \
# setup local repo
	mkdir -p /usr/local/portage/{metadata,profiles} && \
	chown -R portage:portage /usr/local/portage && \
	echo 'localrepo' > /usr/local/portage/profiles/repo_name && \
	echo -e 'masters = gentoo\nauto-sync = false\nthin-manifests = true' > /usr/local/portage/metadata/layout.conf && \
	mkdir -p /etc/portage/repos.conf && \
	echo -e '[localrepo]\nlocation = /usr/local/portage' > /etc/portage/repos.conf/localrepo.conf && \
# get newer ebuild for firmware
	cd /tmp && \
	git clone https://github.com/Wuodan/gentoo-overlay.git && \
	mkdir -p /usr/local/portage/sys-boot && \
	cp -r /tmp/gentoo-overlay/sys-boot/raspberrypi-firmware /usr/local/portage/sys-boot && \
	rm -rf /tmp/gentoo-overlay && \
# copy local repo to target
	cp -ar /usr/local/portage ${TARGET_PATH}/usr/local && \
	mkdir -p ${TARGET_PATH}/etc/portage/repos.conf && \
	cp /etc/portage/repos.conf/localrepo.conf ${TARGET_PATH}/etc/portage/repos.conf/localrepo.conf && \
# unmask kernel and firmware (why?)
	mkdir -p ${TARGET_PATH}/etc/portage/package.unmask && \
	echo '<sys-boot/raspberrypi-firmware-9999' >> ${TARGET_PATH}/etc/portage/package.unmask/raspberrypi-firmware && \
	echo '<sys-boot/raspberrypi-firmware-9999 **' >> ${TARGET_PATH}/etc/portage/package.keywords/raspberrypi-firmware && \
	echo '<sys-kernel/raspberrypi-sources-9999 **' >> ${TARGET_PATH}/etc/portage/package.keywords/raspberrypi-sources && \
# get kernel and firmare source
	ARCH=amd64 ROOT=${TARGET_PATH} ${TARGET}-emerge -q	'<sys-boot/raspberrypi-firmware-9999' \
														'<sys-kernel/raspberrypi-sources-9999' && \
# set up baseline bcmrpi3_defconfig
	cd ${TARGET_PATH}/usr/src/linux && \
	ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make distclean && \
	ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make bcmrpi3_defconfig && \
# fix default CPU governor
	sed -Ei \
		-e 's@CONFIG_CPU_FREQ_DEFAULT_GOV_POWERSAVE=y@# CONFIG_CPU_FREQ_DEFAULT_GOV_POWERSAVE is not set@' \
		-e 's@# CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND is not set@CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y@' \
		.config && \
# build kernel
	ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make -j9 && \
# copy kernel
	cp ${TARGET_PATH}/usr/src/linux/arch/${ARCH}/boot/Image ${TARGET_PATH}/boot/kernel8.img && \
	mv ${TARGET_PATH}/boot/bcm2710-rpi-3-b-plus.dtb ${TARGET_PATH}/boot/bcm2710-rpi-3-b-plus.dtb_32 && \
	cp ${TARGET_PATH}/usr/src/linux/arch/${ARCH}/boot/dts/broadcom/bcm2710-rpi-3-b-plus.dtb ${TARGET_PATH}/boot && \
# install kernel module
	ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make modules_install INSTALL_MOD_PATH=${TARGET_PATH} && \
# configure
	sed -i 's@f0:12345:respawn:/sbin/agetty 9600 ttyAMA0 vt100@# \0@' ${TARGET_PATH}/etc/inittab && \
	mkdir -p ${TARGET_PATH}/lib/firmware/brcm && \
	cd ${TARGET_PATH}/lib/firmware/brcm && \
	curl -s -o brcmfmac43455-sdio.bin https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43455-sdio.bin && \
	curl -s -o brcmfmac43455-sdio.txt https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43455-sdio.txt && \
	curl -s -o BCM4345C0.hcd https://raw.githubusercontent.com/RPi-Distro/bluez-firmware/master/broadcom/BCM4345C0.hcd && \
# set root password
	cd ${TARGET_PATH} && \
	sed -Ei 's@^root:.*$@root:$6$xxPVR/Td5iP$/7Asdgq0ux2sgNkklnndcG4g3493kUYfrrdenBXjxBxEsoLneJpDAwOyX/kkpFB4pU5dlhHEyN0SK4eh/WpmO0::0:99999:7:::@' etc/shadow && \
# update world
	ROOT=${TARGET_PATH}/ ${TARGET}-emerge -uq world || exit 0 && \
# install dhcpcd
	ROOT=$PWD/ ${TARGET}-emerge -uq net-misc/dhcpcd && \
# setup pi user
	useradd -P ${TARGET_PATH} -m -G users,wheel,audio -s /bin/bash pi && \
# install qemu for chroot
	QEMU_USER_TARGETS="aarch64" QEMU_SOFTMMU_TARGETS="aarch64" USE="static-user static-libs" emerge -q --buildpkg --oneshot qemu && \
	ROOT=${TARGET_PATH}/ emerge -q --usepkgonly --oneshot --nodeps qemu

# configs
COPY 99-com.rules ${TARGET_PATH}/etc/udev/rules.d/
COPY btattach ${TARGET_PATH}/etc/init.d
COPY fstab ${TARGET_PATH}/etc
COPY config.txt ${TARGET_PATH}/boot
COPY cmdline.txt ${TARGET_PATH}/boot

COPY qemu-chroot.sh /usr/local/bin

# fails with
# ERROR: dev-util/ctags-20161028::gentoo failed (configure phase):
# configure: error: regcomp() on this system is broken.
# RUN cd ${TARGET_PATH} && \
# 	ROOT=$PWD/ ${TARGET}-emerge -uq app-editors/vim


# RUN cd ${TARGET_PATH} && \
# 	tar cfz /mnt/${TARGET}-$(date "+%Y%m%d%H%M").tar.gz . --xattrs-include='*.*' --numeric-owner
