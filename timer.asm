;----------------------------------------------------------------------
;Assignment Two Part C
;By: Lee de Byl
;Modified to use direct Video Access
;----------------------------------------------------------------------
.MODEL TINY
.CODE
Main PROC FAR
   PROG_START:                          ;Used for calculating the length
        org 100h
        jmp INSTALL

        ;Define our parameters
        ;---------------------
        ;Screen Parameters
        TIMER_X         EQU     71      ;The column of the leftmost timer digit
        TIMER_Y         EQU     1       ;The row of the timer
        TIMER_OFFSET    EQU     (TIMER_Y - 1) * 160 + (TIMER_X - 1) * 2
        DIGIT_COLOUR    EQU     07      ;The colour code of the digit
        NUM_DIGITS      EQU     02      ;The number of digits to display. Note: Figures will be truncated from right to left.
        SEPERATOR       EQU     3Ah     ;The character used to sepearte MM:SS:HH

        ;Keys
        INSERT          EQU     52h
        HOME            EQU     47h

        ;Variables
        VRAM_OFFSET     DW      0       ; Initial offset       ;Stores the video RAM offset where the character should be displayed
        STATUS          DB      0       ;Stores the status of the timer. If 0, it is stopped. If 1, it is running.

        MINUTES         DB      0       ;The number of minutes elapesed
        SECONDS         DB      0       ;The number of seconds elapsed
        HUNDREDTHS      DB      0       ;The number of hundredths of a second
        MILLI           DW      0       ;The number of milliseconds elapsed

        NUMBER_BASE     DB     10       ;The number base used (10 for decimal)
        OLD_01CH        DD     ?        ;The location of the original 01Ch ISR
        OLD_09H         DD     ?        ;The location of the original 01CH ISR

        ;-----------
        ;INSTALL TSR
        ;-----------
    INSTALL:
        ;Initialise Segment Registers
        mov  AX, @CODE
        mov  DS, AX

        call INIT_SCREEN
        call SETUP_IVT                  ; Insert our ISR

        ;Return control back to DOS, but LEAVE RESIDENT
        mov  dx, (offset PROG_END - offset PROG_START)          ;Inform DOS of the program length
        mov  cl, 4
        shr  dx, cl
        add  DX, 17
        mov  AH, 31h                    ;Service 31(Exit and leave resident)
        mov  AL, 00                     ;Error code
        int  21h                        
Main ENDP

;---------------------------------------------------------------
;Procedure: SETUP_IVT
;Purpose: Sets up the interrupt handlers
;Out: none (yet)
;---------------------------------------------------------------
SETUP_IVT  PROC NEAR
        push AX                         ;Store changed interrupts on the stack
        push DS
        push ES 
        cli                             ;Disable Ints
        ;Get current 01CH ISR segment:offset
        mov  AH, 35h                    ;Select MS-DOS service 35h
        mov  AL, 1Ch                    ;IVT entry 1Ch
        int  21h                        ;Get the existing IVT entry for 01CH
        mov  WORD PTR OLD_01CH+2, ES    ;Store Segment 
        mov  WORD PTR OLD_01CH, BX      ;Store Offset

        ;Set new 01Ch ISR segment:offset
        mov  DX, offset HANDLER_01CH    ;Set the offset where the new IVT entry should point to
        mov  AX, 251Ch                  ;MS-DOS serivce 25h, IVT entry 01Ch
        int  21h                        ;Define the new vector

        ;Get current 09h ISR segment:offset
        mov  AH, 35h                    ;Select MS-DOS service 35h
        mov  AL, 09h                    ;IVT entry 09H
        int  21h                        ;Get the existing IVT entry for 09H
        mov  WORD PTR OLD_09H+2, ES    ;Store Segment 
        mov  WORD PTR OLD_09H, BX      ;Store Offset

        ;Set new 01Ch ISR segment:offset
        mov  DX, offset HANDLER_09H     ;Set the offset where the new IVT entry should point to
        mov  AX, 2509h                  ;MS-DOS serivce 25h, IVT entry 01Ch
        int  21h                        ;Define the new vector

        pop  ES                         ;Restore interrupts
        pop  DS
        pop  AX
        sti                             ;Re-enable interrupts
        ret
SETUP_IVT ENDP

;---------------------------------------------------------------
;Procedure: HANDLER_01CH
;Purpose: Our brand new clock tick procedure
;---------------------------------------------------------------
HANDLER_01CH    PROC NEAR
        push AX                         ;Backup any registers modified
        push DS
        ;Initialise Segment Registers
        mov  AX, @CODE
        mov  DS, AX

        cmp  STATUS, 01                 ;Is the timer supposed to be running?
        jne  UPDATE_DISPLAY             ;If not, don't increment it.
        ;Add the time
  NEXT_HUNDREDTH:
        add  HUNDREDTHS, 5
        cmp  HUNDREDTHS, 100
        jge  INC_SECONDS
        jmp  UPDATE_DISPLAY
  INC_SECONDS:
        mov  HUNDREDTHS, 0
        add  SECONDS, 1
        cmp  SECONDS, 60
        jge  INC_MINUTES
        jmp  UPDATE_DISPLAY
  INC_MINUTES:
        mov  SECONDS, 0
        add  MINUTES, 1
        cmp  MINUTES, 100
        jge  OVERFLOW
  UPDATE_DISPLAY:
        call DISPLAY_TIME                   ;Display the time at this position
        jmp  INC_DONE
  OVERFLOW:
        mov  STATUS, 00                     ;Stop counting people
  INC_DONE:
        pop  DS                             ;Restore backed up registers
        pop  AX
        jmp  CS:OLD_01CH                    ;Run the old handler
HANDLER_01CH ENDP

;---------------------------------------------------------------
;Procedure: HANDLER_09H
;Purpose: The new INT 09 Handler
;In: None
;Out: None
;---------------------------------------------------------------
HANDLER_09H PROC NEAR
        push AX
        push DS

        ;Initialise Segment Registers
        mov  AX, @CODE
        mov  DS, AX

        ;Note: May not be compatibe with 101/102 keyboards. :(
        mov  AH,02h                      ;Get the keyboard status byte
        int  16h                         ;Using BIOS INT 16
        test AL,00001000B                ;Check for ALT
        jz   NO_ACTION
        in   AL,60H                      ;Get the scan code 
        cmp  AL, INSERT                  ;Has the insert key been pressed
        jne  NOT_INSERT
        cmp  STATUS, 01                  ;It has, so change the status of the timer
        je   STOP_TIMER
        mov  STATUS, 01
        jmp  NO_ACTION
   STOP_TIMER:
        mov  STATUS, 00
        jmp  NO_ACTION                   ; Get another key
   NOT_INSERT:
        cmp  AL, HOME                    ;Was the home key pressed?
        jne  NO_ACTION                   ;If not, check to see what other keys it could be
        mov  STATUS, 00                  ;It was, so stop the timer and reset it
        mov  MINUTES, 00
        mov  SECONDS, 00
        mov  HUNDREDTHS, 00
  NO_ACTION:
        pop  DS
        pop  AX
        jmp  CS:OLD_09H                   ;Run old ISR
HANDLER_09H ENDP

;---------------------------------------------------------------
;Procedure: INIT_SCREEN
;Purpose: Sets the screen mode, and hides the cursor
;In: None
;Out: None
;---------------------------------------------------------------
INIT_SCREEN PROC NEAR
        mov  AH, 0                      ;Select BIOS Function 0 - Set Display Mode
        mov  AL, 3                      ;Set it to 03 
        int  10h                        ;Execute BIOS Routine

        ret                             ;Return to Calling Procedure
INIT_SCREEN ENDP


;---------------------------------------------------------------
;Procedure: DISPLAY_CHAR
;Purpose: Displays a character at the current cursor pos
;In: AL - ASCII code of character
;    DIGIT_COLOUR - Colour code
;Out: None
;---------------------------------------------------------------
DISPLAY_CHAR PROC NEAR
        push  DI
        push  ES
        push  AX
        mov   AX, 0B800h                     ; Video RAM segment
        mov   ES, AX
        pop   AX
        mov   AH, DIGIT_COLOUR               ; Set the colour
        mov   DI, VRAM_Offset                ; Video RAM offset
        stosw                                ; Store word in AX to a memory location ES:[DI]
        pop  ES
        pop  DI
        ret
DISPLAY_CHAR ENDP

;-----------------------------------------------------------------------
;Procedure: DISPLAY_SEPERATOR
;Purpose: Inserts a seperator (colon) and prepares for the next 2 digits to be displayed
;IN: DIGIT_COLOUR - The colour of the digits to be written
;    CURSOR_X - The X position where the leftmost digit should be displayed
;    CURSOR_Y - The Y position where the number should be displayed
;    NUM_DIGITS - *Constant* The number of digits that should be displayed. Will be padded with 0's
;-----------------------------------------------------------------------
DISPLAY_SEPERATOR PROC NEAR
        push BX                                 ;Back up registers
        push AX
        add  VRAM_OFFSET, (NUM_DIGITS+1)*2      ;Place the cursor where the seperator should be
        mov  AL, SEPERATOR                      ;Set the character
        call DISPLAY_CHAR                       ;Actually display it
        add  VRAM_OFFSET, 2                     ;Move to where the next digit group should start
        pop  AX                                 ;Restore backed up registers
        pop  BX
        ret
DISPLAY_SEPERATOR ENDP


;-----------------------------------------------------------------------
;Procedure: DISPLAY_DECIMAL
;Purpose: Displays a number byte as 2 ASCII Characters on screen
;IN: AL - The number to be displayed
;    DIGIT_COLOUR - The colour of the digits to be written
;    CURSOR_X - The X position where the leftmost digit should be displayed
;    CURSOR_Y - The Y position where the number should be displayed
;    NUM_DIGITS - *Constant* The number of digits that should be displayed. Will be padded with 0's
;-----------------------------------------------------------------------
DISPLAY_DECIMAL PROC NEAR
        add  VRAM_OFFSET, 2             ;Double Check
        push CX
        mov  CX, NUM_DIGITS
  NEXT_DIGIT:
        xor  AH, AH
        div  NUMBER_BASE                ;Get one digit (in the form of the remainder) in AH
        push AX                         ;Put the result of the division onto the stack
        add  AH, 30h                    ;Add 30 to the remainder, to make it ASCII
        xchg AL, AH                     ;Put the remainder into AL, ready to be displayed
        call DISPLAY_CHAR               ;Display the character in AL
        sub  VRAM_OFFSET, 02            ;Move the cursor left one digit
        pop  AX                         ;Restore the value of AX
        loop NEXT_DIGIT                 ;Display the next digit
        pop CX                          ;Restore backed up registers
        ret
DISPLAY_DECIMAL ENDP
                                  

;-----------------------------------------------------------------------
;Procedure: DISPLAY_TIME
;Purpose: Displays the time stored in the appropriate variables
;IN: MINUTES
;    SECONDS
;    HUNDREDTHS   - The amount elapsed for each of those quantities
;    TIMER_OFFSET       - The location where the timer should be placed
;-----------------------------------------------------------------------
DISPLAY_TIME PROC NEAR
        push AX
        mov  VRAM_OFFSET, TIMER_OFFSET

        ;Display the number of Minutes
        mov  AL, MINUTES
        call DISPLAY_DECIMAL

        ;Display the first seperator
        call DISPLAY_SEPERATOR

        ;Display the number of seconds
        mov  AL, SECONDS
        call DISPLAY_DECIMAL

        call DISPLAY_SEPERATOR

        ;Display the number of hundredths
        mov  AL, HUNDREDTHS
        call DISPLAY_DECIMAL

        pop  AX
        ret
    PROG_END:
DISPLAY_TIME ENDP

END Main
