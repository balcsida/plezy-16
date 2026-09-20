#!/usr/bin/env python3
import io
import struct
import unittest
import zipfile

from inspect_tpk import inspect


class PackageInspectionTest(unittest.TestCase):
    def package(self, *, machine=40, extra=None, manifest=None):
        header = bytearray(52)
        header[:6] = b'\x7fELF\x01\x01'
        struct.pack_into('<H', header, 18, machine)
        entries = {
            'tizen-manifest.xml': manifest or '''<manifest xmlns="http://tizen.org/ns/packages"
                package="com.edde746.plezy" api-version="6.0" version="2.20.0">
                <profile name="tv"/><ui-application appid="com.edde746.plezy" type="dotnet" exec="Runner.dll"/>
                </manifest>''',
            'author-signature.xml': '<Signature/>', 'signature1.xml': '<Signature/>',
            'bin/Runner.dll': b'MZ',
            **{f'lib/{name}': header for name in ['libapp.so', 'libflutter_engine.so', 'libflutter_tizen.so']},
            **(extra or {}),
        }
        target = io.BytesIO()
        with zipfile.ZipFile(target, 'w') as archive:
            for name, value in entries.items():
                archive.writestr(name, value)
        target.seek(0)
        return target

    def test_arm_csharp_structure_is_not_claimed_as_verified_signing(self):
        result = inspect(self.package())
        self.assertTrue(result['aot'])
        self.assertFalse(result['cryptographic_signature_verified'])
        self.assertFalse(result['tv_installation_verified'])

    def test_rejects_wrong_arch_secrets_debug_and_xml_entities(self):
        bad = [self.package(machine=62), self.package(machine=183)]
        for path in ['author.p12', 'profiles.xml', '../escape', 'lib/libsqlite3.so', 'kernel_blob.bin']:
            bad.append(self.package(extra={path: b'not for release'}))
        bad.append(self.package(manifest='<!DOCTYPE manifest [<!ENTITY x "boom">]><manifest/>'))
        bad.append(self.package(manifest='<manifest/>'.encode('utf-16')))
        for package in bad:
            with self.subTest(package=package), self.assertRaises((ValueError, UnicodeError)):
                inspect(package)


if __name__ == '__main__':
    unittest.main()
