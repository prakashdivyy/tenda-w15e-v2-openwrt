# Patching `squashfs-tools` for Tenda Customized Firmware

This guide documents the exact modifications required to compile a patched version of `unsquashfs` (`squashfs-tools`) capable of extracting vendor-obfuscated SquashFS root filesystems found in **Tenda** routers (such as the **Tenda W15E v2.0**, AC-series, and AX-series).

---

## 1. Background: Tenda's SquashFS Modifications

Tenda applies three specific alterations to the standard SquashFS 4.0 format to deter automated extraction tools (like standard `binwalk` and upstream `unsquashfs`):

1. **Superblock Magic Bytes Replacement:**
   * Standard SquashFS magic: `0x73717368` (`sqsh`) or `0x68737173` (`hsqs`).
   * Tenda custom magic: `0x6563696e` / `0x6e696365` (ASCII string `"nice"`).

2. **Custom Compressor Options Struct Length:**
   * Standard `struct comp_opts` for XZ is 8 bytes (`dictionary_size` + `flags`).
   * Tenda uses a 12-byte header, causing standard `unsquashfs` to fail with:
     ```text
     xz: error reading stored compressor options from filesystem!
     ```

3. **XZ Stream Header Magic Replacement:**
   * Standard XZ stream header: 6 bytes `\xFD7zXZ\x00`.
   * Tenda custom stream header: 6 bytes `Tenda\x00`.
   * Tenda's toolchain alters internal CRC verification, causing standard `lzma_stream_buffer_decode` to reject blocks with `LZMA_DATA_ERROR` (code 9).

---

## 2. Prerequisites

### macOS (Homebrew)
```bash
brew install xz
```
* Include headers: `/opt/homebrew/include`
* Library link path: `/opt/homebrew/lib`

### Debian / Ubuntu
```bash
sudo apt-get update
sudo apt-get install build-essential liblzma-dev zlib1g-dev git
```

---

## 3. Clone `squashfs-tools`

```bash
git clone --depth 1 https://github.com/plougher/squashfs-tools.git
cd squashfs-tools/squashfs-tools
```

---

## 4. Required Patches

### Patch 1: `squashfs_fs.h` (Magic Bytes)

Locate lines 30–31 in `squashfs_fs.h`:

```c
/* Original */
#define SQUASHFS_MAGIC			0x73717368
#define SQUASHFS_MAGIC_SWAP		0x68737173
```

Replace with:

```c
/* Tenda "nice" Magic Bytes */
#define SQUASHFS_MAGIC			0x6563696e
#define SQUASHFS_MAGIC_SWAP		0x6e696365
```

---

### Patch 2: `xattr.h` (Compilation Fix for `XATTR_SUPPORT=0`)

When compiling without extended attributes on macOS, `xattr.h` in some releases references an undeclared `read_fs_bytes`. Locate `read_xattrs_from_disk`:

```c
static inline unsigned int read_xattrs_from_disk(int fd, struct squashfs_super_block *sBlk, int sanity_only, long long *table_start)
{
	return 0;
}
```
*(Ensure the function body simply returns `0;` to avoid undefined symbol errors).*

---

### Patch 3: `xz_wrapper.c` (Compressor Options & Custom Block Decoding)

#### A. Allow 12-byte compressor options
In `xz_extract_options()` around line 313, change:

```c
/* Original */
if(size != sizeof(struct comp_opts))
    goto failed;
```

To:

```c
/* Allow Tenda 12-byte comp_opts */
if(size < 8)
    goto failed;
```

#### B. Handle `Tenda\0` XZ blocks and bypass payload CRC
Replace `static int xz_uncompress(...)` around line 517 with:

```c
static int xz_uncompress(void *dest, void *src, int size, int outsize, int *error)
{
	uint8_t *s = (uint8_t *) src;

	/* Detect Tenda custom XZ stream header */
	if (size > 28 && memcmp(s, "Tenda\0", 6) == 0) {
		lzma_filter filters[5];
		lzma_block block;
		memset(&block, 0, sizeof(block));
		memset(filters, 0, sizeof(filters));
		block.filters = filters;
		block.check = LZMA_CHECK_CRC32;
		block.header_size = (s[12] + 1) * 4;

		/* Recompute block header CRC32 using liblzma */
		uint32_t c_bh = lzma_crc32(s + 12, block.header_size - 4, 0);
		s[12 + block.header_size - 4] = c_bh & 0xff;
		s[12 + block.header_size - 3] = (c_bh >> 8) & 0xff;
		s[12 + block.header_size - 2] = (c_bh >> 16) & 0xff;
		s[12 + block.header_size - 1] = (c_bh >> 24) & 0xff;

		lzma_ret ret = lzma_block_header_decode(&block, NULL, s + 12);
		if (ret != LZMA_OK) {
			*error = ret;
			return -1;
		}

		/* Bypass altered payload check */
		block.check = LZMA_CHECK_NONE;

		lzma_stream strm = LZMA_STREAM_INIT;
		ret = lzma_block_decoder(&strm, &block);
		if (ret != LZMA_OK) {
			*error = ret;
			return -1;
		}

		strm.next_in = s + 12 + block.header_size;
		strm.avail_in = block.compressed_size;
		strm.next_out = (uint8_t *) dest;
		strm.avail_out = outsize;

		ret = lzma_code(&strm, LZMA_FINISH);
		size_t written = strm.total_out;
		lzma_end(&strm);

		if (ret == LZMA_OK || ret == LZMA_STREAM_END) {
			return (int) written;
		} else {
			*error = ret;
			return -1;
		}
	}

	/* Fallback standard XZ decompression */
	size_t src_pos = 0;
	size_t dest_pos = 0;
	uint64_t memlimit = MEMLIMIT;

	lzma_ret res = lzma_stream_buffer_decode(&memlimit, 0, NULL,
			src, &src_pos, size, dest, &dest_pos, outsize);

	if(res == LZMA_OK && size == (int) src_pos)
		return (int) dest_pos;
	else {
		*error = res;
		return -1;
	}
}
```

---

## 5. Compilation

### On macOS (Apple Silicon):
```bash
make clean
make GZIP_SUPPORT=1 XZ_SUPPORT=1 LZO_SUPPORT=0 LZ4_SUPPORT=0 ZSTD_SUPPORT=0 XATTR_SUPPORT=0 \
     EXTRA_CFLAGS="-I/opt/homebrew/include" EXTRA_LDFLAGS="-L/opt/homebrew/lib" \
     unsquashfs
```

### On Linux (x86_64 / Debian / Ubuntu):
```bash
make clean
make GZIP_SUPPORT=1 XZ_SUPPORT=1 LZO_SUPPORT=0 LZ4_SUPPORT=0 ZSTD_SUPPORT=0 XATTR_SUPPORT=0 \
     unsquashfs
```

---

## 6. Extracting the Root Filesystem

1. **Carve the SquashFS partition slice** from the firmware binary starting at offset `1139041` (`0x116161`):
   ```bash
   tail -c +1139042 "US_W15EV2.0qu_V16.01.0.11(3317)_CN&EN_TDE01.bin" > rootfs.squashfs
   ```

2. **Verify superblock with your patched `unsquashfs`:**
   ```bash
   ./unsquashfs -s rootfs.squashfs
   ```

3. **List files:**
   ```bash
   ./unsquashfs -l rootfs.squashfs
   ```

4. **Extract entire filesystem:**
   ```bash
   ./unsquashfs -d ./extracted_rootfs rootfs.squashfs
   ```
