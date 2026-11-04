#!/usr/bin/env python3
"""
wrap_tenda_firmware.py

Encapsulates a standard OpenWrt uImage/sysupgrade binary with Tenda's proprietary
64-byte U-Boot wrapper header expected by the stock Tenda web management interface.

Header Structure:
  - Offset 0..3:   Magic (0x27051956)
  - Offset 4..7:   Header CRC32 (calculated over header with hcrc=0)
  - Offset 8..11:  Timestamp (Unix epoch)
  - Offset 12..15: Data size (payload size in bytes)
  - Offset 16..19: Load Address (0x80000000)
  - Offset 20..23: Entry Point (0x802b03e0)
  - Offset 24..27: Data CRC32
  - Offset 28:     OS Type (5 = Linux)
  - Offset 29:     Arch (5 = MIPS)
  - Offset 30:     Image Type (2 = Kernel)
  - Offset 31:     Compression (3 = LZMA)
  - Offset 32..63: 32-byte Name field with Tenda vendor metadata:
                   [0..3]   = 0x02, 0x00, 0x00, 0x00 (Hardware ID: 2)
                   [4..7]   = 0x01, 0x01, 0x10, 0x60 (Version metadata)
                   [8..11]  = Total file size (little-endian uint32)
                   [12..15] = 0x00, 0x00, 0x00, 0x00
                   [16..31] = b"Tenda_upgrade\\x00\\x00\\x00"
"""

import sys
import struct
import time
import zlib
import os

def wrap_image(input_file, output_file):
    if not os.path.isfile(input_file):
        print(f"Error: input file {input_file} not found.")
        sys.exit(1)

    with open(input_file, "rb") as f:
        payload = f.read()

    payload_size = len(payload)
    total_file_size = payload_size + 64
    dcrc = zlib.crc32(payload) & 0xffffffff
    now = int(time.time())

    # Build 32-byte name field
    hw_id = struct.pack("<I", 2)
    ver_tag = bytes([1, 1, 0x10, 0x60])
    total_sz = struct.pack("<I", total_file_size)
    reserved = bytes(4)
    sig = b"Tenda_upgrade\x00\x00\x00"
    name_field = hw_id + ver_tag + total_sz + reserved + sig
    assert len(name_field) == 32, f"Name field length error: {len(name_field)}"

    magic = 0x27051956
    load_addr = 0x80000000
    ep = 0x802b03e0
    os_type = 5   # Linux
    arch = 5      # MIPS
    img_type = 2  # Kernel
    comp = 3      # LZMA

    # Header with CRC = 0 for calculation
    dummy_header = struct.pack(
        ">IIIIIIIBBBB32s",
        magic, 0, now, payload_size, load_addr, ep, dcrc,
        os_type, arch, img_type, comp, name_field
    )

    hcrc = zlib.crc32(dummy_header) & 0xffffffff

    final_header = struct.pack(
        ">IIIIIIIBBBB32s",
        magic, hcrc, now, payload_size, load_addr, ep, dcrc,
        os_type, arch, img_type, comp, name_field
    )

    with open(output_file, "wb") as f:
        f.write(final_header)
        f.write(payload)

    print(f"Successfully wrapped {input_file} -> {output_file}")
    print(f"  Payload size:    {payload_size} bytes")
    print(f"  Total file size: {total_file_size} bytes")
    print(f"  Header CRC:      {hex(hcrc)}")
    print(f"  Data CRC:        {hex(dcrc)}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: wrap_tenda_firmware.py <input.bin> <output_wrapped.bin>")
        sys.exit(1)
    wrap_image(sys.argv[1], sys.argv[2])
