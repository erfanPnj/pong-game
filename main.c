/* ==============================================================================
 * STM32F401 PONG CONTROLLER FIRMWARE FOR PROTEUS (Keil uVision / Bare-Metal CMSIS)
 * Features:
 *   - PA0 & PA1 : Left & Right Buttons -> Sends 'L' & 'R' via USART1 (9600 8N1)
 *   - PB0, PB1, PB4..PB7 : 4-bit 16x2 Character LCD Driver (RS, E, D4..D7)
 *   - PA9 & PA10 : USART1 TX & RX (Receives 'W', 'G', or Raw Score 0..30)
 * ============================================================================== */

#include "stm32f4xx.h"
#include <stdio.h>

/* --- Simple CPU Cycle Delay (16MHz Default HSI Clock) --- */
void Delay_ms(uint32_t ms)
{
    uint32_t count = ms * 1600; /* Approximate loop for 16MHz */
    while (count--)
    {
        __NOP();
    }
}

/* ==============================================================================
 * 16x2 CHARACTER LCD DRIVER (4-BIT MODE ON PORT B)
 * PB0 = RS, PB1 = EN, PB4..PB7 = D4..D7
 * ============================================================================== */
#define LCD_RS_SET (GPIOB->BSRR = (1 << 0))
#define LCD_RS_CLR (GPIOB->BSRR = (1 << 16))
#define LCD_EN_SET (GPIOB->BSRR = (1 << 1))
#define LCD_EN_CLR (GPIOB->BSRR = (1 << 17))

void LCD_Pulse_EN(void)
{
    LCD_EN_SET;
    Delay_ms(2);
    LCD_EN_CLR;
    Delay_ms(2);
}

void LCD_Send_4Bit(uint8_t data)
{
    /* Clear PB4..PB7 first */
    GPIOB->BSRR = (0xF0 << 16);
    /* Put upper 4 bits of 'data' onto PB4..PB7 */
    GPIOB->BSRR = ((data & 0xF0));
    LCD_Pulse_EN();
}

void LCD_Command(uint8_t cmd)
{
    LCD_RS_CLR;
    LCD_Send_4Bit(cmd & 0xF0);
    LCD_Send_4Bit((cmd << 4) & 0xF0);
    Delay_ms(3);
}

void LCD_Char(char chr)
{
    LCD_RS_SET;
    LCD_Send_4Bit(chr & 0xF0);
    LCD_Send_4Bit((chr << 4) & 0xF0);
    Delay_ms(1);
}

void LCD_String(char *str)
{
    while (*str)
    {
        LCD_Char(*str++);
    }
}

void LCD_SetCursor(uint8_t row, uint8_t col)
{
    uint8_t addr = (row == 0) ? 0x80 : 0xC0;
    addr += col;
    LCD_Command(addr);
}

void LCD_Init(void)
{
    Delay_ms(40);
    LCD_RS_CLR;
    /* Special initialization sequence for 4-bit mode */
    LCD_Send_4Bit(0x30);
    Delay_ms(5);
    LCD_Send_4Bit(0x30);
    Delay_ms(1);
    LCD_Send_4Bit(0x30);
    Delay_ms(1);
    LCD_Send_4Bit(0x20); /* Set to 4-bit mode */

    LCD_Command(0x28); /* 2 lines, 5x8 font, 4-bit mode */
    LCD_Command(0x0C); /* Display ON, Cursor OFF */
    LCD_Command(0x06); /* Auto-increment cursor */
    LCD_Command(0x01); /* Clear LCD */
    Delay_ms(5);
}

/* ==============================================================================
 * USART1 DRIVER (BAUD RATE = 9600 @ 16MHz)
 * PA9 = USART1_TX, PA10 = USART1_RX
 * ============================================================================== */
void USART1_Init(void)
{
    /* 1. Enable Clocks for GPIOA and USART1 */
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB2ENR |= RCC_APB2ENR_USART1EN;

    /* 2. Configure PA9 (TX) and PA10 (RX) as Alternate Function (AF7) */
    GPIOA->MODER &= ~(GPIO_MODER_MODER9 | GPIO_MODER_MODER10);
    GPIOA->MODER |= (2 << (9 * 2)) | (2 << (10 * 2));
    GPIOA->AFR[1] &= ~((0xF << 4) | (0xF << 8));
    GPIOA->AFR[1] |= ((7 << 4) | (7 << 8)); /* AF7 for USART1 */

    /* 3. Configure Baud Rate 9600 for 16MHz Clock -> BRR = 16000000 / 9600 = 1667 (0x0683) */
    USART1->BRR = 0x0683;

    /* 4. Enable USART1, TX, and RX */
    USART1->CR1 = USART_CR1_TE | USART_CR1_RE | USART_CR1_UE;
}

void USART1_SendChar(char chr)
{
    while (!(USART1->SR & USART_SR_TXE))
        ; /* Wait until TX buffer is empty */
    USART1->DR = chr;
}

uint8_t USART1_DataAvailable(void)
{
    return (USART1->SR & USART_SR_RXNE) ? 1 : 0;
}

uint8_t USART1_ReadChar(void)
{
    return (uint8_t)(USART1->DR & 0xFF);
}

/* ==============================================================================
 * GPIO INITIALIZATION FOR BUTTONS & LCD
 * ============================================================================== */
void GPIO_Init(void)
{
    /* 1. Enable Clocks for GPIOA and GPIOB */
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN | RCC_AHB1ENR_GPIOBEN;

    /* 2. Configure PA0 and PA1 as Input with Internal Pull-Up (Left & Right Buttons) */
    GPIOA->MODER &= ~(GPIO_MODER_MODER0 | GPIO_MODER_MODER1);
    GPIOA->PUPDR &= ~(GPIO_PUPDR_PUPDR0 | GPIO_PUPDR_PUPDR1);
    GPIOA->PUPDR |= (1 << (0 * 2)) | (1 << (1 * 2)); /* Pull-up */

    /* 3. Configure PB0, PB1, PB4..PB7 as General Purpose Output for LCD */
    GPIOB->MODER &= ~(GPIO_MODER_MODER0 | GPIO_MODER_MODER1 |
                      GPIO_MODER_MODER4 | GPIO_MODER_MODER5 |
                      GPIO_MODER_MODER6 | GPIO_MODER_MODER7);
    GPIOB->MODER |= (1 << (0 * 2)) | (1 << (1 * 2)) |
                    (1 << (4 * 2)) | (1 << (5 * 2)) |
                    (1 << (6 * 2)) | (1 << (7 * 2));
}

/* ==============================================================================
 * MAIN PROGRAM ENTRY POINT
 * ============================================================================== */
int main(void)
{
    /* Initialize Hardware Peripherals */
    GPIO_Init();
    USART1_Init();
    LCD_Init();

    /* Initial Welcome Message on LCD */
    LCD_SetCursor(0, 0);
    LCD_String("PONG CONTROLLER");
    LCD_SetCursor(1, 0);
    LCD_String("SCORE: 00");

    uint8_t last_left = 1;
    uint8_t last_right = 1;

    while (1)
    {
        /* --- 1. HANDLE LEFT BUTTON (PA0 - Active Low) --- */
        uint8_t current_left = (GPIOA->IDR & (1 << 0)) ? 1 : 0;
        if (current_left == 0 && last_left == 1)
        {
            USART1_SendChar('L');
            Delay_ms(80); /* Simple debounce */
        }
        last_left = current_left;

        /* --- 2. HANDLE RIGHT BUTTON (PA1 - Active Low) --- */
        uint8_t current_right = (GPIOA->IDR & (1 << 1)) ? 1 : 0;
        if (current_right == 0 && last_right == 1)
        {
            USART1_SendChar('R');
            Delay_ms(80); /* Simple debounce */
        }
        last_right = current_right;

        /* --- 3. HANDLE INCOMING UART DATA FROM PC/GAME --- */
        if (USART1_DataAvailable())
        {
            uint8_t rx_data = USART1_ReadChar();

            if (rx_data == 'W')
            {
                LCD_Command(0x01); /* Clear LCD */
                LCD_SetCursor(0, 4);
                LCD_String("YOU WIN!");
            }
            else if (rx_data == 'G')
            {
                LCD_Command(0x01); /* Clear LCD */
                LCD_SetCursor(0, 3);
                LCD_String("GAME OVER!");
            }
            else if (rx_data <= 30)
            {
                /* Valid Score value received (0 to 30) -> Update LCD */
                char score_str[4];
                sprintf(score_str, "%02d", rx_data);
                LCD_SetCursor(1, 7);
                LCD_String(score_str);
            }
        }

        Delay_ms(5);
    }
}