#!/usr/bin/env python3
# Download official version-pinned CLI assets; do not copy any local config.
import pathlib,subprocess,hashlib,tarfile,zipfile
root=pathlib.Path(__file__).resolve().parents[2];checks={line.split()[1]:line.split()[0] for line in (root/'tools/lark-cli/node_modules/@larksuite/cli/checksums.txt').read_text().splitlines()}
for platform,arch,folder in [('darwin','arm64','mac-arm64'),('darwin','amd64','mac-x64'),('windows','amd64','win-x64')]:
 ext='zip' if platform=='windows' else 'tar.gz';name=f'lark-cli-1.0.96-{platform}-{arch}.{ext}';dest=root/'.build'/name
 if not dest.exists() or hashlib.sha256(dest.read_bytes()).hexdigest()!=checks[name]:
  subprocess.run(['curl','-fL','--connect-timeout','15','--max-time','180','-sS',f'https://registry.npmmirror.com/-/binary/lark-cli/v1.0.96/{name}','-o',str(dest)],check=True)
 assert hashlib.sha256(dest.read_bytes()).hexdigest()==checks[name],f'Checksum mismatch: {name}'
 output=root/'Desktop/vendor'/folder;output.mkdir(parents=True,exist_ok=True)
 wanted={'lark-cli.exe','lark-cli','LICENSE'}
 if ext=='zip':
  with zipfile.ZipFile(dest) as z:
   for m in z.namelist():
    if pathlib.Path(m).name in wanted and not m.endswith('/'):(output/pathlib.Path(m).name).write_bytes(z.read(m))
 else:
  with tarfile.open(dest) as t:
   for m in t.getmembers():
    if m.isfile() and pathlib.Path(m.name).name in wanted:(output/pathlib.Path(m.name).name).write_bytes(t.extractfile(m).read())
 binary=output/('lark-cli.exe' if platform=='windows' else 'lark-cli');assert binary.exists();binary.chmod(0o755)
 print(f'PASS: {folder}, official SHA-256 verified')
