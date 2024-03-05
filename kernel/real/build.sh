#!/bin/sh

NAME=x86demo
BUILD=/tmp/build
FULL_BUILD=$BUILD/$USER"_"$NAME

MBR=$FULL_BUILD/mbr
FS=$FULL_BUILD/fs
KERNEL=$FULL_BUILD/kernel
IMG=$FULL_BUILD/img

mkdir -p $FULL_BUILD
ln -s $FULL_BUILD build
chmod 1777 $BUILD
chmod 0750 $FULL_BUILD

# MBR
nasm bootloader.S -o $MBR

# Filesystem
touch $FS
truncate -s 64M $FS
mkfs.fat -F 16 $FS

# Kernel
nasm all.S -o $KERNEL
mcopy -i $FS $KERNEL ::KERNEL.BIN

# Create disk image and partition
cat $MBR $FS > $IMG
echo ",,6;" | sfdisk $IMG # TODO: FIX THIS SINCE BOOTLOADER IS 2 SECTORS

#rm $MBR, $FS, $KERNEL
