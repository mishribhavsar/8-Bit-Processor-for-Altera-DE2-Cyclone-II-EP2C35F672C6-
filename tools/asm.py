#!/usr/bin/env python3
"""asm.py -- tiny assembler for the 8-bit single-cycle processor.

Syntax (one instruction per line, ';' starts a comment, case-insensitive):
    ADD Rd, Rs      two-operand:  Rd <- Rd op Rs   (ADD SUB AND OR XOR CMP MUL DIV)
    NOT Rd          one-operand:  Rd <- op Rd      (NOT LSL LSR ROR ROL INC DEC)
    NOP

Encoding: [7:4] opcode  [3:2] Rs  [1:0] Rd
Output:   256 lines of 2-digit hex for $readmemh; unused words are NOP (F0).

usage: python3 asm.py program.asm program.hex
"""
import re
import sys

OPCODES = {
    "ADD": 0x0, "SUB": 0x1, "AND": 0x2, "OR": 0x3, "XOR": 0x4, "NOT": 0x5,
    "CMP": 0x6, "LSL": 0x7, "LSR": 0x8, "ROR": 0x9, "ROL": 0xA, "INC": 0xB,
    "DEC": 0xC, "MUL": 0xD, "DIV": 0xE, "NOP": 0xF,
}
TWO_OP = {"ADD", "SUB", "AND", "OR", "XOR", "CMP", "MUL", "DIV"}
ONE_OP = {"NOT", "LSL", "LSR", "ROR", "ROL", "INC", "DEC"}
ROM_WORDS = 256
NOP_WORD = 0xF0


def reg(tok, lineno):
    m = re.fullmatch(r"R([0-3])", tok.strip().upper())
    if not m:
        sys.exit(f"line {lineno}: bad register '{tok}' (use R0-R3)")
    return int(m.group(1))


def assemble(lines):
    words, listing = [], []
    for lineno, raw in enumerate(lines, 1):
        text = raw.split(";", 1)[0].strip()
        if not text:
            continue
        parts = text.replace(",", " ").split()
        mnem, args = parts[0].upper(), parts[1:]
        if mnem not in OPCODES:
            sys.exit(f"line {lineno}: unknown mnemonic '{parts[0]}'")
        if mnem in TWO_OP:
            if len(args) != 2:
                sys.exit(f"line {lineno}: {mnem} needs Rd, Rs")
            rd, rs = reg(args[0], lineno), reg(args[1], lineno)
        elif mnem in ONE_OP:
            if len(args) != 1:
                sys.exit(f"line {lineno}: {mnem} needs Rd")
            rd, rs = reg(args[0], lineno), 0
        else:  # NOP
            if args:
                sys.exit(f"line {lineno}: NOP takes no operands")
            rd, rs = 0, 0
        word = (OPCODES[mnem] << 4) | (rs << 2) | rd
        listing.append(f"{len(words):02X}: {word:02X}   {text}")
        words.append(word)
    if len(words) > ROM_WORDS:
        sys.exit(f"program has {len(words)} words; ROM holds {ROM_WORDS}")
    words += [NOP_WORD] * (ROM_WORDS - len(words))
    return words, listing


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1]) as f:
        words, listing = assemble(f.readlines())
    with open(sys.argv[2], "w") as f:
        f.write("\n".join(f"{w:02X}" for w in words) + "\n")
    print("\n".join(listing))
    print(f"-> {sys.argv[2]} ({len(listing)} instructions, rest NOP)")


if __name__ == "__main__":
    main()
