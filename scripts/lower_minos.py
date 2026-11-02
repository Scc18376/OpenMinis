#!/usr/bin/env python3
"""把目录下所有 Mach-O 的 minos 降到目标版本"""
import sys, os, struct

TARGET = sys.argv[2] if len(sys.argv) > 2 else '14.3'
root = sys.argv[1]

def vhex(s):
    p = [int(x) for x in s.split('.')]
    while len(p) < 3: p.append(0)
    return (p[0] << 16) | (p[1] << 8) | p[2]

TV = vhex(TARGET)
n_patched = 0
n_files = 0

for d, _, fs in os.walk(root):
    for fn in fs:
        p = os.path.join(d, fn)
        try:
            data = bytearray(open(p, 'rb').read())
        except Exception:
            continue
        if len(data) < 32:
            continue
        magic = struct.unpack('<I', data[:4])[0]
        if magic not in (0xfeedface, 0xfeedfacf):
            continue
        is64 = magic == 0xfeedfacf
        ncmds = struct.unpack('<I', data[16:20])[0]
        off = 32 if is64 else 28
        hit = 0
        for _ in range(ncmds):
            if off + 8 > len(data):
                break
            cmd, cmdsize = struct.unpack('<II', data[off:off + 8])
            if cmdsize == 0:
                break
            if cmd == 0x32:      # LC_BUILD_VERSION
                data[off + 12:off + 16] = struct.pack('<I', TV)
                hit += 1
            elif cmd == 0x25:    # LC_VERSION_MIN_IPHONEOS
                data[off + 8:off + 12] = struct.pack('<I', TV)
                hit += 1
            off += cmdsize
        if hit:
            open(p, 'wb').write(data)
            n_files += 1
            n_patched += hit

print(f'[minos] {n_files} 个 Mach-O / {n_patched} 处 -> {TARGET}')
