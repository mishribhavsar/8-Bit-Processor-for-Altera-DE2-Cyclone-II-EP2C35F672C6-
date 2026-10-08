; muldiv_mix.asm -- MUL and DIV per iteration plus independent ALU work
;   acc ^= (200 / i) + (3 * i),  i = 1..N-1
        .equ IN   0xFF
        .equ OUT  0xFE
        LD   R3, [IN]       ; N
        LDI  R0, 0          ; acc
        LDI  R1, 1          ; i
loop:   LDI  R2, 200
        DIV  R2, R1         ; 200 / i
        ADD  R0, R2
        LDI  R2, 3
        MUL  R2, R1         ; 3 * i   (R2 renamed: no WAR/WAW wait on the DIV)
        XOR  R0, R2
        INC  R1
        CMP  R1, R3
        BNE  loop
        ST   R0, [OUT]
        HLT
