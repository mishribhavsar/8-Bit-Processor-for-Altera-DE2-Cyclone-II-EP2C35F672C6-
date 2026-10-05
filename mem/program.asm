; program.asm -- demo program that exercises all 15 ALU instructions
;
; At reset: R0 = SW[7:0], R1 = SW[15:8], R2 = 0x0F, R3 = 0x01
; Format:   OP Rd, Rs   ->  Rd <- Rd op Rs
;
; Build:    python3 ../tools/asm.py program.asm program.hex

        ADD  R0, R1      ; R0 = R0 + R1        (CF/OF/AF from the add)
        SUB  R0, R3      ; R0 = R0 - 1
        CMP  R0, R1      ; flags <- R0 - R1, no write-back
        AND  R1, R2      ; R1 = R1 & 0x0F      (keep low nibble)
        OR   R1, R3      ; R1 = R1 | 0x01      (R1 is now odd, non-zero)
        XOR  R0, R1      ; R0 = R0 ^ R1
        NOT  R0          ; R0 = ~R0
        LSL  R0          ; R0 = R0 << 1        (CF = old bit 7)
        LSR  R0          ; R0 = R0 >> 1        (CF = old bit 0)
        ROL  R1          ; R1 rotated left
        ROR  R1          ; R1 rotated right    (back to the odd value)
        MUL  R0, R1      ; R0 = low byte of R0 * R1   (CF = OF = high byte != 0)
        DIV  R0, R1      ; R0 = R0 / R1        (R1 != 0)
        INC  R2          ; R2 = 0x10           (AF = 1: carry out of bit 3)
        DEC  R3          ; R3 = 0x00           (ZF = 1)
        DIV  R0, R3      ; divide by zero      -> R0 = 0, OF = 1
        NOP
