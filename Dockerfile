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
	crossdev --stable -t "${TARGET}"
# test toolchain
RUN ${TARGET}-gcc --version && \
	${TARGET}-c++ --version && \
	${TARGET}-g++ --version
# emerge stuff
# need sys-devel/bc this to build kernel somehow
RUN emerge -qu dev-vcs/git sys-devel/bc

# get kernel and firmare source
# RUN mkdir -p "${RPI_PATH}" && \
# 	cd "${RPI_PATH}" && \
# 	git clone -b stable --depth=1 https://github.com/raspberrypi/firmware
# RUN cd "${RPI_PATH}" && \
# 	git clone --depth 1 -b "${KERNEL_BRANCH}" https://github.com/raspberrypi/linux
# set up baseline bcmrpi3_defconfig
# RUN cd "${RPI_PATH}/linux" && \
# 	ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make distclean && \
# 	ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make bcmrpi3_defconfig
# fix default CPU governor
# RUN cd "${RPI_PATH}/linux" && \
# 	sed -Ei \
# 		-e 's@CONFIG_CPU_FREQ_DEFAULT_GOV_POWERSAVE=y@# CONFIG_CPU_FREQ_DEFAULT_GOV_POWERSAVE is not set@' \
# 		-e 's@# CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND is not set@CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y@' \
# 		.config
# build kernel
# RUN cd "${RPI_PATH}/linux" && \
# 	ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make -j9

RUN mkdir -p ${TARGET_PATH} && \
	cd ${TARGET_PATH} && \
	curl -s -o "${STAGE3_FILE}" "http://distfiles.gentoo.org/experimental/${ARCH}/${STAGE3_FILE}" && \
	curl -s -o "${STAGE3_FILE}.DIGESTS" "http://distfiles.gentoo.org/experimental/${ARCH}/${STAGE3_FILE}.DIGESTS" && \
	sha512sum "${STAGE3_FILE}" | cut -f 1 -d " " | grep -q -f - "${STAGE3_FILE}.DIGESTS" && \
	rm -f "${STAGE3_FILE}.DIGESTS" && \
	tar xpf "${STAGE3_FILE}" --xattrs-include='*.*' --numeric-owner && \
	rm "${STAGE3_FILE}" && \
	rm -rf ${TARGET_PATH}/tmp/*

RUN cd ${TARGET_PATH} && \
# copy host /usr/portage while omitting packages and distfiles
	rsync -aq /usr/portage ./usr --exclude distfiles/* --exclude packages/*

RUN emerge -q layman && \
	layman -q -f && \
	yes | layman -q -a wuodan

RUN mkdir -p /usr/local/portage/{metadata,profiles} && \
	chown -R portage:portage /usr/local/portage && \
	echo 'localrepo' > /usr/local/portage/profiles/repo_name && \
	echo -e 'masters = gentoo\nauto-sync = false\nthin-manifests = true' > /usr/local/portage/metadata/layout.conf && \
	mkdir -p /etc/portage/repos.conf && \
	echo -e '[localrepo]\nlocation = /usr/local/portage' > /etc/portage/repos.conf/localrepo.conf

RUN mkdir -p /usr/local/portage/sys-boot && \
	cp -r /var/lib/layman/wuodan/sys-boot/raspberrypi-firmware /usr/local/portage/sys-boot

RUN cp -ar /usr/local/portage ${TARGET_PATH}/usr/local && \
	mkdir -p ${TARGET_PATH}/etc/portage/repos.conf && \
	cp /etc/portage/repos.conf/localrepo.conf ${TARGET_PATH}/etc/portage/repos.conf/localrepo.conf

RUN mkdir -p ${TARGET_PATH}/etc/portage/package.unmask && \
	echo '<sys-boot/raspberrypi-firmware-9999' >> ${TARGET_PATH}/etc/portage/package.unmask/raspberrypi-firmware && \
	echo '<sys-boot/raspberrypi-firmware-9999 **' >> ${TARGET_PATH}/etc/portage/package.keywords/raspberrypi-firmware && \
	echo '<sys-kernel/raspberrypi-sources-9999 **' >> ${TARGET_PATH}/etc/portage/package.keywords/raspberrypi-sources

# get kernel and firmare source
RUN ARCH=amd64 ROOT=${TARGET_PATH} ${TARGET}-emerge -q	'<sys-boot/raspberrypi-firmware-9999' \
																		'<sys-kernel/raspberrypi-sources-9999'
# set up baseline bcmrpi3_defconfig
RUN cd ${TARGET_PATH}/usr/src/linux && \
	ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make distclean && \
	ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make bcmrpi3_defconfig
# fix default CPU governor
RUN cd ${TARGET_PATH}/usr/src/linux && \
	sed -Ei \
		-e 's@CONFIG_CPU_FREQ_DEFAULT_GOV_POWERSAVE=y@# CONFIG_CPU_FREQ_DEFAULT_GOV_POWERSAVE is not set@' \
		-e 's@# CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND is not set@CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y@' \
		.config
# build kernel
RUN cd ${TARGET_PATH}/usr/src/linux && \
	ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make -j9

RUN cp ${TARGET_PATH}/usr/src/linux/arch/${ARCH}/boot/Image ${TARGET_PATH}/boot/kernel8.img

RUN mv ${TARGET_PATH}/boot/bcm2710-rpi-3-b-plus.dtb ${TARGET_PATH}/boot/bcm2710-rpi-3-b-plus.dtb_32

RUN cp ${TARGET_PATH}/usr/src/linux/arch/${ARCH}/boot/dts/broadcom/bcm2710-rpi-3-b-plus.dtb ${TARGET_PATH}/boot

RUN cd ${TARGET_PATH}/usr/src/linux && \
	ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make modules_install INSTALL_MOD_PATH=${TARGET_PATH}

RUN sed -i 's@f0:12345:respawn:/sbin/agetty 9600 ttyAMA0 vt100@# \0@' ${TARGET_PATH}/etc/inittab

COPY 99-com.rules ${TARGET_PATH}/etc/udev/rules.d/

RUN mkdir -p ${TARGET_PATH}/lib/firmware/brcm && \
	cd ${TARGET_PATH}/lib/firmware/brcm && \
	curl -s -o brcmfmac43455-sdio.bin https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43455-sdio.bin && \
	curl -s -o brcmfmac43455-sdio.txt https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43455-sdio.txt

RUN cd ${TARGET_PATH}/lib/firmware/brcm && \
	curl -s -o BCM4345C0.hcd https://raw.githubusercontent.com/RPi-Distro/bluez-firmware/master/broadcom/BCM4345C0.hcd

COPY btattach ${TARGET_PATH}/etc/init.d

# configs
COPY fstab ${TARGET_PATH}/etc
COPY config.txt ${TARGET_PATH}/boot
COPY cmdline.txt ${TARGET_PATH}/boot

RUN cd ${TARGET_PATH} && \
	sed -Ei 's@^root:.*$@root:$6$xxPVR/Td5iP$/7Asdgq0ux2sgNkklnndcG4g3493kUYfrrdenBXjxBxEsoLneJpDAwOyX/kkpFB4pU5dlhHEyN0SK4eh/WpmO0::0:99999:7:::@' etc/shadow

RUN emerge -q app-emulation/qemu

RUN QEMU_USER_TARGETS="aarch64" QEMU_SOFTMMU_TARGETS="aarch64" USE="static-user static-libs" emerge -q --buildpkg --oneshot qemu

RUN cd ${TARGET_PATH} && \
	ROOT=$PWD/ emerge -q --usepkgonly --oneshot --nodeps qemu

RUN cd ${TARGET_PATH} && \
# RUN ARCH=amd64 ROOT=${TARGET_PATH} ${TARGET}-emerge -q	world
	ROOT=$PWD/ ${TARGET}-emerge -uq world

RUN cd ${TARGET_PATH} && \
	ROOT=$PWD/ ${TARGET}-emerge -uq net-misc/dhcpcd

# setup pi user
RUN useradd -P ${TARGET_PATH} -m -G users,wheel,audio -s /bin/bash pi

# install vim cause nano sucks hard
RUN emerge -qu app-editors/vim
# fails with
# ERROR: dev-util/ctags-20161028::gentoo failed (configure phase):
# configure: error: regcomp() on this system is broken.
# RUN cd ${TARGET_PATH} && \
# 	ROOT=$PWD/ ${TARGET}-emerge -uq app-editors/vim

COPY qemu-chroot.sh /usr/local/bin

# RUN touch ${TARGET_PATH}/run/openrc/softlevel

# RUN cd ${TARGET_PATH} && \
# 	ROOT=$PWD/ emerge --usepkgonly --oneshot --nodeps qemu

# COPY qemu-chroot.sh /usr/local/bin
# # qemu for chroot
# RUN QEMU_USER_TARGETS="${ARCH}" QEMU_SOFTMMU_TARGETS="${ARCH}" USE="static-user static-libs" emerge -q --buildpkg --oneshot qemu

# RUN cd ${TARGET_PATH} && \
# 	ROOT=$PWD/ emerge -q --usepkgonly --oneshot --nodeps qemu

# RUN cd ${TARGET_PATH} && \
# 	tar cfz /mnt/${TARGET}-$(date "+%Y%m%d%H%M").tar.gz . --xattrs-include='*.*' --numeric-owner

# RUN chroot ${TARGET_PATH} /bin/bash -c "rc-update add btattach default" && \
# 	ls -alh ${TARGET_PATH}/etc/init.d
