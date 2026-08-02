# pong-game
# 8086 Pong & Breakout Game with STM32F401 Hardware Controller

A full-stack microprocessor embedded systems project featuring a custom **Arcade Pong & Breakout Game** written in **8086 Assembly (VGA Mode 13h)** controlled by an external **STM32F401 ARM Cortex-M4 Microcontroller** and a **16x2 Character LCD** simulated in **Proteus Design Suite**.

The game engine running inside **DOSBox** communicates bi-directionally in real-time with the simulated STM32 hardware controller via a **Virtual UART Null-Modem Bridge (com0com)** at **9600 Baud (8N1)**.

---

## 🏗️ System Architecture & Features

```
+------------------------------------+          Virtual COM Bridge          +------------------------------------+
|         PROTEUS (STM32F401)        |         (e.g., COM1 <-> COM2)        |            DOSBox (8086)           |
|                                    |                                      |                                    |
|  PA0 (Input) <--- Left Button      |                                      |  VGA Mode 13h (320x200 256-Color)  |
|  PA1 (Input) <--- Right Button     |                                      |  Solid Paddle & Ball Physics       |
|  PB0..PB7    ---> 16x2 Char LCD    |                                      |  6 Randomized Blocks (Res. 1 to 5) |
|                                    |                                      |                                    |
|  PA9 (TX)  ---> COMPIM TXD (Pin 3) | ===> COM1  <===============>  COM2  ===> COM1 (3F8h) : Read 'L' / 'R'     |
|  PA10 (RX) <--- COMPIM RXD (Pin 2) | <=== COM1  <===============>  COM2  <=== COM1 (3F8h) : Send 'S'/'W'/'G'   |
+------------------------------------+                                      +------------------------------------+

```

### 1. 8086 Assembly Game Engine (`PONG.ASM`)

* **Graphics Mode:** VGA Mode 13h (`320x200` resolution, 256 colors) with zero-flicker delta rendering.
* **Visual Arena:** Solid 3-pixel Cyan arcade borders (Top, Left, Right).
* **Physics & Collision:**
* **Solid Paddle:** Accurate bounding box that prevents the ball from clipping or getting trapped.
* **Immediate Game-Over:** Losing condition triggers instantly if the bottom of the ball reaches the paddle's vertical level (`Y = 185`) without a clean hit.
* **Randomized Block Grid:** Up to 6 square blocks (`24x24 px`) spawned randomly at startup with resilience levels `1 to 5` (color-coded and numbered).


* **Dual Input Control:** Accepts movement commands from the STM32 hardware controller via UART (`COM1 - 03F8h`) while maintaining fallback support for the PC keyboard (`A`/`D` or Arrow Keys).

### 2. STM32F401 Hardware Controller (`main.c`)

* **Microcontroller:** `STM32F401C6` programmed in bare-metal CMSIS C using **Keil uVision (MDK-ARM)**.
* **Input Buttons:** Left (`PA0`) and Right (`PA1`) buttons configured with internal pull-ups and software debouncing.
* **Display Output:** 4-bit LCD driver interfacing with an `LM016L` 16x2 Character LCD on Port B (`PB0`, `PB1`, `PB4..PB7`).
* **Hardware UART (`USART1`):** Operates at `9600 Baud, 8 Data Bits, No Parity, 1 Stop Bit` (`PA9 = TX`, `PA10 = RX`).

### 3. UART Communication Protocol

* **STM32 ➔ 8086 Game (Paddle Control):**
* `'L'` (`0x4C`): Move paddle left.
* `'R'` (`0x52`): Move paddle right.


* **8086 Game ➔ STM32 (Live LCD Display Update):**
* `'S'` (`0x53`) + `<Score_Byte>` (`0..30`): Updates the score on line 2 of the LCD (`SCORE: XX`).
* `'W'` (`0x57`): Displays `"YOU WIN!"` on the LCD.
* `'G'` (`0x47`): Displays `"GAME OVER!"` on the LCD.



---

## 🛠️ Prerequisites & Software Requirements

1. **DOSBox** (v0.74-3 or later)
2. **Borland Turbo Assembler (TASM)** (`TASM.EXE`, `TLINK.EXE`, `DPMI16BI.OVL`, `RTM.EXE`)
3. **Proteus Design Suite** (v8.9 or later)
4. **Keil uVision MDK-ARM** (v5.x)
5. **com0com** (Null-modem Virtual Serial Port Emulator for Windows)

---

## 🔌 Hardware Wiring & Pinout Table (Proteus)

| Component | Pin Name | STM32F401 Pin | Description |
| --- | --- | --- | --- |
| **Left Button** | Terminal 1 -> GND | **`PA0`** | Active-Low Input with internal Pull-Up |
| **Right Button** | Terminal 1 -> GND | **`PA1`** | Active-Low Input with internal Pull-Up |
| **16x2 LCD (`LM016L`)** | `RS` | **`PB0`** | Register Select |
|  | `RW` | **`GND`** | Hardwired to Write mode |
|  | `E` | **`PB1`** | Enable Pulse |
|  | `D4` to `D7` | **`PB4` to `PB7**` | 4-Bit Data Bus |
| **COMPIM (UART Bridge)** | `TXD` (Pin 3) | **`PA9`** | USART1 Transmit (`TX`) |
|  | `RXD` (Pin 2) | **`PA10`** | USART1 Receive (`RX`) |
|  | `GND` (Pin 5) | **`GND`** | Common Ground |

---

## 🚀 Step-by-Step Setup & Build Instructions

### Step 1: Configure Virtual Serial Ports (`com0com`)

1. Open the `com0com` command prompt (`setupc.exe`) as Administrator.
2. Create a connected pair of virtual serial ports (`COM1` and `COM2`):
```cmd
install PortName=COM1 PortName=COM2

```


3. Confirm installation in Windows Device Manager under **Ports (COM & LPT)**.

---

### Step 2: Build & Configure the Microcontroller Firmware (Keil & Proteus)

1. Open **Keil uVision**, create a new project for `STM32F401C6`, and include CMSIS Core/Startup files.
2. Add `main.c` to your project source tree.
3. In **Project > Options for Target > Output**, check **Create HEX File** and set the crystal frequency to `16.0 MHz`.
4. Press **F7** to build the project and generate the `.hex` file.
5. Open your Proteus schematic:
* Double-click the `STM32F401C6` MCU, browse to the compiled `.hex` file, and set **Crystal Frequency** to **`16MHz`**.
* Double-click the `COMPIM` component and configure:
* **Port:** `COM1`
* **Physical/Virtual Baud Rate:** `9600`
* **Data/Parity/Stop Bits:** `8, None, 1`





---

### Step 3: Configure DOSBox Serial Bridge

1. Open your DOSBox configuration file (`dosbox-0.74-3.conf`).
2. Scroll down to the `[serial]` section and map `serial1` to Windows `COM2`:
```ini
[serial]
serial1=directserial realport:COM2
serial2=dummy
serial3=dummy
serial4=dummy

```


3. *(Optional)* Add your TASM directory to the `[autoexec]` section at the bottom of `dosbox-0.74-3.conf` for automatic mounting:
```ini
[autoexec]
mount c C:\TASM
c:
cls

```



---

### Step 4: Compile & Run the 8086 Game in DOSBox

1. Place `PONG.ASM` in your `C:\TASM` folder alongside `TASM.EXE`, `TLINK.EXE`, `DPMI16BI.OVL`, and `RTM.EXE`.
2. Start **DOSBox**. Check the status window to verify the serial port connection:
```text
Serial1: Opening COM2

```


3. Assemble, link, and launch the game using the following command in DOSBox:
```dos
tasm pong.asm && tlink pong && pong

```



---

## 🎮 How to Play & Verification Guide

1. **Start Proteus Simulation:** Click the **Play** button in Proteus first. The LCD will initialize and display:
```text
PONG CONTROLLER
SCORE: 00

```


2. **Launch Game in DOSBox:** Run `pong` in DOSBox. The VGA Mode 13h graphical arena will appear.
3. **Hardware Control:**
* Press the **Left Button (`PA0`)** in Proteus to move the paddle left.
* Press the **Right Button (`PA1`)** in Proteus to move the paddle right.


4. **Live Synchronization:**
* Every time the ball bounces off the paddle, the score increases, and the LCD in Proteus instantly updates (`SCORE: 01`, `SCORE: 02`, etc.).
* If the ball reaches the bottom (`Y = 185`) without hitting the paddle, the LCD immediately displays **`GAME OVER!`**.
* If you reach the target score of 30, the LCD displays **`YOU WIN!`**.