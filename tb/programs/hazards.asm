; hazards.asm -- directed test of every hazard case in the 3-stage pipeline.
; Pass: OUT = 0xA5, R0=00 R1=10 R2=10 R3=A5, M[0x10]=0x20.  Fail: OUT = 0xFF.

        LDI  R0, 5
        LDI  R1, 3
        ADD  R0, R1         ; RAW: R0 and R1 both from the instruction just before -> 8
        ADD  R0, R0         ; RAW on both operands, same register -> 16
        ST   R0, [0x10]     ; RAW on store data -> M[10] = 16
        LD   R2, [0x10]     ; load
        ADD  R2, R2         ; load-use (no stall needed) -> 32
        LDI  R3, 0x10
        LDR  R1, [R3]       ; RAW on the address register -> R1 = 16
        STR  R2, [R3]       ; M[10] = 32
        CMP  R2, R1         ; 32 != 16
        BEQ  fail           ; not taken (flags from the instruction just before)
        SUB  R2, R1         ; 16
        CMP  R2, R1         ; equal -> ZF = 1
        BNE  fail           ; not taken
        BEQ  t1             ; taken: the next two instructions must be squashed
        LDI  R0, 0xEE
        LDI  R1, 0xEE
t1:     JMP  t2             ; JMP resolved in ID: next instruction squashed
        LDI  R0, 0xEE
t2:     LDI  R0, 1          ; LDI / JMP leave the flags alone
        BEQ  t3             ; still ZF = 1 -> taken
        HLT
t3:     JMP  t4             ; jump to the very next address
t4:     DEC  R0             ; R0 = 0 -> ZF = 1
        BEQ  t5             ; taken
        JMP  fail
t5:     LDI  R3, 0xA5
        ST   R3, [0xFE]     ; OUT = A5
        HLT
fail:   LDI  R3, 0xFF
        ST   R3, [0xFE]     ; OUT = FF
        HLT
