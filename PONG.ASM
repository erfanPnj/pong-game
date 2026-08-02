; ==============================================================================
; PONG & BREAKOUT GAME IN 8086 ASSEMBLY (VGA MODE 13h)
; Includes: Circular Ball, Randomized Blocks (Resilience 1-5), Zero-Flicker Engine
; ==============================================================================

.MODEL SMALL
.STACK 200H

.DATA
    ; --- Ball Properties ---
    BALL_X      DW 160       ; Ball X Center
    BALL_Y      DW 120       ; Ball Y Center
    BALL_R      DW 5         ; Ball Radius (Circular Ball)
    BALL_DX     DW 1         ; X Velocity
    BALL_DY     DW -1        ; Y Velocity
    BALL_COLOR  DB 14        ; Yellow Color

    ; --- Paddle Properties ---
    PADDLE_X    DW 135       ; Paddle Left X Position
    PADDLE_Y    DW 185       ; Paddle Y Position
    PADDLE_W    DW 50        ; Paddle Width
    PADDLE_H    DW 5         ; Paddle Height
    PADDLE_COL  DB 10        ; Light Green Color
    PADDLE_STEP DW 12        ; Movement Speed

    ; --- Game State Variables ---
    SCORE       DW 0         ; Player Score (Target: 30)
    GAME_OVER   DB 0         ; 0 = Running, 1 = Lost
    WIN_FLAG    DB 0         ; 0 = Running, 1 = Won

    ; --- Blocks Matrix (4 Rows x 8 Columns = 32 Blocks) ---
    ; Values: 0 = Destroyed, 1-5 = Remaining Resilience Level
    BLOCKS      DB 32 DUP(0)
    
    ; Block Layout Constants
    BLOCK_W     DW 34        ; Block Width
    BLOCK_H     DW 8         ; Block Height
    BLOCK_GAP   DW 3         ; Gap between blocks
    START_X     DW 14        ; Left margin offset
    START_Y     DW 20        ; Top margin offset

.CODE
MAIN PROC FAR
    MOV AX, @DATA
    MOV DS, AX

    ; 1. Switch to VGA Video Mode 13h (320x200, 256 Colors)
    MOV AX, 0013H
    INT 10H

    ; Set ES register to VGA Memory Base Address (A000h) safely
    PUSH 0A000H
    POP ES

    ; 2. Initialize Random Blocks (1 to 5 Resilience)
    CALL INIT_BLOCKS
    
    ; 3. Initial Static Scene Rendering (Drawn ONCE to prevent CPU bottleneck)
    CALL CLEAR_SCREEN
    CALL DRAW_BLOCKS
    CALL DRAW_PADDLE
    CALL DRAW_CIRCLE

GAME_LOOP:
    ; Frame timing delay
    CALL DELAY

    ; Only dynamic objects (Paddle & Ball) are updated when needed
    CALL CHECK_KEYBOARD
    CALL UPDATE_PHYSICS

    ; Check Game Termination Conditions
    CMP GAME_OVER, 1
    JE EXIT_GAME
    CMP SCORE, 30
    JGE WIN_GAME

    JMP GAME_LOOP

EXIT_GAME:
WIN_GAME:
    ; Return to Standard Text Mode 03h
    MOV AX, 0003H
    INT 10H

    ; Terminate Program
    MOV AH, 4CH
    INT 21H
MAIN ENDP

; ==============================================================================
; PROCEDURE: CLEAR_SCREEN
; Clears all 64,000 bytes of video memory once at startup
; ==============================================================================
CLEAR_SCREEN PROC NEAR
    PUSH AX
    PUSH CX
    PUSH DI

    XOR DI, DI           ; Start at offset 0
    XOR AX, AX           ; Color 0 (Black)
    MOV CX, 32000        ; 32000 words = 64000 bytes
    CLD
    REP STOSW            ; Clear memory rapidly using word stores

    POP DI
    POP CX
    POP AX
    RET
CLEAR_SCREEN ENDP

; ==============================================================================
; PROCEDURE: DELAY (Nested Loop for Accurate Arcade Speed)
; ==============================================================================
DELAY PROC NEAR
    PUSH BX
    PUSH CX

    MOV BX, 1            ; <-- تنظیم سرعت بازی (عدد بزرگ‌تر = بازی کندتر)
OUTER_DELAY:
    MOV CX, 0E000H       ; تعداد تکرار حلقه داخلی
INNER_DELAY:
    NOP
    LOOP INNER_DELAY
    
    DEC BX
    JNZ OUTER_DELAY

    POP CX
    POP BX
    RET
DELAY ENDP

; ==============================================================================
; PROCEDURE: DRAW_PIXEL
; Draws a single pixel at ES:[Y*320 + X]
; Inputs: CX = X, DX = Y, AL = Color Code
; ==============================================================================
DRAW_PIXEL PROC NEAR
    PUSH BX
    PUSH DX
    PUSH DI

    ; DI = Y * 320 + X  ->  Y * (256 + 64) + X
    MOV DI, DX
    SHL DI, 8          ; DI = Y * 256
    MOV BX, DX
    SHL BX, 6          ; BX = Y * 64
    ADD DI, BX         ; DI = Y * 320
    ADD DI, CX         ; DI = Y * 320 + X

    STOSB              ; Write AL (Color) directly to ES:[DI]

    POP DI
    POP DX
    POP BX
    RET
DRAW_PIXEL ENDP

; ==============================================================================
; PROCEDURE: DRAW_CIRCLE
; Draws a circle based on quadratic condition: (X-X0)^2 + (Y-Y0)^2 <= R^2
; ==============================================================================
DRAW_CIRCLE PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

    MOV SI, BALL_Y
    SUB SI, BALL_R       ; SI = Y_start
    MOV DI, BALL_Y
    ADD DI, BALL_R       ; DI = Y_end

ROW_LOOP:
    MOV CX, BALL_X
    SUB CX, BALL_R       ; CX = X_start

COL_LOOP:
    ; Calculate dx^2 = (CX - BALL_X)^2
    MOV AX, CX
    SUB AX, BALL_X
    IMUL AX
    MOV BX, AX

    ; Calculate dy^2 = (SI - BALL_Y)^2
    MOV AX, SI
    SUB AX, BALL_Y
    IMUL AX
    ADD BX, AX

    ; Calculate R^2
    MOV AX, BALL_R
    IMUL AX

    CMP BX, AX
    JG SKIP_PIXEL

    ; Draw Pixel at (X=CX, Y=SI)
    PUSH CX
    PUSH DX
    MOV DX, SI
    MOV AL, BALL_COLOR
    CALL DRAW_PIXEL
    POP DX
    POP CX

SKIP_PIXEL:
    INC CX
    MOV AX, BALL_X
    ADD AX, BALL_R
    CMP CX, AX
    JLE COL_LOOP

    INC SI
    CMP SI, DI
    JLE ROW_LOOP

    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
DRAW_CIRCLE ENDP

; ==============================================================================
; PROCEDURE: ERASE_CIRCLE
; Erases the ball by redrawing it in black (Color 0)
; ==============================================================================
ERASE_CIRCLE PROC NEAR
    PUSH AX
    MOV AL, BALL_COLOR
    PUSH AX
    MOV BALL_COLOR, 0    ; Set ball color to black temporarily
    CALL DRAW_CIRCLE
    POP AX
    MOV BALL_COLOR, AL   ; Restore yellow color
    POP AX
    RET
ERASE_CIRCLE ENDP

; ==============================================================================
; PROCEDURE: DRAW_PADDLE
; Renders the solid rectangle paddle at bottom of screen
; ==============================================================================
DRAW_PADDLE PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX

    MOV DX, PADDLE_Y
    MOV BX, PADDLE_Y
    ADD BX, PADDLE_H

PADDLE_Y_LOOP:
    MOV CX, PADDLE_X
    PUSH BX
    MOV BX, PADDLE_X
    ADD BX, PADDLE_W

PADDLE_X_LOOP:
    MOV AL, PADDLE_COL
    CALL DRAW_PIXEL
    INC CX
    CMP CX, BX
    JL PADDLE_X_LOOP

    POP BX
    INC DX
    CMP DX, BX
    JL PADDLE_Y_LOOP

    POP DX
    POP CX
    POP BX
    POP AX
    RET
DRAW_PADDLE ENDP

; ==============================================================================
; PROCEDURE: ERASE_PADDLE
; Erases the paddle by redrawing it in black
; ==============================================================================
ERASE_PADDLE PROC NEAR
    PUSH AX
    MOV AL, PADDLE_COL
    PUSH AX
    MOV PADDLE_COL, 0    ; Set color to black
    CALL DRAW_PADDLE
    POP AX
    MOV PADDLE_COL, AL   ; Restore green color
    POP AX
    RET
ERASE_PADDLE ENDP

; ==============================================================================
; PROCEDURE: INIT_BLOCKS
; Initializes 32 blocks with pseudo-random resilience values (1 to 5)
; ==============================================================================
INIT_BLOCKS PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH DI

    MOV CX, 32           ; Total number of blocks
    XOR DI, DI

INIT_LOOP:
    PUSH CX              ; Save loop counter (INT 1Ah clobbers CX!)
    
    ; Read System Timer Counter (INT 1Ah, AH = 00h)
    MOV AH, 00H
    INT 1AH              ; Returns clock ticks in CX:DX
    
    MOV AX, DX
    XOR DX, DX
    MOV BX, 5
    DIV BX               ; DX = remainder (0 to 4)
    INC DX               ; DX = value between 1 and 5

    MOV BLOCKS[DI], DL   ; Assign resilience level
    
    POP CX               ; Restore loop counter safely
    INC DI
    LOOP INIT_LOOP

    POP DI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
INIT_BLOCKS ENDP

; ==============================================================================
; PROCEDURE: GET_BLOCK_COORDS
; Calculates screen X, Y coordinates for block at Col = BX, Row = SI
; Outputs: CX = Left X, DX = Top Y
; ==============================================================================
GET_BLOCK_COORDS PROC NEAR
    PUSH AX

    ; Calculate X: CX = (BX * (BLOCK_W + BLOCK_GAP)) + START_X
    MOV AX, BX
    MOV CX, BLOCK_W
    ADD CX, BLOCK_GAP
    IMUL CX
    ADD AX, START_X
    MOV CX, AX           ; CX = Top-Left X

    ; Calculate Y: DX = (SI * (BLOCK_H + BLOCK_GAP)) + START_Y
    MOV AX, SI
    PUSH CX
    MOV CX, BLOCK_H
    ADD CX, BLOCK_GAP
    IMUL CX
    ADD AX, START_Y
    MOV DX, AX           ; DX = Top-Left Y
    POP CX

    POP AX
    RET
GET_BLOCK_COORDS ENDP

; ==============================================================================
; PROCEDURE: DRAW_BLOCKS
; Renders blocks with colors based on their current resilience level
; ==============================================================================
DRAW_BLOCKS PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

    XOR DI, DI           ; Block index (0 to 31)
    MOV SI, 0            ; Row counter (0 to 3)

ROW_BLOCK_LOOP:
    MOV BX, 0            ; Column counter (0 to 7)

COL_BLOCK_LOOP:
    MOV AL, BLOCKS[DI]
    CMP AL, 0
    JE NEXT_BLOCK        ; Skip destroyed blocks

    ; Map resilience level (1-5) to distinctive VGA colors
    ADD AL, 32           ; Color palette shift for visibility
    CALL GET_BLOCK_COORDS ; Returns CX = X, DX = Y
    CALL DRAW_SINGLE_BLOCK

NEXT_BLOCK:
    INC DI
    INC BX
    CMP BX, 8
    JL COL_BLOCK_LOOP

    INC SI
    CMP SI, 4
    JL ROW_BLOCK_LOOP

    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
DRAW_BLOCKS ENDP

; ==============================================================================
; PROCEDURE: DRAW_SINGLE_BLOCK
; Helper function to draw a single block rectangle
; Inputs: CX = X, DX = Y, AL = Color
; ==============================================================================
DRAW_SINGLE_BLOCK PROC NEAR
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

    MOV SI, DX
    ADD SI, BLOCK_H      ; SI = Y_end
    MOV DI, CX
    ADD DI, BLOCK_W      ; DI = X_end

BLOCK_Y_LOOP:
    PUSH CX              ; Save X_start

BLOCK_X_LOOP:
    CALL DRAW_PIXEL
    INC CX
    CMP CX, DI
    JL BLOCK_X_LOOP

    POP CX               ; Restore X_start
    INC DX
    CMP DX, SI
    JL BLOCK_Y_LOOP

    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    RET
DRAW_SINGLE_BLOCK ENDP

; ==============================================================================
; PROCEDURE: CHECK_KEYBOARD
; Handles local keyboard input (A/D or Left/Right Arrow keys)
; ==============================================================================
CHECK_KEYBOARD PROC NEAR
    PUSH AX
    PUSH DX

    ; Check if key is available in buffer
    MOV AH, 01H
    INT 16H
    JZ KEY_DONE

    ; Consume key from buffer
    MOV AH, 00H
    INT 16H

    ; 'A' or 'a' key -> Move Left
    CMP AL, 'a'
    JE MOVE_LEFT
    CMP AL, 'A'
    JE MOVE_LEFT
    ; Extended Key Left Arrow (AH = 4BK)
    CMP AH, 4BH
    JE MOVE_LEFT

    ; 'D' or 'd' key -> Move Right
    CMP AL, 'd'
    JE MOVE_RIGHT
    CMP AL, 'D'
    JE MOVE_RIGHT
    ; Extended Key Right Arrow (AH = 4DK)
    CMP AH, 4DH
    JE MOVE_RIGHT
    JMP KEY_DONE

MOVE_LEFT:
    CALL ERASE_PADDLE    ; Erase paddle before moving left
    MOV AX, PADDLE_STEP
    SUB PADDLE_X, AX
    CMP PADDLE_X, 2
    JGE DRAW_NEW_LEFT
    MOV PADDLE_X, 2
DRAW_NEW_LEFT:
    CALL DRAW_PADDLE     ; Immediately redraw paddle at new position
    JMP KEY_DONE

MOVE_RIGHT:
    CALL ERASE_PADDLE    ; Erase paddle before moving right
    MOV AX, PADDLE_STEP
    ADD PADDLE_X, AX
    MOV AX, PADDLE_X
    ADD AX, PADDLE_W
    CMP AX, 318
    JLE DRAW_NEW_RIGHT
    MOV AX, 318
    SUB AX, PADDLE_W
    MOV PADDLE_X, AX
DRAW_NEW_RIGHT:
    CALL DRAW_PADDLE     ; Immediately redraw paddle at new position

KEY_DONE:
    POP DX
    POP AX
    RET
CHECK_KEYBOARD ENDP

; ==============================================================================
; PROCEDURE: UPDATE_PHYSICS
; Updates coordinates, checks collisions, and redraws ball dynamically
; ==============================================================================
UPDATE_PHYSICS PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

    ; 0. Erase old ball position
    CALL ERASE_CIRCLE

    ; 1. Update Ball Position
    MOV AX, BALL_DX
    ADD BALL_X, AX
    MOV AX, BALL_DY
    ADD BALL_Y, AX

    ; 2. Wall Collisions (Left / Right)
    MOV AX, BALL_R
    CMP BALL_X, AX
    JLE REV_DX
    MOV AX, 320
    SUB AX, BALL_R
    CMP BALL_X, AX
    JGE REV_DX
    JMP CHECK_TOP

REV_DX:
    NEG BALL_DX
    JMP CHECK_TOP

    ; 3. Top Wall Collision
CHECK_TOP:
    MOV AX, BALL_R
    CMP BALL_Y, AX
    JLE REV_DY_TOP
    JMP CHECK_PADDLE_COLLISION

REV_DY_TOP:
    NEG BALL_DY
    JMP CHECK_BLOCKS_COLLISION

    ; 4. Paddle Collision (Bottom)
CHECK_PADDLE_COLLISION:
    MOV AX, PADDLE_Y
    SUB AX, BALL_R
    CMP BALL_Y, AX
    JL CHECK_BLOCKS_COLLISION

    ; Check if Ball X is within [PADDLE_X, PADDLE_X + PADDLE_W]
    MOV AX, PADDLE_X
    CMP BALL_X, AX
    JL CHECK_GAME_OVER
    ADD AX, PADDLE_W
    CMP BALL_X, AX
    JG CHECK_GAME_OVER

    ; Bounce upwards from paddle
    NEG BALL_DY
    JMP CHECK_BLOCKS_COLLISION

CHECK_GAME_OVER:
    MOV AX, 198
    CMP BALL_Y, AX
    JL CHECK_BLOCKS_COLLISION
    MOV GAME_OVER, 1         ; Trigger Game Over if missed paddle
    JMP DONE_PHYSICS

    ; 5. Block Collisions
CHECK_BLOCKS_COLLISION:
    MOV AX, START_Y
    CMP BALL_Y, AX
    JL DONE_PHYSICS
    MOV AX, START_Y
    ADD AX, 45               ; Total height of 4 block rows
    CMP BALL_Y, AX
    JG DONE_PHYSICS

    XOR DI, DI               ; Iterate all 32 blocks
    MOV SI, 0                ; Row index (0 to 3)

BROW_LOOP:
    MOV BX, 0                ; Column index (0 to 7)

BCOL_LOOP:
    CMP BLOCKS[DI], 0
    JE NEXT_BCHECK

    CALL GET_BLOCK_COORDS    ; Returns CX = Left X, DX = Top Y

    ; Check X bounds: CX <= BALL_X <= CX + BLOCK_W
    CMP BALL_X, CX
    JL NEXT_BCHECK
    ADD CX, BLOCK_W
    CMP BALL_X, CX
    JG NEXT_BCHECK

    ; Check Y bounds: DX <= BALL_Y <= DX + BLOCK_H
    CMP BALL_Y, DX
    JL NEXT_BCHECK
    ADD DX, BLOCK_H
    CMP BALL_Y, DX
    JG NEXT_BCHECK

    ; Collision Confirmed!
    DEC BLOCKS[DI]           ; Reduce resilience level by 1
    
    ; Update block visually based on remaining resilience
    CMP BLOCKS[DI], 0
    JE ERASE_DESTROYED_BLOCK
    
    ; If still alive, redraw block with new resilience color
    PUSH AX
    MOV AL, BLOCKS[DI]
    ADD AL, 32
    CALL DRAW_SINGLE_BLOCK
    POP AX
    JMP COLLISION_APPLIED

ERASE_DESTROYED_BLOCK:
    ; If destroyed (resilience = 0), erase it immediately with black color
    PUSH AX
    MOV AL, 0
    CALL DRAW_SINGLE_BLOCK
    POP AX

COLLISION_APPLIED:
    NEG BALL_DY              ; Reflect vertical trajectory
    INC SCORE                ; Increment score towards win condition 30
    JMP DONE_PHYSICS

NEXT_BCHECK:
    INC DI
    INC BX
    CMP BX, 8
    JL BCOL_LOOP             ; Safe short jump distance

    INC SI
    CMP SI, 4
    JL BROW_LOOP             ; Safe short jump distance

DONE_PHYSICS:
    ; 6. Immediately redraw ball at new position with ZERO delay after erase!
    CALL DRAW_CIRCLE

    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
UPDATE_PHYSICS ENDP

END MAIN