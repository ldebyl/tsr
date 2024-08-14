# x86 Timer TSR

A simple MS-DOS stopwatch TSR implemented in x86 assembly. The TSR can be loaded from the DOS prompt by running the executable as2c.exe. This will load the TSR program into memory. Pressing Alt and Insert will start or stop the timer. Pressing Alt and Home will reset the timer, and also stop it.

The program works by hooking two interrupts – INT 01Ch and INT 09h. By hooking interrupt 01Ch, a portion of the code is executed every 55ms. This code increments the internal counter, and updates the screen. Thus the display is updated approximately 20 times per second. Setting the Interrupt Vector Table entry for interrupt 9h to point to our own code allows us to intercept any keystrokes. Thus we can determine if one of the hotkeys has been pressed.

The rest of the program design is quite simple. A set of three variables stores the elapsed time. Two other variables store the original location of the interrupt service routines. The remainder of the variables used control such things as timer status and the video ram offset.

Initially the program was designed to use BIOS routines for displaying the numbers on the screen. However, this proved problematic when implementing the TSR portion. Using the BIOS routines caused the other running program to have its display corrupted. This implementation uses direct access to the video RAM for displaying timer. This method is probably also more efficient in terms of speed.

Assemble and link using Turbo Assembler.

## Initialization
- Initialize Segment Registers
- Initialize the Screen
- Retrieve current IVT entries for interrupts 09h and 01Ch
- Point IVT entries for interrupts 09h and 01Ch to point to keyboard handler and time handler, respectively
- Exit to DOS leaving program code and data in memory

## Keyboard Handler

ISR for Interrupt 09h:
- Reset the Data Segment Register
- Is an ALT key is been pressed, see what KEY it is been held in combination with.
- If KEY is Insert, start or stop timing.
- If KEY is Home, reset timer
- Execute original ISR

## Clock-Tick Handler

ISR for Interrupt 01Ch

- Reset the Data Segment Register
- Is the timer supposed to be active? If so, increment the elapsed time variables by 55ms.
- If an overflow has occurred, stop the timer.
- Update the display
- Execute the original ISR
