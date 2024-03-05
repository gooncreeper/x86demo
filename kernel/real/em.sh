#!/usr/bin/sh

qemu-system-i386 \
	-drive format=raw,file=build/img \
	-m 1M \
	-nographic \
	$@
