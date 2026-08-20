#!/usr/bin/env python3
"""Inject LC_LOAD_DYLIB into a Mach-O arm64 binary."""
import struct
import sys

def inject(binary_path, dylib_path):
    with open(binary_path, 'rb') as f:
        data = bytearray(f.read())

    magic = struct.unpack('<I', data[0:4])[0]
    if magic != 0xfeedfacf:
        print(f'Error: unexpected magic {hex(magic)}, expected 0xfeedfacf (arm64)')
        sys.exit(1)

    ncmds = struct.unpack('<I', data[16:20])[0]
    sizeofcmds = struct.unpack('<I', data[20:24])[0]

    lc_offset = 32
    cs_cmd_offset = None
    for i in range(ncmds):
        cmd = struct.unpack('<I', data[lc_offset:lc_offset+4])[0]
        cmdsize = struct.unpack('<I', data[lc_offset+4:lc_offset+8])[0]
        if cmd == 0x1d:
            cs_cmd_offset = lc_offset
        lc_offset += cmdsize

    if cs_cmd_offset is None:
        print('Error: LC_CODE_SIGNATURE not found')
        sys.exit(1)

    dylib_bytes = dylib_path.encode('utf-8') + b'\x00'
    padding = (4 - (len(dylib_bytes) % 4)) % 4
    dylib_bytes_padded = dylib_bytes + b'\x00' * padding
    cmdsize = 8 + len(dylib_bytes_padded)
    lc_load_dylib = struct.pack('<II', 12, cmdsize) + dylib_bytes_padded

    new_data = data[:cs_cmd_offset] + lc_load_dylib + data[cs_cmd_offset:]
    new_sizeofcmds = sizeofcmds + len(lc_load_dylib)
    new_ncmds = ncmds + 1
    new_data[16:20] = struct.pack('<I', new_ncmds)
    new_data[20:24] = struct.pack('<I', new_sizeofcmds)

    with open(binary_path, 'wb') as f:
        f.write(new_data)
    print(f'Injected {dylib_path} into {binary_path}')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f'Usage: {sys.argv[0]} <binary> <dylib_path>')
        sys.exit(1)
    inject(sys.argv[1], sys.argv[2])
