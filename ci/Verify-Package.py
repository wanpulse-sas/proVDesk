"""Verify the pinned fork's data.bin format and its inclusion in the wrapper."""
import hashlib
import json
import struct
import sys
from pathlib import Path

import brotli


def verify(blob_path, manifest_path, exe_path):
    blob = Path(blob_path).read_bytes()
    expected = {item['Path']: item for item in json.loads(Path(manifest_path).read_text(encoding='utf-8-sig'))}
    if not blob.startswith(b'rustdesk'):
        raise ValueError('Invalid package header')
    offset = 8
    seen = set()
    while blob[offset:offset + 8] != b'rustdesk':
        name_length = struct.unpack_from('>I', blob, offset)[0]
        offset += 4
        name = blob[offset:offset + name_length].decode('utf-8').replace('\\', '/')
        offset += name_length
        if name.startswith('./'):
            name = name[2:]
        if name not in expected or name in seen:
            raise ValueError(f'Unexpected or duplicate file: {name}')
        size = struct.unpack_from('>I', blob, offset)[0]
        offset += 4
        content = brotli.decompress(blob[offset:offset + size])
        offset += size
        md5 = blob[offset:offset + 32].decode('ascii')
        offset += 32
        if hashlib.md5(content).hexdigest() != md5:
            raise ValueError(f'Corrupt package checksum: {name}')
        if len(content) != expected[name]['Length'] or hashlib.sha256(content).hexdigest().upper() != expected[name]['SHA256'].upper():
            raise ValueError(f'Package differs from payload manifest: {name}')
        seen.add(name)
    if seen != set(expected):
        raise ValueError('Missing payload files')
    entrypoint = blob[offset + 8:].decode('utf-8').replace('\\', '/')
    if entrypoint != './ProVDesk.exe':
        raise ValueError(f'Unexpected entrypoint: {entrypoint}')
    if blob not in Path(exe_path).read_bytes():
        raise ValueError('Verified payload not embedded in wrapper')
    print(f'Package verified: {len(seen)} files, exact manifest bytes embedded.')


if __name__ == '__main__':
    verify(*sys.argv[1:])
