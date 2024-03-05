; Entry
	; Callee Set: IF = 0
start:
	; Initialize Segments
	mov ax, 0x7c0 ; Stack Segment
	mov ds, ax
	mov ss, ax

	; Initialize stack pointer
	mov sp, stack

	; Initialize Serial Device
	call serial_init
	
	mov si, message
	call serial_out

halt:
	cli ; Disable interrupts
	hlt ; Wait for next interrupt
	jmp halt ; Non-maskable interrupts

message:
	db `\nHello World!\n\0`
