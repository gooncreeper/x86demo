; Source document:
; https://www.sci.muni.cz/docs/pc/serport.txt

%define COM1 0x3F8
%define COM2 0x2F8
%define COM3 0x3E8
%define COM4 0x2E8

%define OUT_ORG COM1 ; Origin for serial port

%define OUT_RBR (OUT_ORG + 0) ; Receive Buffer Register
%define OUT_THR (OUT_ORG + 0) ; Transmitter Holding Register
%define OUT_IER (OUT_ORG + 1) ; Interrupt Enable Register
%define OUT_DL  (OUT_ORG + 0) ; Divisor Latch (LSB, +1 MSB)
%define OUT_IIR (OUT_ORG + 2) ; Interupt Identification Register
%define OUT_FCR (OUT_ORG + 2) ; FIFO Control Register
%define OUT_LCR (OUT_ORG + 3) ; Line Control Register
%define OUT_MCR (OUT_ORG + 4) ; Modem Control Register
%define OUT_LSR (OUT_ORG + 5) ; Line Status Register
%define OUT_MSR (OUT_ORG + 6) ; Modem Status Regsiter
%define OUT_SCR (OUT_ORG + 7) ; Scratch Register (unused)

; Waits until all the passed bits are set when reading port
	; Caller preserved: AL
	; DX: Port
	; AH: Bits
port_wait:
	in al, dx ; Read Data
	not al ; Reverse to check if bits are 0
	test al, ah
	jnz port_wait
	ret
	
; Initializes Serial UART
	; Caller preserved: AX, DX
serial_init:
		; Wait until no `transmission`
	mov dx, OUT_LSR ; Line Status Register
	mov ah, 0x40
	call port_wait

		; Disable Interrupts (we will just poll the port)
	mov dx, OUT_IER ; Interrupt Enable Register
	mov al, 0x00    ; All interrupts disabled
	out dx, al

		; Baud Rate
	mov dx, OUT_LCR ; Line Control Register
	mov al, 0x80    ; Set DLAB to modify divisor
	out dx, al
	
	mov dx, OUT_DL ; Divisor Latch
	mov ax, 0x0001 ; Baud Rate divisor of 1 (so fastest)
	out dx, ax

		; Set 8 bits, 1 stop bit, no parity & Disable Divisor Latch
	mov dx, OUT_LCR ; Line Control Register
	mov al, 0x03    ; 8 bits, 1 stop bit, no parity
	out dx, al

		; Clear the FIFO buffers & disable
	mov dx, OUT_FCR ; FIFO Control Register
	mov al, 0b11000110
	out dx, al

		; Clear Data Ready, Ready to Send, "Enable Port", and Disable ALL Interupts
	mov dx, OUT_MCR ; Modem Control Register
	mov al, 0b00001111
	out dx, al

		; Clear serial input ports
	mov dx, OUT_RBR
	in al, dx

	mov dx, OUT_LSR
	in al, dx 

	ret

; Outputs a string to Serial UART
	; Caller Preserved: AL, BX, DX, SI
	; SI: String start pointer

serial_out:
		; Get character and return if null
	mov bl, [si]
	test bl, bl ; Check null
	jz string_null
	inc si ; Next character

		; Wait until we can write to THR
	mov dx, OUT_LSR ; Line Status Register
	mov ah, 0x20
	call port_wait

		; Output next character
	mov dx, OUT_THR
	mov al, bl
	out dx, al
	
	jmp serial_out ; Next iteration
string_null:
	ret
