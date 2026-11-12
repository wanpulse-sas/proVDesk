"""Exercise the pinned producer with production CLI arguments, without Cargo or signing."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location('verifier', Path(__file__).parents[1] / 'Verify-Package.py')
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


def run(generator):
    with tempfile.TemporaryDirectory(prefix='provdesk-pack-') as directory:
        root = Path(directory)
        payload = root / 'payload with spaces'
        files = {
            'ProVDesk.exe': b'MZ signed fixture',
            'nested/library.dll': b'MZ vendor signature fixture' * 32,
            'data/accents-é.txt': 'Préservation des octets'.encode('utf-8'),
            'data/empty': b'',
        }
        manifest = []
        for name, content in files.items():
            target = payload / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            manifest.append({'Path': name, 'Length': len(content), 'SHA256': hashlib.sha256(content).hexdigest()})
        blob = root / 'data.bin'
        subprocess.run([sys.executable, str(Path(generator).resolve()), '-f', str(payload),
                        '-e', str(payload / 'ProVDesk.exe'), '-l', '11', '--package', str(blob)],
                       check=True, cwd=root)
        manifest_path = root / 'manifest.json'
        manifest_path.write_text(json.dumps(manifest), encoding='utf-8')
        wrapper = root / 'wrapper.exe'
        wrapper.write_bytes(b'MZ fixture prefix' + blob.read_bytes() + b'fixture suffix')
        verifier.verify(blob, manifest_path, wrapper)
        for name, content in files.items():
            assert (payload / name).read_bytes() == content, name


if __name__ == '__main__':
    run(sys.argv[1])
