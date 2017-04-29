export RELEASE_NAME ?= dev
export RELEASE ?= 1
export LINUX_BRANCH ?= my-hacks-3.0
export BOOT_TOOLS_BRANCH ?= master
LINUX_LOCALVERSION ?= -ayufan-$(RELEASE)

all: xenial-pinebook

linux/.git:
	git clone --depth=1 --branch=$(LINUX_BRANCH) --single-branch \
		https://github.com/ayufan-pine64/linux-pine64.git linux

linux/.config: linux/.git
	make -C linux ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" clean CONFIG_ARCH_SUN50IW1P1=y
	make -C linux ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" sun50iw1p1smp_linux_defconfig
	touch linux/.config

linux/arch/arm64/boot/Image: linux/.config
	make -C linux ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" -j4 LOCALVERSION=$(LINUX_LOCALVERSION) Image
	make -C linux ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" -j4 LOCALVERSION=$(LINUX_LOCALVERSION) modules
	make -C linux LOCALVERSION=$(LINUX_LOCALVERSION) M=modules/gpu/mali400/kernel_mode/driver/src/devicedrv/mali \
		ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" \
		CONFIG_MALI400=m CONFIG_MALI450=y CONFIG_MALI400_PROFILING=y \
		CONFIG_MALI_DMA_BUF_MAP_ON_ATTACH=y CONFIG_MALI_DT=y \
		EXTRA_DEFINES="-DCONFIG_MALI400=1 -DCONFIG_MALI450=1 -DCONFIG_MALI400_PROFILING=1 -DCONFIG_MALI_DMA_BUF_MAP_ON_ATTACH -DCONFIG_MALI_DT"

busybox/.git:
	git clone --depth 1 --branch 1_24_stable --single-branch git://git.busybox.net/busybox busybox

busybox: busybox/.git
	cp -u kernel/pine64_config_busybox busybox/.config
	make -C busybox ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" -j4 oldconfig

busybox/busybox: busybox
	make -C busybox ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" -j4

kernel/initrd.gz: busybox/busybox
	cd kernel/ && ./make_initrd.sh

boot-tools/.git:
	git clone --single-branch --depth=1 --branch=$(BOOT_TOOLS_BRANCH) https://github.com/ayufan-pine64/boot-tools

boot-tools: boot-tools/.git

linux-pine64-$(RELEASE_NAME).tar: linux/arch/arm64/boot/Image boot-tools kernel/initrd.gz
	cd kernel && \
		bash ./make_kernel_tarball.sh $(shell readlink -f "$@")

%.tar.xz: %.tar
	pxz -f -3 $<

%.img.xz: %.img
	pxz -f -3 $<

simple-image-pinebook-$(RELEASE_NAME).img: linux-pine64-$(RELEASE_NAME).tar.xz boot-tools
	cd simpleimage && \
		export boot0=../boot-tools/build/boot0_pinebook.bin && \
		export uboot=../boot-tools/build/u-boot-sun50iw1p1-secure-with-pinebook-dtb.bin && \
		bash ./make_simpleimage.sh $(shell readlink -f "$@") 100 $(shell readlink -f linux-pine64-$(RELEASE_NAME).tar.xz)

xenial-pinebook-bspkernel-$(RELEASE_NAME)-$(RELEASE).img: simple-image-pinebook-$(RELEASE_NAME).img.xz linux-pine64-$(RELEASE_NAME).tar.xz boot-tools
	sudo bash ./build-pine64-image.sh \
		$(shell readlink -f $@) \
		$(shell readlink -f simple-image-pinebook-$(RELEASE_NAME).img.xz) \
		$(shell readlink -f linux-pine64-$(RELEASE_NAME).tar.xz) \
		xenial \
		pinebook

.PHONY: kernel-tarball
kernel-tarball: linux-pine64-$(RELEASE_NAME).tar.xz

.PHONY: simple-image-pinebook-$(RELEASE_NAME).img
simple-image-pinebook: simple-image-pinebook-$(RELEASE_NAME).img

.PHONY: xenial-pinebook
xenial-pinebook: xenial-pinebook-bspkernel-$(RELEASE_NAME)-$(RELEASE).img.xz
