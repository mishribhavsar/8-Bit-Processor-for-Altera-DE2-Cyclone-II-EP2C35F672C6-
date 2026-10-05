#!/usr/bin/env python3
"""asm.py -- two-pass assembler for the 8-bit RISC processor (16-bit instructions).

Syntax (';' starts a comment, mnemonics/registers are case-insensitive)
    label:                      define a label (code address)
    .equ NAME value             define a constant
    ADD Rd, Rs                  ADD SUB AND OR XOR CMP MUL DIV   (Rd <- Rd op Rs)
    NOT Rd                      NOT LSL LSR ROR ROL INC DEC      (Rd <- op Rd)
    LDI Rd, imm                 Rd <- imm
    LD  Rd, [addr]              Rd <- M[addr]
    ST  Rd, [addr]              M[addr] <- Rd
    LDR Rd, [Rs]                Rd <- M[Rs]
    STR Rd, [Rs]                M[Rs] <- Rd
    JMP target / BEQ target / BNE target
    NOP / HLT
Numbers: 42, 0x2A, 0b101010, or a .equ name / label.
I/O: address 0xFF reads the input port, 0xFE is the output port.

Encoding
    R-type  [15:11] op  [10:9] Rd  [8:7] Rs  [6:0] 0
    I-type  [15:11] op  [10:9] Rd  [8]   0   [7:0] imm8

usage: python3 asm.py program.asm program.hex
"""
import re
import sys

ALU2 = {"ADD": 0x00, "SUB": 0x01, "AND": 0x02, "OR": 0x03, "XOR": 0x04,
        "CMP": 0x06, "MUL": 0x0D, "DIV": 0x0E}
ALU1 = {"NOT": 0x05, "LSL": 0x07, "LSR": 0x08, "ROR": 0x09, "ROL": 0x0A,
        "INC": 0x0B, "DEC": 0x0C}
OTHER = {"NOP": 0x0F, "LDI": 0x10, "LD": 0x11, "ST": 0x12, "LDR": 0x13,
         "STR": 0x14, "JMP": 0x15, "BEQ": 0x16, "BNE": 0x17, "HLT": 0x18}
ROM_WORDS = 256
NOP_WORD = 0x0F << 11


class AsmError(Exception):
    pass


def parse_reg(tok):
    m = re.fullmatch(r"R([0-3])", tok.strip().upper())
    if not m:
        raise AsmError(f"bad register '{tok}' (use R0-R3)")
    return int(m.group(1))


def parse_num(tok, symbols):
    t = tok.strip()
    key = t.upper()
    if key in symbols:
        return symbols[key]
    try:
        v = int(t, 0)
    except ValueError:
        raise AsmError(f"unknown value or label '{t}'")
    if not 0 <= v <= 255:
        raise AsmError(f"value {v} does not fit in 8 bits")
    return v


def strip_brackets(tok):
    t = tok.strip()
    if not (t.startswith("[") and t.endswith("]")):
        raise AsmError(f"expected [address], got '{t}'")
    return t[1:-1]


def tokenize(lines):
    """Yield (lineno, label_or_None, mnemonic_or_None, args, source)."""
    for n, raw in enumerate(lines, 1):
        text = raw.split(";", 1)[0].strip()
        if not text:
            continue
        label = None
        m = re.match(r"^([A-Za-z_]\w*):\s*(.*)$", text)
        if m:
            label, text = m.group(1), m.group(2).strip()
        if not text:
            yield n, label, None, [], raw.rstrip()
            continue
        parts = text.split(None, 1)
        mnem = parts[0].upper()
        args = [a.strip() for a in parts[1].split(",")] if len(parts) > 1 else []
        yield n, label, mnem, args, raw.rstrip()


def assemble(lines):
    symbols, items, pc = {}, [], 0
    # pass 1: addresses and symbols
    for n, label, mnem, args, src in tokenize(lines):
        try:
            if label:
                if label.upper() in symbols:
                    raise AsmError(f"duplicate symbol '{label}'")
                symbols[label.upper()] = pc
            if mnem is None:
                continue
            if mnem == ".EQU":
                if len(args) != 1 or len(args[0].split()) != 2:
                    raise AsmError(".equ NAME value")
                name, val = args[0].split()
                symbols[name.upper()] = parse_num(val, symbols)
                continue
            items.append((n, pc, mnem, args, src))
            pc += 1
        except AsmError as e:
            sys.exit(f"line {n}: {e}")
    if pc > ROM_WORDS:
        sys.exit(f"program has {pc} instructions; ROM holds {ROM_WORDS}")

    # pass 2: encode
    words, listing = [], []
    for n, addr, mnem, args, src in items:
        try:
            def need(k):
                if len(args) != k:
                    raise AsmError(f"{mnem} takes {k} operand(s)")
            rd = rs = imm = 0
            if mnem in ALU2:
                need(2); op = ALU2[mnem]
                rd, rs = parse_reg(args[0]), parse_reg(args[1])
            elif mnem in ALU1:
                need(1); op = ALU1[mnem]; rd = parse_reg(args[0])
            elif mnem in ("NOP", "HLT"):
                need(0); op = OTHER[mnem]
            elif mnem == "LDI":
                need(2); op = OTHER[mnem]
                rd, imm = parse_reg(args[0]), parse_num(args[1], symbols)
            elif mnem in ("LD", "ST"):
                need(2); op = OTHER[mnem]
                rd, imm = parse_reg(args[0]), parse_num(strip_brackets(args[1]), symbols)
            elif mnem in ("LDR", "STR"):
                need(2); op = OTHER[mnem]
                rd, rs = parse_reg(args[0]), parse_reg(strip_brackets(args[1]))
            elif mnem in ("JMP", "BEQ", "BNE"):
                need(1); op = OTHER[mnem]; imm = parse_num(args[0], symbols)
            else:
                raise AsmError(f"unknown mnemonic '{mnem}'")
        except AsmError as e:
            sys.exit(f"line {n}: {e}")
        word = (op << 11) | (rd << 9) | (rs << 7) | imm
        words.append(word)
        listing.append(f"{addr:02X}: {word:04X}   {src.strip()}")
    words += [NOP_WORD] * (ROM_WORDS - len(words))
    return words, listing


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1]) as f:
        words, listing = assemble(f.readlines())
    with open(sys.argv[2], "w") as f:
        f.write("\n".join(f"{w:04X}" for w in words) + "\n")
    print("\n".join(listing))
    print(f"-> {sys.argv[2]} ({len(listing)} instructions, rest NOP)")


if __name__ == "__main__":
    main()
