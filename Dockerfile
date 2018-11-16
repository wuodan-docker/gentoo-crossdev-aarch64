# named portage image
FROM gentoo/portage:latest as portage
FROM wuodan/gentoo-crossdev:latest

ARG STAGE3_DATE=20180907

ARG TARGET=aarch64-unknown-linux-gnu
ARG ARCH=arm64
ARG STAGE3_FILE="stage3-${ARCH}-${STAGE3_DATE}.tar.bz2"

ARG TARGET_PATH=/usr/${TARGET}

# host: create toolchain
RUN crossdev --stable -t "${TARGET}" --init-target && \
	echo "cross-${TARGET}/gcc cxx multilib fortran -mudflap nls openmp -sanitize -vtv" >> /etc/portage/package.use/crossdev && \
	crossdev --stable -t "${TARGET}" && \
# host: need sys-devel/bc this to build kernel somehow
	emerge --quiet --update  sys-devel/bc && \
# host: cleanup
	rm -rf /usr/portage/distfiles/*

COPY ${STAGE3_FILE} ${TARGET_PATH}
ADD http://distfiles.gentoo.org/experimental/${ARCH}/${STAGE3_FILE}.DIGESTS ${TARGET_PATH}

# target: install stage3 arm64
RUN sha512sum "${TARGET_PATH}/${STAGE3_FILE}" | cut -f 1 -d " " | grep -q -f - "${TARGET_PATH}/${STAGE3_FILE}.DIGESTS" && \
	rm -f "${TARGET_PATH}/${STAGE3_FILE}.DIGESTS" && \
	tar xpf "${TARGET_PATH}/${STAGE3_FILE}" --xattrs-include='*.*' --numeric-owner -C ${TARGET_PATH}/ && \
	rm "${TARGET_PATH}/${STAGE3_FILE}" && \
	rm -rf ${TARGET_PATH}/tmp/*

# target: copy the entire portage volume
COPY --chown=portage:portage --from=portage /usr/portage/* /usr/portage ${TARGET_PATH}/usr/portage/

# install qemu for chroot
RUN QEMU_USER_TARGETS="aarch64" QEMU_SOFTMMU_TARGETS="aarch64" USE="static-user static-libs" emerge --buildpkg --oneshot --quiet qemu && \
	ROOT=${TARGET_PATH}/ emerge --nodeps --oneshot --quiet --usepkgonly qemu && \
# host: cleanup
	rm -rf /usr/portage/distfiles/*

# target: configure portage
RUN echo -e '\n\
# custom\n\
MAKEOPTS="-j4"\n\
EMERGE_DEFAULT_OPTS="${EMERGE_DEFAULT_OPTS} --jobs=4 --load-average=4"\n\
FEATURES="distcc"\n\
GENTOO_MIRRORS="http://mirror.netcologne.de/gentoo/ http://linux.rz.ruhr-uni-bochum.de/download/gentoo-mirror/ http://ftp-stud.hs-esslingen.de/pub/Mirrors/gentoo/"' >> ${TARGET_PATH}/etc/portage/make.conf

# fix for user.eclass writing to host
RUN mkdir /tmp/user.eclass.fix && \
	cp -a /etc/{group,gshadow,passwd,shadow} /tmp/user.eclass.fix/ && \
# target: update world
	( ROOT=${TARGET_PATH}/ ${TARGET}-emerge --deep --keep-going --newuse --update --quiet world || exit 0 ) && \
# host: cleanup
	rm -rf /usr/portage/distfiles/* && \
	rm -rf /var/tmp/portage/* && \
# fix for user.eclass writing to host
	for f in /tmp/user.eclass.fix/*; do \
		echo $(basename $f); \
		diff /tmp/user.eclass.fix/$(basename $f) /etc/$(basename $f)  | sed -n 's/^> //p' >> /usr/aarch64-unknown-linux-gnu/etc/$(basename $f); \
	done && \
	rm -rf /tmp/user.eclass.fix

# target: install layman
RUN ROOT=${TARGET_PATH}/ ${TARGET}-emerge --oneshot --quiet --update app-portage/layman && \
# host: cleanup
	rm -rf /usr/portage/distfiles/*

# docker: force update of wuodan overlay
# ADD https://github.com/Wuodan/gentoo-overlay/archive/master.zip /tmp/wuodan-master.zip
# RUN rm /tmp/wuodan-master.zip

# host: trick layman into target root
# target: install wuodan overlay
RUN cp -a /etc/layman/layman.cfg /etc/layman/layman.cfg.bak && \
	sed -Ei -e "s#^storage   : /#storage   : ${TARGET_PATH}/#" -e "s#^repos_conf : /#repos_conf : ${TARGET_PATH}/#" /etc/layman/layman.cfg && \
	mkdir -p ${TARGET_PATH}/etc/portage/repos.conf && \
	layman -f && \
	yes | layman -a pentoo wuodan && \
	mv /etc/layman/layman.cfg.bak /etc/layman/layman.cfg

# target: set wuodan profile
RUN rm ${TARGET_PATH}/etc/portage/make.profile && \
	ln -s ../../var/lib/layman/wuodan/profiles/wuodan/default/linux/arm64 ${TARGET_PATH}/etc/portage/make.profile

# fix for user.eclass writing to host
RUN mkdir /tmp/user.eclass.fix && \
	cp -a /etc/{group,gshadow,passwd,shadow} /tmp/user.eclass.fix/ && \
# target: update world
# this should install essential and nice-to-have packages from the wuodan profile
# including kernel source and firmare
	( ROOT=${TARGET_PATH}/ ${TARGET}-emerge --deep --keep-going --newuse --update --quiet world || exit 0 ) && \
# host: cleanup
	rm -rf /usr/portage/distfiles/* && \
	rm -rf /var/tmp/portage/* && \
# fix for user.eclass writing to host
	for f in /tmp/user.eclass.fix/*; do \
		echo $(basename $f); \
		diff /tmp/user.eclass.fix/$(basename $f) /etc/$(basename $f)  | sed -n 's/^> //p' >> /usr/aarch64-unknown-linux-gnu/etc/$(basename $f); \
	done && \
	rm -rf /tmp/user.eclass.fix && \
# host: install distcc (not before now, it creates a user and group)
	emerge --quiet sys-devel/distcc

# target: setup kernel source and firmare
# target: set up baseline bcmrpi3_defconfig
RUN ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make --directory ${TARGET_PATH}/usr/src/linux distclean && \
	ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make --directory ${TARGET_PATH}/usr/src/linux bcmrpi3_defconfig && \
# target: fix default CPU governor
	sed -Ei \
		-e 's@CONFIG_CPU_FREQ_DEFAULT_GOV_POWERSAVE=y@# CONFIG_CPU_FREQ_DEFAULT_GOV_POWERSAVE is not set@' \
		-e 's@# CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND is not set@CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y@' \
		${TARGET_PATH}/usr/src/linux/.config && \
# target: build kernel
	ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make --directory ${TARGET_PATH}/usr/src/linux -j9 --directory ${TARGET_PATH}/usr/src/linux && \
# target: copy kernel
	cp ${TARGET_PATH}/usr/src/linux/arch/${ARCH}/boot/Image ${TARGET_PATH}/boot/kernel8.img && \
# target: install kernel module
	ARCH=${ARCH} CROSS_COMPILE=${TARGET}- make --directory ${TARGET_PATH}/usr/src/linux modules_install INSTALL_MOD_PATH=${TARGET_PATH}

# target: install the device tree
# for Raspberry Pi 3B:
RUN mv ${TARGET_PATH}/boot/bcm2710-rpi-3-b.dtb ${TARGET_PATH}/boot/bcm2710-rpi-3-b.dtb_32 && \
	cp ${TARGET_PATH}/usr/src/linux/arch/${ARCH}/boot/dts/broadcom/bcm2710-rpi-3-b.dtb ${TARGET_PATH}/boot && \
# for Raspberry Pi 3B Plus:
	mv ${TARGET_PATH}/boot/bcm2710-rpi-3-b-plus.dtb ${TARGET_PATH}/boot/bcm2710-rpi-3-b-plus.dtb_32 && \
	cp ${TARGET_PATH}/usr/src/linux/arch/${ARCH}/boot/dts/broadcom/bcm2710-rpi-3-b-plus.dtb ${TARGET_PATH}/boot

RUN exit 1

# target: install wifi firmware
# Raspberry Pi 3B: brcmfmac43430-sdio.txt and brcmfmac43430-sdio.bin 
ADD https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43430-sdio.bin ${TARGET_PATH}/lib/firmware/brcm
ADD https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43430-sdio.txt ${TARGET_PATH}/lib/firmware/brcm
# Raspberry Pi 3B Plus: brcmfmac43455-sdio.txt and brcmfmac43455-sdio.bin
ADD https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43455-sdio.bin ${TARGET_PATH}/lib/firmware/brcm
ADD https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43455-sdio.txt ${TARGET_PATH}/lib/firmware/brcm

# target: install bluetooth firmware
# Raspberry Pi 3B: BCM43430A1.hcd
ADD https://raw.githubusercontent.com/RPi-Distro/bluez-firmware/master/broadcom/BCM43430A1.hcd ${TARGET_PATH}/lib/firmware/brcm
# Raspberry Pi 3B+: BCM4345C0.hcd
ADD https://raw.githubusercontent.com/RPi-Distro/bluez-firmware/master/broadcom/BCM4345C0.hcd ${TARGET_PATH}/lib/firmware/brcm

# target: files for target
COPY target-files/ ${TARGET_PATH}/

# target: configure serial port configuration (udev-rule file is in target-files)
RUN sed -i 's@f0:12345:respawn:/sbin/agetty 9600 ttyAMA0 vt100@# \0@' ${TARGET_PATH}/etc/inittab && \
# target: set timezone to Europe/Zurich (see target-files/etc/timezone)
	ROOT=${TARGET_PATH}/ ${TARGET}-emerge --config --quiet sys-libs/timezone-data && \
# host: cleanup
	rm -rf /usr/portage/distfiles/* && \
	rm -rf /var/tmp/portage/*

# target: fix layman.conf
RUN sed -i "s#${TARGET_PATH}##g" ${TARGET_PATH}/etc/portage/repos.conf/layman.conf

# target: setup pi user
RUN useradd -P ${TARGET_PATH} -m -G users,wheel,audio -s /bin/bash pi && \
# target: let wheel execute sudo
	sed -Ei 's@^# (%wheel ALL=\(ALL\) ALL)$@\1@' ${TARGET_PATH}/etc/sudoers && \
# set password of pi to raspberry and force reset of password on first login
	sed -Ei 's#^pi:.*$#pi:$6$m0lncX2beGNdmvTt$vsgvDQsLEa5KVAK5ZVgIx5x01krxOuxiBgyUN2y10j.6xd2nFQOvBwCXLv0S6K.uMY7SkE.SxhEYxnfMDR4NO0:0:0:99999:7:::#' \
		${TARGET_PATH}/etc/shadow

# host: only qemu-chroot.sh script at the moment, thus last
COPY host-files/ /

# install umeq and proot
# ARG UMEQ_VERSION=1.7.10
# ADD https://raw.githubusercontent.com/mickael-guene/proot-static-build/master-umeq/static/proot-x86_64 /usr/local/bin
# ADD https://github.com/mickael-guene/umeq/releases/download/${UMEQ_VERSION}/umeq-arm64 /usr/local/bin

# fails with
# ERROR: dev-util/ctags-20161028::gentoo failed (configure phase):
# configure: error: regcomp() on this system is broken.
# RUN cd ${TARGET_PATH} && \
# 	ROOT=$PWD/ ${TARGET}-emerge -uq app-editors/vim


# RUN cd ${TARGET_PATH} && \
# 	tar cfz /mnt/${TARGET}-$(date "+%Y%m%d%H%M").tar.gz . --xattrs-include='*.*' --numeric-owner
