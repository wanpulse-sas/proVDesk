import hashlib
import importlib.util
import json
import struct
import tempfile
import unittest
from pathlib import Path

import brotli

spec = importlib.util.spec_from_file_location('verify_package', Path(__file__).parents[1] / 'Verify-Package.py')
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class PackageTests(unittest.TestCase):
    def test_signed_bytes_and_failures(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            content = b'fake signed PE bytes'
            name = b'.\\ProVDesk.exe'
            compressed = brotli.compress(content)
            blob = (b'rustdesk' + struct.pack('>I', len(name)) + name +
                    struct.pack('>I', len(compressed)) + compressed +
                    hashlib.md5(content).hexdigest().encode() + b'rustdesk.\\ProVDesk.exe')
            (root / 'data.bin').write_bytes(blob)
            (root / 'final.exe').write_bytes(b'MZ-placeholder' + blob + b'signature-placeholder')
            manifest = [{'Path': 'ProVDesk.exe', 'Length': len(content), 'SHA256': hashlib.sha256(content).hexdigest()}]
            (root / 'manifest.json').write_text(json.dumps(manifest))
            args = [root / name for name in ('data.bin', 'manifest.json', 'final.exe')]
            verifier.verify(*args)
            (root / 'final.exe').write_bytes(b'MZ-old-wrapper')
            with self.assertRaisesRegex(ValueError, 'not embedded'):
                verifier.verify(*args)
            (root / 'final.exe').write_bytes(blob)
            manifest[0]['SHA256'] = '0' * 64
            (root / 'manifest.json').write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'differs'):
                verifier.verify(*args)
            manifest.append({'Path': 'missing.dll', 'Length': 0, 'SHA256': ''})
            manifest[0]['SHA256'] = hashlib.sha256(content).hexdigest()
            (root / 'manifest.json').write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'Missing'):
                verifier.verify(*args)


if __name__ == '__main__':
    unittest.main()
