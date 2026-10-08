; alu_loop.asm control-heavy loop with no MUL/DIV (sum of 1..N with a table)
; same kernel as mem/program.asm, used as the no-latency baseline
        .equ IN     0xFF
        .equ OUT    0xFE
        .equ TABLE  0x20
        LD   R1, [IN]
        LDI  R0, 0
        LDI  R3, TABLE
        LDI  R2, 0
        CMP  R1, R2
        BEQ  done
loop:   ADD  R0, R1
        STR  R0, [R3]
        INC  R3
        DEC  R1
        BNE  loop
done:   ST   R0, [OUT]
        HLT
