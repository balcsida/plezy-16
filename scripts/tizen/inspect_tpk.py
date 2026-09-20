#!/usr/bin/env python3
"""Fail-closed TPK structure/ABI/secret check; not a signature or TV-runtime verifier."""
import argparse
import hashlib
import json
import struct
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path, PurePosixPath


def inspect(package):
    with zipfile.ZipFile(package) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate ZIP entries')
        total = 0
        elves = []
        for entry in archive.infolist():
            path = PurePosixPath(entry.filename)
            if path.is_absolute() or '..' in path.parts or '\\' in entry.filename:
                raise ValueError('Unsafe ZIP path')
            if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Symlink in package')
            if path.suffix.lower() in {'.p12', '.pfx', '.key', '.pem', '.log'} or path.name.lower() == 'profiles.xml':
                raise ValueError('Signing material or logs in package')
            if any(part in {'.git', '.tizen-signing', '.dart_tool', 'node_modules'} for part in path.parts):
                raise ValueError('Development directory in package')
            if path.name in {'kernel_blob.bin', 'vm_snapshot_data', 'isolate_snapshot_data'}:
                raise ValueError('JIT/debug assets in release package')
            if path.name.startswith('libsqlite3') and '.so' in path.name:
                raise ValueError('Unexpected SQLite FFI asset; Tizen must use sqflite')
            total += entry.file_size
            if entry.file_size > 512 * 1024 * 1024 or total > 2 * 1024 * 1024 * 1024:
                raise ValueError('Package exceeds inspection limits')
            with archive.open(entry) as stream:
                header = stream.read(52)
            if header.startswith(b'\x7fELF'):
                if len(header) < 52 or header[4:6] != bytes([1, 1]) or struct.unpack_from('<H', header, 18)[0] != 40:
                    raise ValueError('Non-ARM32 little-endian native library')
                if struct.unpack_from('<I', header, 36)[0] & 0x400:
                    raise ValueError('ARM hard-float ABI is not the Tizen arm target')
                elves.append(entry.filename)
        required = {'tizen-manifest.xml', 'author-signature.xml', 'signature1.xml'}
        if not required.issubset(names):
            raise ValueError('Missing manifest or signing blocks')
        if archive.getinfo('tizen-manifest.xml').file_size > 1024 * 1024:
            raise ValueError('Manifest exceeds inspection limit')
        manifest = archive.read('tizen-manifest.xml').decode('utf-8-sig')
        if '<!DOCTYPE' in manifest or '<!ENTITY' in manifest:
            raise ValueError('DTDs and entities are forbidden')
        root = ET.fromstring(manifest)  # noqa: S314 -- strict UTF-8, bounded, no DTD/entities.
        ns = {'t': 'http://tizen.org/ns/packages'}
        app = root.find('t:ui-application', ns)
        profile = root.find('t:profile', ns)
        if root.get('package') != 'com.edde746.plezy' or root.get('api-version') != '6.0':
            raise ValueError('Incorrect package identity or API')
        if profile is None or profile.get('name') != 'tv':
            raise ValueError('Package is not TV profile')
        if app is None or app.get('appid') != 'com.edde746.plezy' or app.get('type') != 'dotnet' or app.get('exec') != 'Runner.dll':
            raise ValueError('Not the supported C# application host')
        basenames = {PurePosixPath(name).name for name in names}
        if not {'Runner.dll', 'libapp.so', 'libflutter_engine.so', 'libflutter_tizen.so'}.issubset(basenames):
            raise ValueError('Missing C# host, AOT application, engine or embedder')
        if not {'libapp.so', 'libflutter_engine.so', 'libflutter_tizen.so'}.issubset({PurePosixPath(name).name for name in elves}):
            raise ValueError('Native release components are not ARM ELF files')
        return {
            'package': root.get('package'), 'version': root.get('version'), 'api': '6.0',
            'profile': 'tv', 'architecture': 'arm', 'host': 'dotnet', 'aot': True,
            'native_libraries': sorted(elves),
            'signature_blocks_present': True,
            'cryptographic_signature_verified': False,
            'tv_installation_verified': False,
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--revision', required=True)
    parser.add_argument('--dirty', action='store_true')
    parser.add_argument('--source-inputs-sha256')
    parser.add_argument('--signing-category', required=True, choices=['test-only', 'user-profile-unverified'])
    args = parser.parse_args()
    result = inspect(args.package)
    result.update(sha256=hashlib.sha256(args.package.read_bytes()).hexdigest(),
                  source_revision=args.revision, source_tree_dirty=args.dirty,
                  source_inputs_sha256=args.source_inputs_sha256,
                  signing_category=args.signing_category)
    args.output.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
