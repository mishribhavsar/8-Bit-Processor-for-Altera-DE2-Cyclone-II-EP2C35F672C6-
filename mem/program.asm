; program.asm -- demo: sum of 1..N with loops, branches and memory
;
;   N comes from the switches (input port 0xFF).
;   Each partial sum is stored in a table at 0x20, 0x21, ...
;   The final sum (mod 256) goes to the LEDs (output port 0xFE), then HLT.
;   N = 10 -> LEDs show 0x37 (55); table = 0A 13 1B 22 28 2D 31 34 36 37
;
; Build:  python3 ../tools/asm.py program.asm program.hex

        .equ IN     0xFF
        .equ OUT    0xFE
        .equ TABLE  0x20

start:  LD   R1, [IN]       ; R1 = N (switches)
        LDI  R0, 0          ; R0 = running sum
        LDI  R3, TABLE      ; R3 = table pointer
        LDI  R2, 0
        CMP  R1, R2         ; N == 0 ?
        BEQ  done
loop:   ADD  R0, R1         ; sum += i
        STR  R0, [R3]       ; table[k] = sum      (R0 forwarded from ADD)
        INC  R3             ; next table slot
        DEC  R1             ; i--, sets ZF at 0
        BNE  loop           ; taken branch -> 2-cycle flush in the pipeline
done:   ST   R0, [OUT]      ; LEDs = sum
        HLT
