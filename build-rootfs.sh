#!/bin/bash

STAMP=${1-$(date +"%Y_%b_%d")}

set -euo pipefail


build_cpython() {
	cd ${BASE}
	mkdir -p obj_cpython
	cd obj_cpython
	cat <<EOF > ./config.site
ac_cv_file__dev_ptmx=no
ac_cv_file__dev_ptc=no
EOF
	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH \
		CONFIG_SITE=${PWD}/config.site \
       		READELF=llvm-readelf \
		HOSTCC=cc \
       		CC=hexagon-unknown-linux-musl-clang \
		CFLAGS="-mlong-calls -mv65 -static" \
		LDFLAGS="-static" \
		CPPFLAGS="-static" \
		../cpython/configure \
	       		--host=hexagon-unknown-linux-musl \
	       		--build=x86_64-linux-gnu \
	       		--disable-ipv6 \
                        --disable-shared \
                        --with-ensurepip=no \
                        --prefix=${ROOTFS}
	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH make -j
	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH make test || /bin/true
	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH make install
}

build_busybox() {
	cd ${BASE}
	mkdir -p obj_busybox
	cd obj_busybox

	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH \
		make -f ../busybox/Makefile defconfig \
		KBUILD_SRC=../busybox/ \
		AR=llvm-ar \
		RANLIB=llvm-ranlib \
		STRIP=llvm-strip \
	       	ARCH=hexagon \
		CFLAGS="-mlong-calls" \
		HOSTCC=cc \
		CC=clang \
		CROSS_COMPILE=hexagon-unknown-linux-musl-

	PATH=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin/:$PATH \
		make -j install \
		AR=llvm-ar \
		RANLIB=llvm-ranlib \
		STRIP=llvm-strip \
	       	ARCH=hexagon \
		KBUILD_VERBOSE=1 \
		CFLAGS="-G0 -mlong-calls" \
		CONFIG_PREFIX=${ROOTFS} \
		HOSTCC=cc \
		CC=clang \
		CROSS_COMPILE=hexagon-unknown-linux-musl-

}

build_canadian_clang() {
	cd ${BASE}
	mkdir -p obj_canadian
	cd obj_canadian

	cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX:PATH=${ROOTFS} \
		-DLLVM_CCACHE_BUILD:BOOL=OFF \
		-DLLVM_ENABLE_LIBCXX:BOOL=ON \
		-DLLVM_ENABLE_ASSERTIONS:BOOL=ON \
		-DCMAKE_CROSSCOMPILING:BOOL=ON \
		-DCMAKE_SYSTEM_NAME:STRING=Linux \
		-DCMAKE_C_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DCMAKE_ASM_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang" \
		-DCMAKE_CXX_COMPILER:STRING="${TOOLCHAIN_BIN}/hexagon-unknown-linux-musl-clang++" \
		-DLLVM_TABLEGEN=${TOOLCHAIN_BIN}/llvm-tblgen \
		-DCMAKE_C_FLAGS:STRING="-G0 -mlong-calls --target=hexagon-unknown-linux-musl " \
		-DCMAKE_CXX_FLAGS:STRING="-G0 -mlong-calls --target=hexagon-unknown-linux-musl " \
		-DLLVM_DEFAULT_TARGET_TRIPLE=hexagon-unknown-linux-musl \
		-DLLVM_TARGET_ARCH="Hexagon" \
		-DLLVM_BUILD_RUNTIME:BOOL=OFF \
		-DBUILD_SHARED_LIBS:BOOL=OFF \
		-DLLVM_INCLUDE_TESTS:BOOL=OFF \
		-DLLVM_INCLUDE_EXAMPLES:BOOL=OFF \
		-DLLVM_INCLUDE_UTILS:BOOL=OFF \
                -DHAVE_STEADY_CLOCK:BOOL=OFF \
                -DHAVE_POSIX_REGEX:BOOL=OFF \
                -DLLVM_ENABLE_PIC:BOOL=OFF \
		-DLLVM_TARGETS_TO_BUILD:STRING="Hexagon" \
		-DLLVM_ENABLE_PROJECTS:STRING="clang;lld" \
		../llvm-project/llvm

        ninja -v
        ninja -v install

}

build_dropbear() {
	cd ${BASE}
	mkdir -p obj_dropbear
	cd obj_dropbear
	echo FIXME TODO
}

build_kernel() {
	cd ${BASE}
	mkdir obj_linux
	cd linux
	make -j $(nproc) \
		O=../obj_linux ARCH=hexagon \
		CROSS_COMPILE=hexagon-unknown-linux-musl- \
		HOSTCC=cc \
		AS=clang \
		CC=clang \
		LD=ld.lld \
		LLVM=1 \
		LLVM_IAS=1 \
		KBUILD_VERBOSE=1 \
		comet_defconfig

	make -j $(nproc) \
		O=../obj_linux ARCH=hexagon \
		CROSS_COMPILE=hexagon-unknown-linux-musl- \
		HOSTCC=cc \
		AS=clang \
		CC=clang \
		LD=ld.lld \
		LLVM=1 \
		LLVM_IAS=1 \
		KBUILD_VERBOSE=1 \
		vmlinux
}

get_src_tarballs() {
	cd ${BASE}

	wget --quiet ${BUSYBOX_SRC_URL} -O busybox.tar.bz2
	mkdir busybox
	cd busybox
	tar xf ../busybox.tar.bz2 --strip-components=1
	cd -

}
TOOLCHAIN_INSTALL_REL=${TOOLCHAIN_INSTALL}
TOOLCHAIN_INSTALL=$(readlink -f ${TOOLCHAIN_INSTALL})
TOOLCHAIN_BIN=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/bin
HEX_SYSROOT=${TOOLCHAIN_INSTALL}/x86_64-linux-gnu/target/hexagon-unknown-linux-musl
HEX_TOOLS_TARGET_BASE=${HEX_SYSROOT}/usr
ROOT_INSTALL_REL=${ROOT_INSTALL}
ROOT_INSTALL=$(readlink -f ${ROOT_INSTALL})
ROOTFS=$(readlink -f ${ROOT_INSTALL})
RESULTS_DIR=$(readlink -f ${ARTIFACTS})

BASE=$(readlink -f ${PWD})

set -x
export PATH=${TOOLCHAIN_BIN}:${PATH}
cp -ra ${HEX_SYSROOT}/usr ${ROOTFS}/

. /etc/profile.d/cmake-latest.sh
. /etc/profile.d/ninja-latest.sh
. /etc/profile.d/clang-latest.sh
. /etc/profile.d/py3-latest.sh
get_src_tarballs

build_kernel
build_busybox

#build_dropbear
#build_cpython

# Recipe still needs tweaks:
#	ld.lld: error: crt1.c:(function _start_c: .text._start_c+0x5C): relocation R_HEX_B22_PCREL out of range: 2688980 is not in [-2097152, 2097151]; references __libc_start_main
#	>>> defined in ... hexagon-unknown-linux-musl/usr/lib/libc.so
#build_canadian_clang
rm -rf obj_*

cat <<'EOF' > ${ROOTFS}/init
#!/bin/sh
 
mount -t proc none /proc
mount -t sysfs none /sys
mount -t debugfs none /sys/kernel/debug
 
exec /bin/sh
EOF
chmod +x ${ROOTFS}/init

if [[ ${MAKE_TARBALLS-0} -eq 1 ]]; then
    tar c -C $(dirname ${ROOT_INSTALL_REL}) $(basename ${ROOT_INSTALL_REL}) | xz -e9T0 > ${RESULTS_DIR}/hexagon_rootfs_${STAMP}.tar.xz
#   XZ_OPT="-8 --threads=0" tar c ${RESULTS_DIR}/hexagon_rootfs_${STAMP}.tar.xz  -C $(dirname ${ROOT_INSTALL_REL}) $(basename ${ROOT_INSTALL_REL})

    cd ${RESULTS_DIR}
    sha256sum hexagon_rootfs_${STAMP}.tar.xz > hexagon_rootfs_${STAMP}.tar.xz.sha256
    rm -rf ${ROOT_INSTALL}
    rm -rf ${TOOLCHAIN_INSTALL}
fi
