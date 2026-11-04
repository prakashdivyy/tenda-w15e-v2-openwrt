#!/usr/bin/env python3
"""
dump_art_extractor.py

Extracts and verifies the 64 KB Atheros Radio Test (ART) wireless calibration partition
from a full 16 MB flash dump of the Tenda W15E v2.0 router.
"""

import sys
import os

ART_SIZE = 64 * 1024       # 65536 bytes (64 KB)
FLASH_SIZE = 16 * 1024 * 1024 # 16777216 bytes (16 MB)
DEFAULT_ART_OFFSET = FLASH_SIZE - ART_SIZE # 0xff0000

def extract_art(dump_path, output_path="art_backup.bin", offset=DEFAULT_ART_OFFSET):
    if not os.path.isfile(dump_path):
        print(f"Error: File {dump_path} does not exist.")
        sys.exit(1)

    file_size = os.path.getsize(dump_path)
    if file_size < ART_SIZE:
        print(f"Error: Dump file is smaller than ART partition size ({file_size} bytes).")
        sys.exit(1)

    with open(dump_path, "rb") as f:
        if file_size == FLASH_SIZE:
            f.seek(offset)
            art_data = f.read(ART_SIZE)
        elif file_size == ART_SIZE:
            print("Notice: Input file is already 64 KB; treating as standalone ART partition.")
            art_data = f.read(ART_SIZE)
        else:
            print(f"Notice: Non-standard flash dump size ({file_size} bytes). Slicing last 64 KB.")
            f.seek(file_size - ART_SIZE)
            art_data = f.read(ART_SIZE)

    # Basic Atheros calibration check
    # 2.4 GHz ath9k calibration usually resides at offset 0x1000 within ART
    cal_2g = art_data[0x1000:0x1020]
    print("ART Header preview (first 16 bytes):", art_data[:16].hex())
    print("2.4G Calibration data preview (offset 0x1000):", cal_2g.hex())

    with open(output_path, "wb") as f_out:
        f_out.write(art_data)

    print(f"\n[+] Successfully saved 64 KB ART partition to: {output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: dump_art_extractor.py <full_flash_dump.bin> [output_art.bin]")
        sys.exit(1)

    out_file = sys.argv[2] if len(sys.argv) > 2 else "art_backup.bin"
    extract_art(sys.argv[1], out_file)
