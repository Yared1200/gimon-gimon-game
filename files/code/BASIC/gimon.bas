; ==============================================================================
; 1. iNES HEADER
; ==============================================================================
.segment "HEADER"
    .byte $4E, $45, $53, $1A ; "NES" magic string
    .byte $02                ; 32KB PRG-ROM code
    .byte $01                ; 8KB CHR-ROM graphics
    .byte $00                ; Mapper 0 (NROM)
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00

; ==============================================================================
; 2. VARIABLES (Zero Page Memory Allocations)
; ==============================================================================
.segment "ZEROPAGE"
Player_X:        .res 1     ; Horizontal pixel position
Player_Y:        .res 1     ; Vertical pixel position
Player_Y_Vel:    .res 1     ; Vertical velocity (signed)
Buttons_Held:    .res 1     ; Packed bits for controller input
Is_Jumping:      .res 1     ; 0 = on ground, 1 = in air

; Constants
GRAVITY      = $01          ; Downward pull per frame
JUMP_IMPULSE = $FC          ; Negative velocity (-4) for moving UP
FLOOR_Y      = $D0          ; The bottom bounding line of our screen

; ==============================================================================
; 3. CODE SEGMENT
; ==============================================================================
.segment "CODE"

Reset_Handler:
    SEI             ; Disable interrupts
    CLD             ; Clear decimal mode
    LDX #$40
    STX $4017       ; Disable APU frame IRQ
    LDX #$FF
    TXS             ; Init stack pointer

    LDA #$00
    STA $2000       ; Disable NMI
    STA $2001       ; Disable rendering

VBlank_Wait_1:
    BIT $2002
    BPL VBlank_Wait_1

Clear_RAM:
    STA $0000, x
    STA $0100, x
    STA $0300, x
    STA $0400, x
    STA $0500, x
    STA $0600, x
    STA $0700, x
    LDA #$FE        ; Hide sprites offscreen
    STA $0200, x
    LDA #$00
    DEX
    BNE Clear_RAM

VBlank_Wait_2:
    BIT $2002
    BPL VBlank_Wait_2

    ; Initialize Platformer Variables
    LDA #$80
    STA Player_X    ; Start in middle of screen horizontally
    LDA #$A0
    STA Player_Y    ; Start mid-air vertically
    LDA #$00
    STA Player_Y_Vel
    STA Is_Jumping

    ; Turn on the NES Display (Sprites visible, Background visible)
    LDA #%10001000  ; Enable NMI interrupts, Sprites use first CHR bank
    STA $2000
    LDA #%00011110  ; Enable Sprites and Background rendering
    STA $2001

Main_Game_Loop:
    ; The CPU sits here waiting for the TV frame to update via NMI
    JMP Main_Game_Loop


; ==============================================================================
; 4. GAME INTERRUPT LOGIC (Triggers 60 times a second on NTSC systems)
; ==============================================================================
NMI_Handler:
    PHA             ; Save registers to stack to avoid glitches
    TXA
    PHA
    TYA
    PHA

    ; 1. Refresh Sprites via Sprite DMA ($0200 RAM -> PPU OAM)
    LDA #$00
    STA $2003       ; Set low byte of OAM address to 0
    LDA #$02
    STA $4014       ; Write high byte ($0200), triggering ultra-fast transfer

    ; 2. Read Controller Port 1
    LDA #$01
    STA $4016       ; Strobe controller latch high
    LDA #$00
    STA $4016       ; Strobe controller latch low (lock state)
    
    LDX #$08        ; Read all 8 buttons sequentially
Read_Controller_Loop:
    LDA $4016       ; Read current button state (Bit 0)
    LSR A           ; Shift button bit into Carry
    ROL Buttons_Held; Rotate Carry into our variable
    DEX
    BNE Read_Controller_Loop

    ; Buttons_Held is now packed: A, B, Select, Start, Up, Down, Left, Right

    ; 3. Handle Left / Right Physics
Check_Left:
    LDA Buttons_Held
    AND #%00000010  ; Check 'Left' D-pad bit
    BEQ Check_Right
    DEC Player_X    ; Move left 1 pixel

Check_Right:
    LDA Buttons_Held
    AND #%00000001  ; Check 'Right' D-pad bit
    BEQ Check_Jump
    INC Player_X    ; Move right 1 pixel

    ; 4. Handle Jump Input
Check_Jump:
    LDA Is_Jumping
    BNE Apply_Gravity ; Skip jump input if we are already in mid-air
    LDA Buttons_Held
    AND #%10000000  ; Check 'A' button bit
    BEQ Apply_Gravity
    LDA #JUMP_IMPULSE
    STA Player_Y_Vel; Set moving UP force
    LDA #$01
    STA Is_Jumping  ; Lock out jumping until floor hit

    ; 5. Apply Vertical Engine & Gravity
Apply_Gravity:
    LDA Player_Y_Vel
    CLC
    ADC #GRAVITY    ; Apply gravity constant
    STA Player_Y_Vel

    CLC
    ADC Player_Y    ; Add current velocity to player Y position
    STA Player_Y

    ; 6. Collision Detection (Simple Floor Check)
    LDA Player_Y
    CMP #FLOOR_Y    ; Are we past or hitting the floor coordinate?
    BCC Update_OAM  ; If less than FLOOR_Y, we are still airborne

    ; Landed on the floor! Reset states
    LDA #FLOOR_Y
    STA Player_Y    ; Force snap player directly onto floor line
    LDA #$00
    STA Player_Y_Vel; Stop falling velocity
    STA Is_Jumping  ; Allow jumping again

    ; 7. Write New Player Coordinates to Sprite RAM ($0200)
Update_OAM:
    LDA Player_Y
    STA $0200       ; Sprite 0: Y Position
    LDA #$01
    STA $0201       ; Sprite 0: Tile Index #1 from graphics table
    LDA #$00
    STA $0202       ; Sprite 0: Attributes (Color palette 0)
    LDA Player_X
    STA $0203       ; Sprite 0: X Position

    ; Restore registers and return to main game loop
    PLA
    TAY
    PLA
    TAX
    PLA
    RTI

IRQ_Handler:
    RTI

; ==============================================================================
; 5. INTERRUPT VECTORS
; ==============================================================================
.segment "VECTORS"
    .word NMI_Handler
    .word Reset_Handler
    .word IRQ_Handler
    MEMORY {
    HEADER: start = $00, size = $10, file = %O, fill = yes;
    PRG:    start = $8000, size = $8000, file = %O, fill = yes;
    CHR:    start = $0000, size = $2000, file = %O, fill = yes;
}

SEGMENTS {
    HEADER:  load = HEADER, type = ro;
    CODE:    load = PRG,    type = ro, start = $8000;
    VECTORS: load = PRG,    type = ro, start = $FFFA;
    CHARS:   load = CHR,    type = ro;
}

.segment "CHARS"
.incbin "sprites.chr"

