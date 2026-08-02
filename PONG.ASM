; ==============================================================================
; PONG & BREAKOUT GAME IN 8086 ASSEMBLY (VGA MODE 13h)
; Patched v3:
;   - Score now increases only on paddle hits (not block hits)
;   - Blocks are solid: real circle-vs-square collision (accounts for ball
;     radius) with side detection, so the ball can no longer clip through
;   - Exactly one random layout of up to 6 square blocks, generated once at
;     startup (no regeneration on contact); each block shows its 1-5
;     resilience value as text
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
    SCORE       DW 0         ; Player Score (Target: 30) - increases on PADDLE hits only
    GAME_OVER   DB 0         ; 0 = Running, 1 = Lost
    WIN_FLAG    DB 0         ; 0 = Running, 1 = Won

    ; --- Block System: up to 6 square blocks, placed once at startup ---
    BLOCK_COUNT_MAX   EQU 6
    BLOCK_SIZE        EQU 24     ; blocks are SQUARE (24x24)
    GRID_COLS         EQU 9
    GRID_ROWS         EQU 4
    GRID_TOTAL        EQU 36     ; GRID_COLS * GRID_ROWS possible slots
    CELL_SIZE         EQU 32     ; pitch between slots (leaves a gap around each block)
    GRID_START_X      EQU 8
    GRID_START_Y      EQU 24     ; below the score line
    BLOCK_AREA_TOP    EQU 24
    BLOCK_AREA_BOTTOM EQU 144    ; comfortably above the paddle (Y=185)

    BLOCK_ACTIVE DB BLOCK_COUNT_MAX DUP(0)   ; 1 = alive, 0 = empty/destroyed
    BLOCK_RES    DB BLOCK_COUNT_MAX DUP(0)   ; resilience 1-5
    BLOCK_X      DW BLOCK_COUNT_MAX DUP(0)   ; top-left pixel X
    BLOCK_Y      DW BLOCK_COUNT_MAX DUP(0)   ; top-left pixel Y

    SLOT_POOL    DB GRID_TOTAL DUP(0)        ; used once at startup to pick unique slots
    REMAINING    DW 0
    NUM_BLOCKS   DB 0                        ; how many blocks this game (3-6)

    ; scratch used while resolving a block collision
    OVERLAP_L    DW 0
    OVERLAP_R    DW 0
    OVERLAP_T    DW 0
    OVERLAP_B    DW 0

    ; --- Pseudo-Random Generator Seed ---
    RAND_SEED   DW 0

    ; --- Score Display (top of screen) ---
    SCORE_TEXT_ROW   EQU 0
    SCORE_TEXT_COL   EQU 1
    SCORE_DIGIT_COL  EQU 7
    SCORE_DIGIT_X    EQU 56      ; = SCORE_DIGIT_COL * 8 px
    SCORE_DIGIT_Y    EQU 0       ; = SCORE_TEXT_ROW * 8 px
    SCORE_LABEL      DB 'SCORE:'
    SCORE_LABEL_LEN  EQU $-SCORE_LABEL
    SCORE_DIGITS     DB '00'
    PRINT_COLOR_TEMP DB 0

    ; --- Block number label scratch (reuses PRINT_STRING) ---
    BLOCK_NUM_CHAR DB '0'
    BLOCK_NUM_COL  DB 0
    BLOCK_NUM_ROW  DB 0

    ; --- End-of-Game Messages ---
    GAME_OVER_MSG     DB 'GAME OVER - PRESS ANY KEY'
    GAME_OVER_MSG_LEN EQU $-GAME_OVER_MSG
    WIN_MSG           DB 'YOU WIN! - PRESS ANY KEY'
    WIN_MSG_LEN       EQU $-WIN_MSG

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

    ; 2. Initialize the (at most 6) random square blocks - done ONCE
    CALL INIT_BLOCKS

    ; 3. Initial Static Scene Rendering (Drawn ONCE to prevent CPU bottleneck)
    CALL CLEAR_SCREEN
    CALL DRAW_BLOCKS
    CALL DRAW_PADDLE
    CALL DRAW_CIRCLE
    CALL DRAW_SCORE_LABEL
    CALL DRAW_SCORE_VALUE

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
    MOV SI, OFFSET GAME_OVER_MSG
    MOV CX, GAME_OVER_MSG_LEN
    MOV DH, 12
    MOV DL, 8
    MOV BL, 12          ; Red
    CALL PRINT_STRING
    CALL WAIT_FOR_KEY
    JMP END_PROGRAM

WIN_GAME:
    MOV WIN_FLAG, 1
    MOV SI, OFFSET WIN_MSG
    MOV CX, WIN_MSG_LEN
    MOV DH, 12
    MOV DL, 8
    MOV BL, 10          ; Green
    CALL PRINT_STRING
    CALL WAIT_FOR_KEY

END_PROGRAM:
    ; Return to Standard Text Mode 03h
    MOV AX, 0003H
    INT 10H

    ; Terminate Program
    MOV AH, 4CH
    INT 21H
MAIN ENDP

; ==============================================================================
; PROCEDURE: CLEAR_SCREEN
; ==============================================================================
CLEAR_SCREEN PROC NEAR
    PUSH AX
    PUSH CX
    PUSH DI

    XOR DI, DI
    XOR AX, AX
    MOV CX, 32000
    CLD
    REP STOSW

    POP DI
    POP CX
    POP AX
    RET
CLEAR_SCREEN ENDP

; ==============================================================================
; PROCEDURE: DELAY
; ==============================================================================
DELAY PROC NEAR
    PUSH BX
    PUSH CX

    MOV BX, 1
OUTER_DELAY:
    MOV CX, 0E000H
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
; Inputs: CX = X, DX = Y, AL = Color Code
; ==============================================================================
DRAW_PIXEL PROC NEAR
    PUSH BX
    PUSH DX
    PUSH DI

    MOV DI, DX
    SHL DI, 8
    MOV BX, DX
    SHL BX, 6
    ADD DI, BX
    ADD DI, CX

    STOSB

    POP DI
    POP DX
    POP BX
    RET
DRAW_PIXEL ENDP

; ==============================================================================
; PROCEDURE: PRINT_STRING
; Prints text via BIOS teletype, which also works inside VGA graphics modes.
; Inputs: SI = offset of string, CX = length, DH = row, DL = column, BL = color
; ==============================================================================
PRINT_STRING PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    MOV PRINT_COLOR_TEMP, BL

    MOV AH, 02H
    MOV BH, 0
    INT 10H

PRINT_STRING_LOOP:
    MOV AL, [SI]
    MOV AH, 0EH
    MOV BH, 0
    MOV BL, PRINT_COLOR_TEMP
    INT 10H
    INC SI
    LOOP PRINT_STRING_LOOP

    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
PRINT_STRING ENDP

; ==============================================================================
; PROCEDURE: WAIT_FOR_KEY
; ==============================================================================
WAIT_FOR_KEY PROC NEAR
    PUSH AX
    MOV AH, 00H
    INT 16H
    POP AX
    RET
WAIT_FOR_KEY ENDP

; ==============================================================================
; PROCEDURE: DRAW_CIRCLE
; ==============================================================================
DRAW_CIRCLE PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

    MOV SI, BALL_Y
    SUB SI, BALL_R
    MOV DI, BALL_Y
    ADD DI, BALL_R

ROW_LOOP:
    MOV CX, BALL_X
    SUB CX, BALL_R

COL_LOOP:
    MOV AX, CX
    SUB AX, BALL_X
    IMUL AX
    MOV BX, AX

    MOV AX, SI
    SUB AX, BALL_Y
    IMUL AX
    ADD BX, AX

    MOV AX, BALL_R
    IMUL AX

    CMP BX, AX
    JG SKIP_PIXEL

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
; ==============================================================================
ERASE_CIRCLE PROC NEAR
    PUSH AX
    MOV AL, BALL_COLOR
    PUSH AX
    MOV BALL_COLOR, 0
    CALL DRAW_CIRCLE
    POP AX
    MOV BALL_COLOR, AL
    POP AX
    RET
ERASE_CIRCLE ENDP

; ==============================================================================
; PROCEDURE: DRAW_PADDLE
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
; ==============================================================================
ERASE_PADDLE PROC NEAR
    PUSH AX
    MOV AL, PADDLE_COL
    PUSH AX
    MOV PADDLE_COL, 0
    CALL DRAW_PADDLE
    POP AX
    MOV PADDLE_COL, AL
    POP AX
    RET
ERASE_PADDLE ENDP

; ==============================================================================
; PROCEDURE: DRAW_SCORE_LABEL (drawn once at startup only)
; ==============================================================================
DRAW_SCORE_LABEL PROC NEAR
    PUSH SI
    PUSH CX
    PUSH DX
    PUSH BX

    MOV SI, OFFSET SCORE_LABEL
    MOV CX, SCORE_LABEL_LEN
    MOV DH, SCORE_TEXT_ROW
    MOV DL, SCORE_TEXT_COL
    MOV BL, 15
    CALL PRINT_STRING

    POP BX
    POP DX
    POP CX
    POP SI
    RET
DRAW_SCORE_LABEL ENDP

; ==============================================================================
; PROCEDURE: DRAW_SCORE_VALUE
; Called at startup and every time SCORE changes (paddle hits only).
; ==============================================================================
DRAW_SCORE_VALUE PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

    MOV DX, SCORE_DIGIT_Y
    MOV DI, DX
    ADD DI, 8
ERASE_SCORE_ROW:
    MOV CX, SCORE_DIGIT_X
    MOV SI, CX
    ADD SI, 16
ERASE_SCORE_COL:
    MOV AL, 0
    CALL DRAW_PIXEL
    INC CX
    CMP CX, SI
    JL ERASE_SCORE_COL
    INC DX
    CMP DX, DI
    JL ERASE_SCORE_ROW

    MOV AX, SCORE
    XOR DX, DX
    MOV BX, 10
    DIV BX
    ADD AL, '0'
    MOV SCORE_DIGITS, AL
    MOV AL, DL
    ADD AL, '0'
    MOV SCORE_DIGITS+1, AL

    MOV SI, OFFSET SCORE_DIGITS
    MOV CX, 2
    MOV DH, SCORE_TEXT_ROW
    MOV DL, SCORE_DIGIT_COL
    MOV BL, 15
    CALL PRINT_STRING

    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
DRAW_SCORE_VALUE ENDP

; ==============================================================================
; PROCEDURE: GET_RANDOM
; LCG: seed = seed * 25173 + 13849 (mod 65536). Returns AX = next value.
; ==============================================================================
GET_RANDOM PROC NEAR
    PUSH BX
    PUSH DX

    MOV AX, RAND_SEED
    MOV BX, 25173
    MUL BX
    ADD AX, 13849
    MOV RAND_SEED, AX

    POP DX
    POP BX
    RET
GET_RANDOM ENDP

; ==============================================================================
; PROCEDURE: INIT_BLOCKS
; Runs ONCE at program start. Picks 3-6 unique grid slots (out of 36 possible,
; via a partial Fisher-Yates draw so blocks never overlap), assigns each a
; random 1-5 resilience value, and marks it active. Never called again, so
; no new blocks ever appear mid-game.
; ==============================================================================
INIT_BLOCKS PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

    ; Seed the generator once using the system timer tick count
    MOV AH, 00H
    INT 1AH
    MOV RAND_SEED, DX

    ; Fill the slot pool with 0..GRID_TOTAL-1
    MOV CX, GRID_TOTAL
    MOV BX, 0
FILL_POOL_LOOP:
    MOV AL, BL
    MOV SLOT_POOL[BX], AL
    INC BX
    LOOP FILL_POOL_LOOP

    MOV REMAINING, GRID_TOTAL

    ; Decide how many blocks to place this game: 3 to 6 (never more than 6)
    CALL GET_RANDOM
    XOR DX, DX
    MOV BX, 4
    DIV BX
    ADD DL, 3
    MOV NUM_BLOCKS, DL

    XOR SI, SI                 ; SI = block slot index (0..NUM_BLOCKS-1)
PLACE_BLOCK_LOOP:
    MOV AL, NUM_BLOCKS
    MOV AH, 0
    CMP SI, AX
    JL PLACE_BLOCK_BODY
    JMP PLACE_BLOCKS_DONE
PLACE_BLOCK_BODY:

    ; pick a random remaining pool position and read the grid slot it holds
    CALL GET_RANDOM
    XOR DX, DX
    MOV BX, REMAINING
    DIV BX
    MOV BX, DX                 ; BX = chosen pool position
    MOV AL, SLOT_POOL[BX]      ; AL = chosen grid slot number (0-35)
    MOV DL, AL                 ; keep it safe in DL

    ; remove it from the pool: move the last pool element into its place
    MOV AX, REMAINING
    DEC AX
    MOV DI, AX
    MOV CL, SLOT_POOL[DI]
    MOV SLOT_POOL[BX], CL
    DEC REMAINING

    ; convert grid slot number (in DL) into row, col
    MOV AH, 0
    MOV AL, DL
    XOR DX, DX
    MOV BX, GRID_COLS
    DIV BX                      ; AX = row, DX = col

    ; pixel Y = GRID_START_Y + row*CELL_SIZE
    MOV BX, CELL_SIZE
    PUSH DX                     ; save col
    MUL BX
    ADD AX, GRID_START_Y
    MOV DI, SI
    SHL DI, 1                   ; DI = SI*2 (word index)
    MOV BLOCK_Y[DI], AX

    ; pixel X = GRID_START_X + col*CELL_SIZE
    POP AX                      ; AX = col
    MOV BX, CELL_SIZE
    MUL BX
    ADD AX, GRID_START_X
    MOV BLOCK_X[DI], AX

    ; random resilience 1-5, mark active
    CALL GET_RANDOM
    XOR DX, DX
    MOV BX, 5
    DIV BX
    INC DX
    MOV BLOCK_RES[SI], DL
    MOV BLOCK_ACTIVE[SI], 1

    INC SI
    JMP PLACE_BLOCK_LOOP

PLACE_BLOCKS_DONE:
    ; any slots from NUM_BLOCKS..5 stay at their .DATA default (0 = inactive)

    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
INIT_BLOCKS ENDP

; ==============================================================================
; PROCEDURE: GET_RESILIENCE_COLOR (Maps Resilience 1-5 to Distinct Palette)
; ==============================================================================
GET_RESILIENCE_COLOR PROC NEAR
    CMP AL, 5
    JE COL_5
    CMP AL, 4
    JE COL_4
    CMP AL, 3
    JE COL_3
    CMP AL, 2
    JE COL_2
    MOV AL, 48           ; Resilience 1 = Blue
    RET
COL_2:
    MOV AL, 46           ; Resilience 2 = Green
    RET
COL_3:
    MOV AL, 44           ; Resilience 3 = Yellow
    RET
COL_4:
    MOV AL, 42           ; Resilience 4 = Orange
    RET
COL_5:
    MOV AL, 40           ; Resilience 5 = Red
    RET
GET_RESILIENCE_COLOR ENDP

; ==============================================================================
; PROCEDURE: DRAW_BLOCKS
; Draws the (up to 6) active square blocks with their color + number.
; ==============================================================================
DRAW_BLOCKS PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

    XOR SI, SI
DRAW_BLOCKS_LOOP:
    CMP SI, BLOCK_COUNT_MAX
    JGE DRAW_BLOCKS_DONE

    CMP BLOCK_ACTIVE[SI], 0
    JE DRAW_BLOCKS_NEXT

    MOV DI, SI
    SHL DI, 1
    MOV CX, BLOCK_X[DI]
    MOV DX, BLOCK_Y[DI]

    MOV AL, BLOCK_RES[SI]
    CALL GET_RESILIENCE_COLOR
    CALL DRAW_SINGLE_BLOCK
    MOV AL, BLOCK_RES[SI]
    CALL DRAW_BLOCK_NUMBER

DRAW_BLOCKS_NEXT:
    INC SI
    JMP DRAW_BLOCKS_LOOP

DRAW_BLOCKS_DONE:
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
; Draws a solid BLOCK_SIZE x BLOCK_SIZE square.
; Inputs: CX = X, DX = Y, AL = Color
; ==============================================================================
DRAW_SINGLE_BLOCK PROC NEAR
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

    MOV SI, DX
    ADD SI, BLOCK_SIZE
    MOV DI, CX
    ADD DI, BLOCK_SIZE

BLOCK_Y_LOOP:
    PUSH CX

BLOCK_X_LOOP:
    CALL DRAW_PIXEL
    INC CX
    CMP CX, DI
    JL BLOCK_X_LOOP

    POP CX
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
; PROCEDURE: DRAW_BLOCK_NUMBER
; Writes the resilience value (1-5) on top of a block using BIOS teletype.
; Grid constants are all multiples of 8, so this aligns exactly to the
; blocks top-left pixel - no rounding drift.
; Inputs: AL = resilience (1-5), CX = block X (pixel), DX = block Y (pixel)
; ==============================================================================
DRAW_BLOCK_NUMBER PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    ADD AL, '0'
    MOV BLOCK_NUM_CHAR, AL

    MOV SI, DX                 ; preserve block Y before DX is used by DIV

    MOV AX, CX
    XOR DX, DX
    MOV BX, 8
    DIV BX
    MOV BLOCK_NUM_COL, AL

    MOV AX, SI
    XOR DX, DX
    MOV BX, 8
    DIV BX
    MOV BLOCK_NUM_ROW, AL

    MOV SI, OFFSET BLOCK_NUM_CHAR
    MOV CX, 1
    MOV DH, BLOCK_NUM_ROW
    MOV DL, BLOCK_NUM_COL
    MOV BL, 15
    CALL PRINT_STRING

    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
DRAW_BLOCK_NUMBER ENDP

; ==============================================================================
; PROCEDURE: CHECK_KEYBOARD
; ==============================================================================
CHECK_KEYBOARD PROC NEAR
    PUSH AX
    PUSH DX

    MOV AH, 01H
    INT 16H
    JZ KEY_DONE

    MOV AH, 00H
    INT 16H

    CMP AL, 'a'
    JE MOVE_LEFT
    CMP AL, 'A'
    JE MOVE_LEFT
    CMP AH, 4BH
    JE MOVE_LEFT

    CMP AL, 'd'
    JE MOVE_RIGHT
    CMP AL, 'D'
    JE MOVE_RIGHT
    CMP AH, 4DH
    JE MOVE_RIGHT
    JMP KEY_DONE

MOVE_LEFT:
    CALL ERASE_PADDLE
    MOV AX, PADDLE_STEP
    SUB PADDLE_X, AX
    CMP PADDLE_X, 2
    JGE DRAW_NEW_LEFT
    MOV PADDLE_X, 2
DRAW_NEW_LEFT:
    CALL DRAW_PADDLE
    JMP KEY_DONE

MOVE_RIGHT:
    CALL ERASE_PADDLE
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
    CALL DRAW_PADDLE

KEY_DONE:
    POP DX
    POP AX
    RET
CHECK_KEYBOARD ENDP

; ==============================================================================
; PROCEDURE: UPDATE_PHYSICS
; Score increases ONLY when the ball bounces off the paddle (Issue #1).
; Blocks are solid: real circle-vs-square overlap test using BALL_R, with
; side detection so the ball bounces off whichever face it hit (Issue #2).
; Blocks are only ever the set created once in INIT_BLOCKS (Issue #3).
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

    ; 4. Paddle Collision (Bottom) - the ONLY place SCORE increases
CHECK_PADDLE_COLLISION:
    MOV AX, PADDLE_Y
    SUB AX, BALL_R
    CMP BALL_Y, AX
    JGE PADDLE_Y_IN_RANGE
    JMP CHECK_BLOCKS_COLLISION
PADDLE_Y_IN_RANGE:

    MOV AX, PADDLE_X
    CMP BALL_X, AX
    JGE PADDLE_X_CHECK_2
    JMP CHECK_GAME_OVER
PADDLE_X_CHECK_2:
    ADD AX, PADDLE_W
    CMP BALL_X, AX
    JLE PADDLE_HIT_CONFIRMED
    JMP CHECK_GAME_OVER
PADDLE_HIT_CONFIRMED:

    NEG BALL_DY
    INC SCORE
    CALL DRAW_SCORE_VALUE
    JMP CHECK_BLOCKS_COLLISION

CHECK_GAME_OVER:
    MOV AX, 198
    CMP BALL_Y, AX
    JL CHECK_BLOCKS_COLLISION
    MOV GAME_OVER, 1
    JMP DONE_PHYSICS

    ; 5. Block Collisions - solid, circle-vs-square, no scoring here
CHECK_BLOCKS_COLLISION:
    MOV AX, BALL_Y
    ADD AX, BALL_R
    CMP AX, BLOCK_AREA_TOP
    JGE BLOCKS_Y_TOP_OK
    JMP DONE_PHYSICS
BLOCKS_Y_TOP_OK:
    MOV AX, BALL_Y
    SUB AX, BALL_R
    CMP AX, BLOCK_AREA_BOTTOM
    JLE BLOCKS_Y_BOTTOM_OK
    JMP DONE_PHYSICS
BLOCKS_Y_BOTTOM_OK:

    XOR SI, SI                     ; SI = block index 0..5
BLOCK_CHECK_LOOP:
    CMP SI, BLOCK_COUNT_MAX
    JL BLOCK_CHECK_CONTINUE
    JMP END_BLOCK_CHECK
BLOCK_CHECK_CONTINUE:

    CMP BLOCK_ACTIVE[SI], 0
    JNE BLOCK_IS_ACTIVE
    JMP NEXT_BLOCK_CHECK
BLOCK_IS_ACTIVE:

    MOV DI, SI
    SHL DI, 1
    MOV CX, BLOCK_X[DI]            ; CX = block left X
    MOV DX, BLOCK_Y[DI]            ; DX = block top Y

    ; --- Expanded AABB (circle-vs-square) overlap test ---
    MOV AX, BALL_X
    ADD AX, BALL_R
    CMP AX, CX
    JGE AABB_CHECK_2
    JMP NO_COLLISION_HERE
AABB_CHECK_2:
    MOV AX, BALL_X
    SUB AX, BALL_R
    MOV BX, CX
    ADD BX, BLOCK_SIZE
    CMP AX, BX
    JLE AABB_CHECK_3
    JMP NO_COLLISION_HERE
AABB_CHECK_3:
    MOV AX, BALL_Y
    ADD AX, BALL_R
    CMP AX, DX
    JGE AABB_CHECK_4
    JMP NO_COLLISION_HERE
AABB_CHECK_4:
    MOV AX, BALL_Y
    SUB AX, BALL_R
    MOV BX, DX
    ADD BX, BLOCK_SIZE
    CMP AX, BX
    JLE COLLISION_CONFIRMED
    JMP NO_COLLISION_HERE

NO_COLLISION_HERE:
    JMP NEXT_BLOCK_CHECK

COLLISION_CONFIRMED:
    ; --- Compute penetration depth from each of the 4 sides ---
    MOV AX, BALL_X
    ADD AX, BALL_R
    SUB AX, CX
    MOV OVERLAP_L, AX

    MOV AX, CX
    ADD AX, BLOCK_SIZE
    SUB AX, BALL_X
    ADD AX, BALL_R
    MOV OVERLAP_R, AX

    MOV AX, BALL_Y
    ADD AX, BALL_R
    SUB AX, DX
    MOV OVERLAP_T, AX

    MOV AX, DX
    ADD AX, BLOCK_SIZE
    SUB AX, BALL_Y
    ADD AX, BALL_R
    MOV OVERLAP_B, AX

    ; --- Smallest penetration = the side actually hit ---
    MOV AX, OVERLAP_L
    MOV BX, 0
    CMP OVERLAP_R, AX
    JGE SKIP_UPDATE_R
    MOV AX, OVERLAP_R
    MOV BX, 1
SKIP_UPDATE_R:
    CMP OVERLAP_T, AX
    JGE SKIP_UPDATE_T
    MOV AX, OVERLAP_T
    MOV BX, 2
SKIP_UPDATE_T:
    CMP OVERLAP_B, AX
    JGE SKIP_UPDATE_B
    MOV BX, 3
SKIP_UPDATE_B:

    CMP BX, 0
    JE HIT_LEFT
    CMP BX, 1
    JE HIT_RIGHT
    CMP BX, 2
    JE HIT_TOP
    JMP HIT_BOTTOM

HIT_LEFT:
    NEG BALL_DX
    MOV AX, CX
    SUB AX, BALL_R
    DEC AX
    MOV BALL_X, AX
    JMP COLLISION_SIDE_DONE

HIT_RIGHT:
    NEG BALL_DX
    MOV AX, CX
    ADD AX, BLOCK_SIZE
    ADD AX, BALL_R
    INC AX
    MOV BALL_X, AX
    JMP COLLISION_SIDE_DONE

HIT_TOP:
    NEG BALL_DY
    MOV AX, DX
    SUB AX, BALL_R
    DEC AX
    MOV BALL_Y, AX
    JMP COLLISION_SIDE_DONE

HIT_BOTTOM:
    NEG BALL_DY
    MOV AX, DX
    ADD AX, BLOCK_SIZE
    ADD AX, BALL_R
    INC AX
    MOV BALL_Y, AX

COLLISION_SIDE_DONE:
    DEC BLOCK_RES[SI]
    CMP BLOCK_RES[SI], 0
    JE BLOCK_DESTROYED

    MOV AL, BLOCK_RES[SI]
    CALL GET_RESILIENCE_COLOR
    CALL DRAW_SINGLE_BLOCK
    MOV AL, BLOCK_RES[SI]
    CALL DRAW_BLOCK_NUMBER
    JMP DONE_PHYSICS

BLOCK_DESTROYED:
    MOV BLOCK_ACTIVE[SI], 0
    MOV AL, 0
    CALL DRAW_SINGLE_BLOCK
    JMP DONE_PHYSICS

NEXT_BLOCK_CHECK:
    INC SI
    JMP BLOCK_CHECK_LOOP

END_BLOCK_CHECK:
    ; Fall through to DONE_PHYSICS

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