#!/usr/bin/env python3
"""Sign local builds with a persistent, private, app-specific identity.

No Apple account or system-wide certificate trust is needed. The identity lives
outside the checkout; deleting it requires approving Accessibility again.
"""
import hashlib
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import sys
import tempfile

os.umask(0o077)
folder = Path.home() / 'Library/Application Support/SpaceNameBar/Signing'
keychain = folder / 'local-signing.keychain-db'
password_file = folder / 'keychain-password'
certificate_file = folder / 'certificate.der'


def run(*args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs).stdout


def prepare():
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    if keychain.exists():
        if not password_file.exists() or not certificate_file.exists():
            raise RuntimeError('Local signing identity is incomplete. Restore its backup; do not silently replace it.')
        return
    if password_file.exists() or certificate_file.exists():
        raise RuntimeError('Local signing setup is incomplete. Inspect the Signing directory before retrying.')
    password = secrets.token_hex(32)
    # security create-keychain changes the search list; restore it exactly.
    search_list = shlex.split(run('/usr/bin/security', 'list-keychains', '-d', 'user').decode())
    with tempfile.TemporaryDirectory(prefix='setup-', dir=folder) as temp:
        temp = Path(temp)
        config = temp / 'certificate.conf'
        config.write_text('''[req]
prompt = no
distinguished_name = subject
x509_extensions = extensions
[subject]
CN = SpaceNameBar Local Development
[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
''')
        run('/usr/bin/openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes',
            '-x509', '-days', '3650', '-sha256', '-config', str(config),
            '-keyout', str(temp / 'key.pem'), '-out', str(temp / 'cert.pem'))
        run('/usr/bin/openssl', 'x509', '-in', str(temp / 'cert.pem'),
            '-outform', 'DER', '-out', str(certificate_file))
        env = dict(os.environ, SPACENAMEBAR_P12_PASSWORD=password)
        run('/usr/bin/openssl', 'pkcs12', '-export', '-inkey', str(temp / 'key.pem'),
            '-in', str(temp / 'cert.pem'), '-out', str(temp / 'identity.p12'),
            '-passout', 'env:SPACENAMEBAR_P12_PASSWORD', env=env)
        password_file.write_text(password)
        try:
            run('/usr/bin/security', 'create-keychain', '-p', password, str(keychain))
        finally:
            run('/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *search_list)
        run('/usr/bin/security', 'import', str(temp / 'identity.p12'), '-k', str(keychain),
            '-P', password, '-x', '-T', '/usr/bin/codesign')
        run('/usr/bin/security', 'set-key-partition-list', '-S', 'apple-tool:',
            '-s', '-k', password, str(keychain))
    print('Created private local signing identity (no system trust settings changed).')


def main():
    prepare()
    password = password_file.read_text().strip()
    fingerprint = hashlib.sha1(certificate_file.read_bytes()).hexdigest().upper()
    run('/usr/bin/security', 'unlock-keychain', '-p', password, str(keychain))
    requirement = '=designated => identifier "com.carusiphilip.SpaceNameBar" and certificate leaf = H"' + fingerprint + '"'
    search_list = shlex.split(run('/usr/bin/security', 'list-keychains', '-d', 'user').decode())
    try:
        run('/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *search_list, str(keychain))
        run('/usr/bin/codesign', '--force', '--sign', fingerprint, '--keychain', str(keychain),
            '--requirements', requirement, '--timestamp=none', sys.argv[1])
    finally:
        run('/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *search_list)
        run('/usr/bin/security', 'lock-keychain', str(keychain))
    run('/usr/bin/codesign', '--verify', '--strict', sys.argv[1])
    print('Verified app signature using the persistent local certificate.')


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        # Commands contain passwords: never print CalledProcessError or argv.
        print('Signing failed: ' + error.stderr.decode(errors='replace'), file=sys.stderr)
        sys.exit(1)
