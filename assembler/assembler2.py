# flake8: noqa

import argparse
import json
from io import TextIOWrapper
from pathlib import Path

current_line = 0


def is_comment(line: str):
    return line.startswith(';') or line.startswith('#')


def int_to_hex(num: int) -> str:
    if num > 0xFFFF:
        raise ValueError(f'Value is larger than 16 bits, line {current_line}')
    return hex(num).lstrip('0x')


def int_to_bin(num: int) -> str:
    return bin(num).lstrip('0b')


def parse_data(word: str):
    raw_num = word
    # parse hex number
    if raw_num.endswith('h'):
        raw_num = '0x' + raw_num.rstrip('h')
    val: int
    try:
        val = int(raw_num, base=0)
    except ValueError:
        raise SyntaxError(
            f'Expected numerical argument got {word}, line {current_line}'
        )

    return int_to_hex(val)


def read_data_section(file: TextIOWrapper) -> list[str]:
    global current_line

    data_list = []
    data_mapping = {}

    for line in file:
        line = line.lower()

        # end of section
        if line.startswith('.'):
            break

        # split on whitespace
        words = line.split()
        if len(words) > 0 and not is_comment(words[0]):
            word = words[0]
            if len(words) >= 2:
                word = words[1]
                data_mapping[word[0]] = len(data_list)
            value = parse_data(word)
            data_list.append(value)

        current_line += 1

    return data_list, data_mapping


def parse_reg(reg: str) -> str:
    if not reg.startswith('r'):
        raise SyntaxError(
            f'Expected register definition got {reg}, ' + f'line {current_line}'
        )

    num = int(reg.lstrip('r'))

    if num not in range(0, 8):
        raise ValueError(
            f'Expected register number in range [0,7], ' + f'line {current_line}'
        )

    num = bin(num).lstrip('0b')

    return f'{num:0>3}'


def parse_num(str_num: str) -> str:
    raw_num = str_num
    if raw_num.endswith('h'):
        raw_num = '0x' + raw_num.rstrip('h')
    return raw_num


def parse_instruction(words: list[str], isa: dict[str, list[str]]) -> list[str]:
    try:
        instr = isa.get(words[0])
    except KeyError:
        raise SyntaxError(f'Unknown instruction {words[0]}, ' + f'line {current_line}')

    if len(words) < len(instr):
        raise SyntaxError(
            f'Expected {len(instr) - 1} operands got {words[1:]}, '
            + f'line {current_line}'
        )

    instr_binary: list[str] = ['0b', instr[0], '', '', '']
    for idx, action in enumerate(instr[1:]):
        if action == 'dst':
            instr_binary[2] = parse_reg(words[idx + 1])
        elif action == 'src':
            instr_binary[3] = parse_reg(words[idx + 1])
        elif action == 'sh':
            raw_num = parse_num(words[idx + 1])
            num = int(raw_num, base=0)
            if num > 0xFF:
                raise SyntaxError('shift amount cannot be greater than 8 bits')
            instr_binary[4] = f'{int_to_bin(num):0>8}'
        elif action == 'load':
            raw_num = parse_num(words[idx + 1])
            instr_str: str = ''.join(instr_binary)
            return [
                int_to_hex(int(f'{instr_str:0<18}', base=0)),
                int_to_hex(int(raw_num, base=0)),
            ]

    instr_str: str = ''.join(instr_binary)
    return [int_to_hex(int(f'{instr_str:0<18}', base=0))]


def read_code_section(
    file: TextIOWrapper, isa: dict[str, list[str]], pad: bool
) -> list[str]:
    global current_line

    code_list = []

    nop_padding = parse_instruction(['nop'], isa) * 4

    for line in file:
        line = line.lower()

        # end of section
        if line.startswith('.'):
            break

        # remove commas then split on whitespace
        words = line.replace(',', ' ').split()
        if len(words) > 0 and not is_comment(words[0]):
            code_list.extend(parse_instruction(words, isa))
            if pad:
                code_list.extend(nop_padding)

        current_line += 1

    return code_list


def main():
    parser = argparse.ArgumentParser(
        description="Assembler",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("src", help="Source location")
    parser.add_argument(
        "-z",
        "--no-hazards",
        action="store_true",
        help="Assemble in no hazards mode."
        + "This will insert 4 NOP instructions after each instruction",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="increase verbosity"
    )
    args = parser.parse_args()
    config = vars(args)
    file_path = Path(config['src'])
    file_name = file_path.name.split('.')[0]

    with open('isa.json') as isa_file:
        isa = json.loads(isa_file.read())

    with open(file_path) as file:
        global current_line
        # find data section
        for line in file:
            line = line.lower()
            if line.startswith('.data'):
                break

            current_line += 1

        # fill data
        data, _ = read_data_section(file)
        with open(file_name + '_data.txt', 'w') as data_file:
            for hex_num in data:
                data_file.write(f'{hex_num:0>4}\n')

        file.seek(0)
        current_line = 0

        # find interrupt section
        for line in file:
            line = line.lower()
            if line.startswith('.interrupt') or line.startswith('.org 0'):
                break

            current_line += 1

        # fill interrupt
        interrupt_code = read_code_section(file, isa, config['no_hazards'])
        if len(interrupt_code) > 32:
            raise MemoryError('Interrupt code size may not exceed 32 words')

        with open(file_name + '_code.txt', 'w') as code_file:
            for hex_num in interrupt_code:
                code_file.write(f'{hex_num:0>4}\n')
            for _ in range(32 - len(interrupt_code)):
                code_file.write('0\n')

        file.seek(0)
        current_line = 0

        # find code section
        for line in file:
            line = line.lower()
            if line.startswith('.code') or line.startswith('.org 20'):
                break

            current_line += 1

        # fill code
        code = read_code_section(file, isa, config['no_hazards'])
        with open(file_name + '_code.txt', 'a') as code_file:
            for hex_num in code:
                code_file.write(f'{hex_num:0>4}\n')


if __name__ == '__main__':
    main()
