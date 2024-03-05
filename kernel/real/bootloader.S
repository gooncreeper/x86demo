; ** NOTICE:
; This file is still work in progress and contains many bugs.

	ORG 0x7c00
	CPU 186
	BITS 16

%define INT_BASE 0x60

%define KERNEL_SEGMENT 0x0800
%define KERNEL_ADDRESS 0x0000
%define KERNEL_PATH "KERNEL.BIN"

%define STACK_SEGMENT 0x0060 ; 0x0600 -
%define STACK_ADDRESS 0x7600 ; 0x7C00

; COMPATABILITY:
; The earliest CPU that is able to support this bootloader is the
; 80186, notably due to PUSHA/POPA, PUSH immediate, and three operand
; IMUL.

; LIMITATIONS:
; * FAT16s with more than 4096 root directory entries are not supported.
; * Long file names are not supported.
; * Sector sizes which are not a multiple of two are not supported.

; ENVIRONMENT:
; The kernel shall be entered with SS:SP =  STACK_SEGMENT: STACK_ADDRESS
;                                  CS:IP = KERNEL_SEGMENT:KERNEL_ADDRESS
;                                     DL = Boot drive number from BIOS
;                                  DF,IF = 0
; The values in all other registers are undefined and should not be relied
; upon.
;
; The bootloader shall be located at 0x7E00-0x7FFF and all values in that
; range are considered undefined. If values are modified in this range,
; then the behavoir of the bootloader's interrupts should be considered
; undefined.
;
; All memory from STACK_SEGMENT:0 to STACK_SEGMENT:STACK_ADDRESS should
; be considered undefined.
;
; Interrupts past what is provided by the BIOS shall be as listed in the
; interrupts section.

; ERRORS:
; Format: [O][L][:EE]
; O: Origin
	; B : Bootloader
	; (Suggested) K : Kernel
	; (Suggested) U : Userspace
; L: Letter
	; Letters are described for when Origin is bootloader, may alies with other
	; origin letter sets.
	; d : Debug
	; F : Kernel file not found
	; P : Could not find partition with FAT16 label
	; E : BIOS support for extended read / drive paramaters not indicated
	; S : Stack overflow
	; e : BIOS check extensions present failure
	; r : BIOS extended read failure
	; p : BIOS extended read drive paramaters failure
; EE: BIOS Error Code (hex) if letter is lowercase

; REGISTER PAIRS
;  high:low
;  most:least signifigant

; INTERRUPTS:
; This bootloader provides many useful interrupts for accessing the disk.
; The interrupt numbers here should be interpreted as VECTOR - 0x60 + INT_BASE
; unless it is an exception handler. Any registers not listed under the returned
; section are unmodified.

%define INT_SS 0x0C
; 0x0C Stack-Segment Exception Handler
	; Description
		; Calls INT_PANIC with error type 'S'
		; * May be changed by non-bootloader services. 

%define INT_PANIC INT_BASE + 0x00
; 0x60: Panic
	; Description
		; Outputs error message as described in ERRORS. Error
		; origin is stored at far pointer in INT Panic Origin.
		; * Origin and Error Type must not be ':'
	; Paramaters
		; AL = Error Type Letter != ':'
		; AL & 0x20 = Output error number (lowercase letter)
		; AH = Error Number

%define INT_PANIC_ORIGIN INT_BASE + 0x01
; 0x61: Panic Origin
	; Description
		; Far Pointer to character of origin.
		; * IVT entry is ignored by INT Panic.
	; Far Pointer
		; BYTE [POINTER + 0x00] = Origin Letter != ':'

%define INT_DIV_DWORD INT_BASE + 0x02
; 0x62: Divide Doubleword
	; Paramaters
		; DX:AX = Dividend
		; BX:CX = Divisor
	; Returned
		; DX:AX = Quotient
		; BX:CX = Remainder

%define INT_DISK_SECTOR_SIZE INT_BASE + 0x03
; 0x63: Disk Sector Size
	; Description
		; Returns sector size for given disk. Additionally, if the interrupt
		; does not fail, the drive supports access through DAP and has EDD.
	; Paramaters
		; DL = BIOS Drive Number

		; SP & 1 == 0 (Stack alignment of two bytes)
	; Returned
		; CF = 0 = No Error
			; CX - Sector size
		; CF = 1 = Error
			; AL = Error Code
			; AH = BIOS error code or undef

%define INT_DISK_STACK_READ INT_BASE + 0x04
; 0x64: Disk Stack Read
	; Description
		; Reads a disk sector onto the stack.
	; Paramaters
		; DL = BIOS Drive Number
		; BX:AX = Sector LBA

		; SP & 1 == 0 (Stack alignment of two bytes)
	; Returned
		; XMMWORD [SP - 0x10] = Not sector data

		; CF = 0 = No Error
			; SI - Sector data start (in SS)
		; CF = 1 = Error
			; AL = Error Code
			; AH = BIOS error code or undef

%define INT_DISK_BYTE_READ INT_BASE + 0x05
; 0x65: Disk Byte Read
	; Description
		; Reads bytes from the disk. The blocks of the bytes are determined via
		; the disk's sector size. If aborted early, CX contains how many bytes
		; were not modified before the end of the buffer.
		; * If ES:DI + Bytes is outside the segment bounds, the address (DI) wraps
		; around.
	; Paramaters
		; DL = BIOS Drive Number
		; BX:AX = Byte Offset
		; CX = Bytes
		; ES:DI = Destination (wraps)

		; SP & 1 == 0 (Stack alignment of two bytes)
	; Returned
		; CX = Bytes unread
	
		; CF = 0 = No error
		; CF = 1 = Error
			; AL = Error Code
			; AH = BIOS error code

%define INT_READ_FAT_FILE INT_BASE + 0x06
; 0x66: Read FAT File
	; Description
		; Reads a FAT file of given name, determined via INT stat fat file, to
		; the given address. If aborted early, CX contains how many bytes were
		; not modified before the end of the buffer.
	; Paramaters
		; DL = BIOS Drive Number
		; DH = FAT Partition scan start

		; DS:SI - File path (null terminated)
		; ES:DI - File output buffer

		; SP & 1 == 0 (Stack alignment of two bytes)
	; Notes
		; Disk is boot disk
		; Partition is first valid found in MBR on boot
	; Returned
		; DH = Partition used (if applicable)
			; 5 = None

		; BX:CX = Bytes unread

		; CF = 0 = No error
		; CF = 1 = Error
			; AL = Error Code
			; AH = BIOS error code or undef

%define INT_STAT_FAT_FILE INT_BASE + 0x07
; 0x67: STAT FAT File
	; Description
		; Returns information about a FAT file (system). The partition holding
		; the FAT file system is determined via the MBR on the passed drive. The
		; first FAT16 partition >= the passed scan start is choosen.
	; Paramaters
		; DL = BIOS Drive Number
		; DH = FAT Partition scan start (0-indexed)

		; DS:SI - File path
		; ES:DI - Stat output buffer

		; SP & 1 == 0 (Stack alignment of two bytes)
	; Notes
		; Disk is boot disk
		; Partition is first valid found in MBR on boot
	; Returned
		; DH = Partition used (if applicable)
			; 5 = None
	
		; CF = 0 = No error
			; DWORD [DI + 0x00] = FAT LBA
			; DWORD [DI + 0x04] = Cluster 0 LBA
			;  WORD [DI + 0x08] = First cluster
			;  WORD [DI + 0x0A] = Bytes per sector
			;  WORD [DI + 0x0C] = Sectors per cluster
			;  WORD [DI + 0x0E] = RESERVED

			; BX:CX = File size (bytes)
		; CF = 1 = Error
			; AL = Error Code
			; AH = BIOS error code or undef

; INTERRUPT ERROR CODES:
	; AL = 'F' = File not found
	; AL = 'P' = No FAT partition found (should not happen outside of bootloader)
	; AL = 'E' = BIOS support for extended read / drive paramaters not indicated
	; AL = 'S' = Subtraction Stack Segment Exception
	; AL = 'e' = BIOS check extensions present failure
	; AL = 'r' = BIOS extended read failure
	; AL = 'p' = BIOS extended read drive paramaters failure

head:
	cli ; IVT not set up
	cld
	jmp 0:init ; Some BIOSes may try 0x7c0:0000, not today

kernel_path:
	DB KERNEL_PATH
	DB 0 ; Null terminator

panic_string:
	DB `\nPANIC `
int_panic_origin: ; Interrupt 0x61
	DB "B" ; Initialized B BOOTLOADER
panic_info:
	DB "%:"

buffer: ; Int Addresses & Init are used as a buffer (since they are only used once)

int_addresses:
	DW int_ss
	%define INTERRUPTS 8
	DW int_panic
	DW int_panic_origin
	DW int_div_dword
	DW int_disk_sector_size
	DW int_disk_stack_read
	DW int_disk_byte_read
	DW int_stat_fat_file
	DW int_read_fat_file

init:
	; Initialize stack
	push STACK_SEGMENT
	pop ss
	mov sp, STACK_ADDRESS

	; Set segments to 0
	push cs ; CS is always 0
	push cs ; Don't be suprised when we push CS (alot)
	pop ds
	pop es
init_ivt:
	mov si, int_addresses
	xor ax, ax

	mov di, int_ss * 4
	movsw
	stosw

	mov di, INT_BASE * 4 ; IVT entry
	mov cx, INTERRUPTS
next_ivt_interrupt:
	movsw ; Address
	stosw ; AX = CS = 0
	loop next_ivt_interrupt
load1024:
	; We are going read the bytes 512-1024 of the disk to 0x7E00-0x7FFF since
	; we aren't fitting everything in just 512 bytes.
	; (I mean the addresses are just begging us to do it and EXT4 reserves a
	; 1024 byte region at the start of the filesystem for bootloaders / MBR
	; so yah, and we're not fitting everything otherwise.)

	; Source
	xchg bx, ax ; BX = 0
	mov ax, 512
	mov cx, ax
	; Output
	mov di, 0x7E00
	; Interrupt
	int INT_DISK_BYTE_READ
	jc int_panic
load_kernel:
	; Output
	push KERNEL_SEGMENT
	pop es
	mov di, KERNEL_ADDRESS
	; File name
	mov si, kernel_path
	; Interrupt
	xor dh, dh ; Any partition from zero works
	int INT_READ_FAT_FILE
	jc int_panic
enter_kernel:
	jmp KERNEL_SEGMENT:KERNEL_ADDRESS

%define STACK_AX bp + 0x10
%define STACK_CX bp + 0x0E
%define STACK_DX bp + 0x0C
%define STACK_BX bp + 0x0A
%define STACK_SP bp + 0x08
%define STACK_BP bp + 0x06
%define STACK_SI bp + 0x04
%define STACK_DI bp + 0x02
%define STACK_DS bp + 0x00

; Interrupt 0x0C #SS
int_ss:
	mov al, 'S'
; Interrupt 0x60
int_panic:
	push cs
	pop ds

	xchg dx, ax
	; DH = Error Number
	; DL = Error Type Letter
	
	mov si, panic_string
	mov BYTE [si + panic_info - panic_string], dl

	mov ah, 0Eh ; Teletype output (on QEMU one character is seemingly buffered)
	xor bx, bx ; BL = Color 0, BH = Page 0
	cld
panic_string_char:
	lodsb
	int 10h ; Video Interrupt
	cmp al, ':'
	jne panic_string_char
panic_test_lower:
	test dl, 0x20 ; ASCII lowercase
	jz halt
	mov cx, 3 ; CX = Digits remaining (+1 for buffer)
panic_hex:
	mov al, dh ; AL = Hex Character
	shr al, 4
	add al, '0'
	cmp al, '9' ; Check 0-9
	jng panic_hex_out
	add al, 'A' - '9'
panic_hex_out:
	int 10h
	shl dh, 4 ; Next digit
	loop panic_hex
halt:
	hlt
	jmp halt

; Interrupt 0x62
int_div_dword:
	push bp
	push di
	push si

	; BP:DI = Divisor 
	mov bp, bx
	mov di, cx

	; BX:SI = Remainder
	xor bx, bx
	xor si, si

	; CX = Bits Remaining
	mov cx, 32

	; BP:DI | CF:[BX:SI]:[DX:AX]
	clc
division_step:
	; Rotate division buffer
	rcl ax, 1
	rcl dx, 1
	rcl si, 1
	rol bx, 1 ; We won't ever have a bit that shifts into CF

	; Check if we can divide
	sub si, di
	sbb bx, bp
	jbe division_success
division_failure:
	; Undo subtraction
	add si, di
	adc bx, bp
	clc
	loop division_step
	jmp division_return
division_success:
	stc ; ZF = 1
	loop division_step
division_return:
	mov cx, si
	pop si
	pop di
	pop bp
	iret

; Interrupt 0x63
int_disk_sector_size:
	pusha
	push ds
	mov bp, sp

	push cs
	pop ds
check_ext_present:
	mov ah, 41h
	mov bx, 0x55AA
	int 13h
	mov al, 'e'
	jc error_iret

	cmp bx, 0xAA55
	mov al, 'E'
	jne error_iret ; Not installed

	not cl
	test cl, 0b101
	jnz error_iret ; Disk Access Packet (DAP) or EDD Support missing
find_sector_size: ; AX = Sector buffer size ; DI = Sectors
;Drive Paramaters Structure
;OFF:SIZE
; 0h:1h ; Size
;18h:2h ; Bytes per sector
	mov si, buffer
	mov BYTE [si], 0x1A ; Size (v1.x)
	mov ax, 48h << 8 | 'p'
	int 13h
	jc error_iret

	mov cx, WORD [si + 0x18] ; CX = Sector Size
return_sector_size:
	mov WORD [ss: STACK_CX], cx ; BIOS could be cringe and give us different DS:SI buffer
success_iret:
	mov sp, bp

	pop ds
	popa

	popf
	clc
	pushf
	iret

; Interrupt 0x64
int_disk_stack_read:
	pusha
	push ds
	mov bp, sp

	; DS = SS
	push ss
	pop ds
read_sector:
;DAP Structure
;OFF:SIZE
; 0h:1h ; DAP Size
; 2h:2h ; Sectors to Access
; 4h:2h ; Address
; 6h:2h ; Segment
; 8h:8h ; LBA
	; SP = +0x10
	push cs
	push cs
	push bx
	push ax ; LBA ; SB = +0x08
	push ss ; Segment ; SP = +0x06
	push cs ; Placeholder Address ; SP = +0x04
	push 1  ; Sectors ; SP = +0x02
	push 0x10 ; DAP Size ; SP = +0x00
	mov si, sp

	int INT_DISK_SECTOR_SIZE
	jc error_iret
	
	sub sp, cx ; SP = Buffer pointer
	           ; *If sector is not multiple two bytes stack becomes unaligned
	jc ss_exception_iret
	mov [si + 0x04], sp ; Address
	; and sp, 1 ; Align stack

	; BIOS extended read [SP = -0x02]
	mov ah, 42h
	int 13h
	mov al, 'r'
	jc error_iret
return_sector:
	mov [STACK_SI], sp
	jmp success_iret

; Interrupt 0x65 - aka. where register preasure was invented
int_disk_byte_read:
	pusha
	push ds
	mov bp, sp

	push ds
	pop ss
get_sector_size:
	int INT_DISK_SECTOR_SIZE
	jc error_iret
read_at_address:
	push cx

	; Divide byte address by sector size
	push dx
	mov dx, bx ; DX:AX = Dividend
	xor bx, bx ; BX:CX = Divisor
	int INT_DIV_DWORD ; CX = Sector Offset

	; Read data and offset SI
	mov bx, dx ; BX:AX = Sector (Remainder can only be in CX)
	pop dx
	int INT_DISK_STACK_READ
	jc error_iret
	add si, cx

	; CX = Bytes to Copy = min(Bytes Remaining, (Sector Size - Offset))
	neg cx
	add cx, WORD [bp - 2]
	cmp WORD [STACK_CX], cx
	jb copy_data
	mov cx, WORD [STACK_CX]
copy_data:
	add ax, cx
	adc bx, 0

	sub WORD [STACK_CX], cx
	pop cx
	jnz read_at_address
sucess_byte_read:
	jmp success_iret

ss_exception_iret:
	int int_ss ; #SS
	mov al, 'S'
error_iret:
	mov sp, bp
	mov [STACK_AX], ax

	pop ds
	popa

	popf
	stc
	pushf
	iret

	TIMES 0x01B8-($-$$) DB 0 ; Zero to MBR
mbr:	DD "X86O" ; Disk ID
	DW 0 ; Reserved
part1:	DD 0, 0, 0, 0
part2:	DD 0, 0, 0, 0
part3:	DD 0, 0, 0, 0
part4:	DD 0, 0, 0, 0

sig:	DB 0x55, 0xAA ; Bootsector / MBR Signature

; Interrupt 0x67 - aka. where math was invented
int_stat_fat_file:
	; Save registers
	pusha
	push ds
	mov bp, sp
	std ; VERY IMPORTANT

	; SS = DS
	push ss
	pop ds

	; Reserve stack for local stat output buffer
	push si ; Disk Stack Read overwrites SI
	sub sp, 0x10 - 0x02
	jc ss_exception_iret
load_mbr:
	xor ax, ax ; BX:AX = Sector 0
	xor bx, bx
	int INT_DISK_STACK_READ
	jc error_iret
load_mbr_next:
locate_fat16_part:
	mov al, dh
	shl al, 4
	add si, 0x1BE ; Partition 1
check_fat16_label:

	add si, -0x05 + 16 + 0x04 ; Advance to next Type ID field
	cmp si, part4 + 16 + 0x04 ; Partition 5's type field
	je error_iret ; Couldn't find one with FAT16 label

	; Check if partition has a FAT16 type
	lodsw ; Read partition ID
	xchg ax, bx
	lodsw
	; Offset +0x05
	cmp al, 0x06 ; FAT16
	je read_fat_bpb
	cmp al, 0x04 ; FAT16 < 32M
	je read_fat_bpb
	cmp al, 0x0e ; W95 FAT16 (LBA)
	jne check_fat16_label
read_fat_bpb:
;FAT BPB Structure
;OFF:SIZE
;0Bh:2h ; Bytes per sector
;0Dh:1h ; Sectors per cluster
;0Eh:2h ; Reserved sectors
;10h:1h ; File Allocation Tables
;11h:2h ; Root Directory Entries
;16h:2h ; Sectors per FAT

	; CX:BX - BPB LBA (partition start)
;	mov bx, WORD [cs: vars + 0x00] ; Low byte
;	mov cx, WORD [cs: vars + 0x02] ; High byte

	; Push LBA paramater
	push cx
	push bx

	; Read sector
	int INT_BASE + 0x00
	jc error_iret
	add sp, 4 - 2 ; -2 since we don't care about POP7 Next Cluster in next_entry

	; Write bytes per cluster to stat output buffer
	mov al, BYTE [si + 0x0D]	
	xor ax, ax
	mov WORD [bp - 0x10 + 0x0C], ax

	; Get start of FAT (Partition Start + Reserved Sectors)
	add bx, WORD [si + 0x0E] ; Reserved sectors
	adc cx, 0

	; Write FAT LBA
	mov WORD [bp - 0x10 + 0x00], bx
	mov WORD [bp - 0x10 + 0x02], cx

	; Get size of FATs in DX:AX
	mov al, BYTE [si + 0x10] ; #n of FATs
	xor ah, ah ; Can't use `cbw` due to sign extension
	mul WORD [si + 0x16] ; Sectors per FAT

	; Find first root directory sector in CX:BX
	add bx, ax
	adc cx, dx

	; Make it current sector in next_entry (POP6:POP5)
	push cx
	push bx

	; 65535 sectors remaining in cluster (POP4)
	push -1

	; Write bytes per sector to stat output buffer
	mov si, WORD [si + 0x0B] ; We won't be needing BPB any more
	mov WORD [bp - 0x10 + 0x0A], si

	; Get number of root directory entries in AX and set it to remaining (POP3)
	mov ax, WORD [si + 0x11] ; Root Directory Entries
	push ax
	
	; Get sectors used by root directoy in AX
	shl ax, 5 ; Multiply by 32, Limit of 4096 RDE.
	mov WORD [bp - 0x18 + 0x08], ax ; RDE remaining
	xor dx, dx
	div si ; Bytes per sector
	cmp dx, 1 ; Ceil resault - 0 sets CF
	sbb ax, -1 ; -1 + CF = -1, 0

	; Find Cluster 0 in DX:AX (Cluster 2 starts at first sector after root directory)
	dec ax ; Subtract two since Cluster 2
	dec ax
	cbw ; Sign extend into DX
	add ax, bx ; Root directory starts after FATs
	adc dx, cx

	; Write Cluster 0 LBA
	mov WORD [bp - 0x10 + 0x04], ax
	mov WORD [bp - 0x10 + 0x06], dx

	; Fill in remaining next entry fields to 0 (POP2 & POP1)
	push cs
	push cs

; next_entry
;  Sets SI to pointer to next RDE, or jumps to no_entry if there are
;  no more, else fall-throughs.
;
;  Stack is layed out as followed:
; POP1: Loaded directory entries remaining
; POP2: Last directory entry pointer
; POP3: Total directory entries remaining
; POP4: Sectors remaining in cluster
; POP6:POP5: Next sector LBA
; POP7: Current cluster
next_entry:
	pop bx ; BX = Remaining entries
	pop si ; SI = Entry pointer
	pop dx ; DX = Total remaining entries

	test dx, dx
	jz no_entry
	dec dx
	
	add si, 32
	test bx, bx
	jnz next_entry_cleanup
; TODO: We need to make sector / cluster reading a seperate routine later on.
next_sector_entry:
	pop bx ; BX = Remaining sectors
	sub bx, 1
	jnc next_sector_entry_valid ; Not zero, no wrap!
next_cluster_entry:
	; Skip 2
	pop bx
	pop bx

	; Find sector offset in FAT for cluster
	; We transform (FS = Fat Sector, CL = Cluster, SS = Sector Size)
	; 	FS = (CL * 2) / (SS)
	; into
	; 	FS = (CL) / (SS / 2)
	; to make sure CL stays in a word. This brings upon the restriction
	; though that SS is a multiple of two to avoid percission loss.
	pop ax ; AX = Current cluster
	xor dx, dx
	mov bx, WORD [bp - 0x10 + 0x0B] ; Bytes per sector
	shr bx, 1
	div bx ; AX = Sector, DX = Offset

	; Store offset into sector in BX from division modulo
	mov bx, dx

	; Get LBA of sector in DX:AX
	xor dx, dx
	add ax, WORD [bp - 0x10 + 0x00]
	adc dx, WORD [bp - 0x10 + 0x02]

	; Read sector containing cluster LL entry
	push bx
	push ax

	int INT_BASE + 0x00
	jc error_iret
	add sp, 4

	; Get cluster
	mov ax, [di + bx]
	push ax

	; Get LBA of first cluster sector in BX:AX
	mov bx, WORD [bp - 0x10 + 0x0C] ; BX = Sectors per cluster
	mul bx ; This is why x86 is awesome! It sets up DX for us.
	add ax, WORD [bp - 0x10 + 0x04]
	adc dx, WORD [bp - 0x10 + 0x06]

	push dx
	push ax

	; Decrement since we are going to read a sector and this is taken care
	; of in next_sector_entry.
	dec bx
next_sector_entry_valid:

next_entry_cleanup:
	push dx
	push ax
	push bx
check_entry:

no_entry:

; Interrupt 0x66
int_read_fat_file:
	mov ax, 0xEC00 | 'x'
	jmp error_iret

	TIMES 0x0400-($-$$) DB 0 ; Zero to end of sector
