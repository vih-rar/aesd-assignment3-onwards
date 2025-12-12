#!/bin/bash
# Script outline to install and build kernel.
# Author: Vihar Vasavada.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

ORIG_PWD=$(pwd)
mkdir -p ${OUTDIR}
OUTDIR=$(pwd)/$OUTDIR
echo $OUTDIR
cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # TODO: Add your kernel build steps here
    make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE mrproper
    echo "clean done"
    make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE defconfig
    echo "defconf done"
    make -j4 ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE all
    echo "all done"
    # make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE modules
    # echo "module done"
    make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE dtbs
fi

echo "Adding the Image in outdir"
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image $OUTDIR

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories
mkdir -p $OUTDIR/rootfs 
cd $OUTDIR/rootfs
mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr var
mkdir -p usr/bin usr/lib usr/sbin
mkdir -p var/log

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # TODO:  Configure busybox
    make distclean
    make defconfig
else
    cd busybox
fi

# TODO: Make and install busybox
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE
make CONFIG_PREFIX=${OUTDIR}/busybox ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE install

echo "Library dependencies"

BUSYBOX_BIN=${OUTDIR}/busybox/bin/busybox

${CROSS_COMPILE}readelf -l "${BUSYBOX_BIN}" | awk '/Interpreter|Shared library/ {print}'
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)
ROOTFS=${OUTDIR}/rootfs

sudo mkdir -p "${ROOTFS}/lib" "${ROOTFS}/lib64" "${ROOTFS}/usr/lib" "${ROOTFS}/usr/lib64"

INTERP=$(${CROSS_COMPILE}readelf -l "${BUSYBOX_BIN}" | grep 'program interpreter' | awk -F': ' '/program interpreter/ {gsub(/[][]/,"",$2); print $2}')

SRC="${SYSROOT}${INTERP}"
sudo cp $SRC $ROOTFS/lib/

LIB=$(${CROSS_COMPILE}readelf -a "${BUSYBOX_BIN}" | grep 'Shared library'  \
  | awk -F'[][]' '{print $2}' \
  | sort -u )

for lib in $LIB; do
    FOUND=$(find $SYSROOT -name $lib)
    sudo cp $FOUND $ROOTFS/lib64/
done

sudo cp -a ${OUTDIR}/busybox/* ${ROOTFS}/

sudo mknod -m 666 "${ROOTFS}/dev/null" c 1 3
sudo mknod -m 600 "${ROOTFS}/dev/console" c 5 1

echo "Done"
# TODO: Clean and build the writer utility
cd $ORIG_PWD
make clean
make CROSS_COMPILE=$CROSS_COMPILE

# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs
cp finder.sh writer $ROOTFS/home
cp finder-test.sh conf/username.txt conf/assignment.txt $ROOTFS/home
cp autorun-qemu.sh $ROOTFS/home

# TODO: Chown the root directory

sudo chown -R root:root "${ROOTFS}"

# TODO: Create initramfs.cpio.gz
cd $ROOTFS
find . | cpio -H newc -ov --owner root:root > ${OUTDIR}/initramfs.cpio
gzip -f ${OUTDIR}/initramfs.cpio
