#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Derived from Project Cascadia (https://github.com/rzxvx/Project-Cascadia) for LegacyPad-Linux
"""
Regression and functional tests for LwVM dynamic capacity (16GB and 32GB).
"""
import os
import sys
import struct
import unittest
import uuid
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import lwvm
except ImportError:
    # Try sibling Project-Cascadia directory or environment variable if running standalone
    env_path = os.environ.get("CASCADIA_ROOT")
    candidate_paths = [
        os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../../Project-Cascadia/devices/a5/tools/nand-volume")),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../../../Project-Cascadia/devices/a5/tools/nand-volume")),
    ]
    if env_path:
        candidate_paths.insert(0, os.path.join(env_path, "devices/a5/tools/nand-volume"))
    for cp in candidate_paths:
        if os.path.exists(os.path.join(cp, "lwvm.py")):
            sys.path.insert(0, cp)
            break
    import lwvm


def generate_synthetic_32gb():
    """Construct a clean, valid 32GB LwVM stock header for host-only verification."""
    b = bytearray(4096)
    b[:16] = lwvm.MAGIC
    b[16:32] = uuid.uuid4().bytes
    struct.pack_into("<QII", b, 0x20, 32000000000, 2, 0)

    # System: 24576 .. 2252689408 (68 chunks of 32 MiB)
    sys_p = bytearray(128)
    sys_p[:16] = lwvm.HFS_TYPE
    sys_p[16:32] = uuid.uuid4().bytes
    struct.pack_into("<QQQ", sys_p, 32, 24576, 2252689408, 0)
    sys_name = "System".encode("utf-16le")
    sys_p[56 : 56 + len(sys_name)] = sys_name
    b[0x200:0x280] = sys_p

    # Data: 2252689408 .. 31708962816 (878 chunks of 32 MiB)
    data_p = bytearray(128)
    data_p[:16] = lwvm.HFS_TYPE
    data_p[16:32] = uuid.uuid4().bytes
    struct.pack_into("<QQQ", data_p, 32, 2252689408, 31708962816, 0x3000000000000)
    data_name = "Data".encode("utf-16le")
    data_p[56 : 56 + len(data_name)] = data_name
    b[0x280:0x300] = data_p

    # Chunk map: 1 header (0xF000), 68 System (0..67), 878 Data (0..877), 6 FREE (0xF111), 71 PAST (0xF3FF)
    cmap = [0xF3FF] * 1024
    cmap[0] = 0xF000
    for i in range(68):
        cmap[1 + i] = (0 << 12) | i
    for i in range(878):
        cmap[69 + i] = (1 << 12) | i
    for i in range(6):
        cmap[947 + i] = 0xF111
    struct.pack_into("<1024H", b, 0x800, *cmap)

    struct.pack_into("<I", b, 0x2C, zlib.crc32(b) & 0xFFFFFFFF)
    return bytes(b)


class LwvmDynamicTest(unittest.TestCase):
    def setUp(self):
        self.now_path = os.path.join(os.path.dirname(__file__), "../../build/nand-volume/now.bin")
        self.backup32_path = os.path.join(os.path.dirname(__file__), "../../build/nand-volume/backup32.bin")
        self.has_hardware_dumps = os.path.exists(self.now_path) and os.path.exists(self.backup32_path)
        if self.has_hardware_dumps:
            with open(self.now_path, "rb") as f:
                self.now_32_raw = f.read()
            with open(self.backup32_path, "rb") as f:
                self.backup_32_raw = f.read()
        else:
            self.now_32_raw = generate_synthetic_32gb()
            self.backup_32_raw = self.now_32_raw

    def test_now_and_backup32_identical(self):
        """Primary (LBA 0) and backup (LBA 8191) on 32GB must be byte-for-byte identical."""
        self.assertEqual(len(self.now_32_raw), 4096)
        self.assertEqual(len(self.backup_32_raw), 4096)
        self.assertEqual(self.now_32_raw, self.backup_32_raw)

    def test_32gb_header_properties(self):
        """Verify 32GB header structure, chunk sizing, bound, and backup LBA."""
        h = lwvm.Header(self.now_32_raw)
        self.assertTrue(h.crc_ok())
        self.assertEqual(h.media_size, 32000000000)
        self.assertEqual(h.chunk_size, 32 << 20)  # 32 MiB
        self.assertEqual(h.nchunks, 953)
        self.assertEqual(h.bound, 31708962816)
        self.assertEqual(h.backup_lba, 8191)
        self.assertEqual(len(h.parts), 2)
        self.assertEqual(h.parts[0].name, "System")
        self.assertEqual(h.parts[1].name, "Data")
        self.assertEqual(h.parts[0].start, 24576)
        self.assertEqual(h.parts[0].end, 2252689408)
        self.assertEqual(h.parts[1].start, 2252689408)
        self.assertEqual(h.parts[1].end, 31708962816)  # Exactly at bound
        self.assertEqual(h.parts[0].chunks(h.chunk_size), 68)
        self.assertEqual(h.parts[1].chunks(h.chunk_size), 878)
        self.assertEqual(h.free_chunks(), [947, 948, 949, 950, 951, 952])
        lwvm.check_shape(h)

    def test_32gb_plan_create_and_remove(self):
        """Plan creation of an 8GB Linux volume on 32GB, and clean removal."""
        h = lwvm.Header(self.now_32_raw)
        size_8g = 8 << 30
        planned_h, planned_raw, n_blocks = lwvm.plan_create(h, size_8g)
        self.assertEqual(len(planned_h.parts), 3)
        self.assertEqual(planned_h.parts[2].name, "Linux")
        self.assertEqual(planned_h.parts[2].start, 31708962816 - size_8g)
        self.assertEqual(planned_h.parts[2].end, 31708962816)
        self.assertEqual(planned_h.parts[1].end, planned_h.parts[2].start)
        self.assertEqual(planned_h.parts[2].chunks(planned_h.chunk_size), 256)
        self.assertEqual(planned_h.free_chunks(), [947, 948, 949, 950, 951, 952])
        lwvm.check_shape(planned_h)

        # Remove with saved stock header
        restored_h, restored_raw = lwvm.plan_remove(planned_h, saved=self.now_32_raw)
        self.assertEqual(restored_raw, self.now_32_raw)

        # Remove without saved header (by inverse rule)
        restored_inv_h, restored_inv_raw = lwvm.plan_remove(planned_h)
        self.assertEqual(len(restored_inv_h.parts), 2)
        self.assertEqual(restored_inv_h.parts[1].end, 31708962816)
        lwvm.check_shape(restored_inv_h)

    def test_16gb_geometry_regression(self):
        """Ensure 16GB geometry constants and calculations remain unchanged."""
        chunk, nchunks, bound, backup_lba = lwvm.media_geometry(16000000000)
        self.assertEqual(chunk, 16 << 20)
        self.assertEqual(nchunks, 953)
        self.assertEqual(bound, 15854493696)
        self.assertEqual(backup_lba, 4095)
        self.assertEqual(lwvm.BOUND, 15854493696)
        self.assertEqual(lwvm.CHUNK, 16 << 20)
        self.assertEqual(lwvm.MEDIA, 16000000000)

    def test_16gb_synthetic_header_create_remove(self):
        """Construct a valid 16GB stock header and test creation/removal."""
        b = bytearray(4096)
        b[:16] = lwvm.MAGIC
        b[16:32] = uuid.uuid4().bytes
        struct.pack_into("<QII", b, 0x20, 16000000000, 2, 0)  # 16GB media size

        # System: 24576 .. 2224152576 (133 chunks of 16MB)
        sys_p = bytearray(128)
        sys_p[:16] = lwvm.HFS_TYPE
        sys_p[16:32] = uuid.uuid4().bytes
        struct.pack_into("<QQQ", sys_p, 32, 24576, 2224152576, 0)
        sys_name = "System".encode("utf-16le")
        sys_p[56 : 56 + len(sys_name)] = sys_name
        b[0x200:0x280] = sys_p

        # Data: 2224152576 .. 15854493696 (813 chunks of 16MB)
        data_p = bytearray(128)
        data_p[:16] = lwvm.HFS_TYPE
        data_p[16:32] = uuid.uuid4().bytes
        struct.pack_into("<QQQ", data_p, 32, 2224152576, 15854493696, 0x3000000000000)
        data_name = "Data".encode("utf-16le")
        data_p[56 : 56 + len(data_name)] = data_name
        b[0x280:0x300] = data_p

        # Chunk map: 1 header (0xF000), 133 System (0..132), 813 Data (0..812), 6 FREE, 71 PAST
        cmap = [0xF3FF] * 1024
        cmap[0] = 0xF000
        for i in range(133):
            cmap[1 + i] = (0 << 12) | i
        for i in range(813):
            cmap[134 + i] = (1 << 12) | i
        for i in range(6):
            cmap[947 + i] = 0xF111
        struct.pack_into("<1024H", b, 0x800, *cmap)

        # CRC
        struct.pack_into("<I", b, 0x2C, zlib.crc32(b) & 0xFFFFFFFF)
        raw_16 = bytes(b)

        h16 = lwvm.Header(raw_16)
        self.assertEqual(h16.media_size, 16000000000)
        self.assertEqual(h16.chunk_size, 16 << 20)
        self.assertEqual(h16.bound, 15854493696)
        self.assertEqual(h16.backup_lba, 4095)
        lwvm.check_shape(h16)

        # Create 8GB Linux partition on 16GB
        p_h, p_raw, n_blocks = lwvm.plan_create(h16, 8 << 30)
        self.assertEqual(len(p_h.parts), 3)
        self.assertEqual(p_h.parts[2].end, 15854493696)
        self.assertEqual(p_h.parts[2].chunks(p_h.chunk_size), 512)
        lwvm.check_shape(p_h)

        # Remove and restore
        r_h, r_raw = lwvm.plan_remove(p_h, saved=raw_16)
        self.assertEqual(r_raw, raw_16)

    def test_rejection_of_corrupt_and_invalid_headers(self):
        """Verify that Header parser and check_shape strictly reject invalid magic, CRC, and bound violations."""
        # 1. Invalid Magic
        corrupt_magic = bytearray(self.now_32_raw)
        corrupt_magic[0] ^= 0xFF
        with self.assertRaises(lwvm.LwvmError):
            lwvm.Header(bytes(corrupt_magic))

        # 2. Invalid CRC
        corrupt_crc = bytearray(self.now_32_raw)
        corrupt_crc[0x2C] ^= 0xFF
        h_bad_crc = lwvm.Header(bytes(corrupt_crc))
        self.assertFalse(h_bad_crc.crc_ok())
        with self.assertRaises(lwvm.LwvmError):
            lwvm.check_shape(h_bad_crc)

        # 3. Partition range exceeding media bound
        h_bad_bound = lwvm.Header(self.now_32_raw)
        h_bad_bound.parts[1].end = h_bad_bound.bound + (32 << 20)  # 1 chunk past bound
        with self.assertRaises(lwvm.LwvmError):
            lwvm.check_shape(h_bad_bound)

        # 4. Overlapping partitions
        h_overlap = lwvm.Header(self.now_32_raw)
        h_overlap.parts[1].start = h_overlap.parts[0].start + 4096  # overlaps partition 0
        with self.assertRaises(lwvm.LwvmError):
            lwvm.check_shape(h_overlap)

        # 5. Chunk 0 not M_HEADER
        h_bad_c0 = lwvm.Header(self.now_32_raw)
        h_bad_c0.map[0] = 0xF111  # Corrupt chunk 0
        with self.assertRaises(lwvm.LwvmError):
            lwvm.check_shape(h_bad_c0)


if __name__ == "__main__":
    unittest.main()
