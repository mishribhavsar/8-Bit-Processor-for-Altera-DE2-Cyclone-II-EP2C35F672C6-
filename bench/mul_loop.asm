; mul_loop.asm -- latency-bound loop: acc = sum of 7*i, i = 1..N-1
; Each iteration's MUL is independent of the previous one; only the ADD
; into the accumulator depends on it. An in-order pipeline stalls for the
; full MUL latency every iteration; the out-of-order core keeps fetching,
; renames R2 and overlaps the loop overhead with the multiply.
        .equ IN   0xFF
        .equ OUT  0xFE
        LD   R3, [IN]       ; N
        LDI  R0, 0          ; acc
        LDI  R1, 1          ; i
loop:   LDI  R2, 7
        MUL  R2, R1         ; t = 7 * i        (9-cycle unit)
        ADD  R0, R2         ; acc += t
        INC  R1
        CMP  R1, R3
        BNE  loop
        ST   R0, [OUT]
        HLT
