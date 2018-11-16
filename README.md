# gentoo-crossdev-aarch64
gentoo docker image with crossdev to aarch64-unknown-linux-gnu

## Usage
### Setup SDcard for a Raspberry Pi 3 Model B+:
- Format SDcard with msdos partition-table and this layout (F2FS for sda3):
/dev/sda1 fat32 128MiB
/dev/sda2 swap  2GiB
/dev/sda3 f2fs  rest

- Mount /dev/sda3 on /mnt/gentoo and /dev/sda1 on /mnt/gentoo/boot
- Run: ./setupSDcard.sh /mnt/gentoo

### Run a build server with distcc and crossdev
- TODO: docker run -d image ... ports

## Build
1. Stage3: Download the latest arm64 stage3 from:
http://distfiles.gentoo.org/experimental/arm64/
and place it in ./target-files.
2. Update the STAGE3_DATE variable in ./Dockerfile
3. Run ./build.sh - which does:
- docker build: Create amd64 host with arm64 inside (/usr/aarch64-unknown-linux-gnu)
- docker run: Update arm64 in qemu-chroot
- docker commit: Create final image from container of last step
- docker push: Push the final image
