#!/usr/bin/env python3
"""Copy the pinned Sparkle artifact and retain only the requested CPU slice."""
import pathlib
import shutil
import subprocess
import sys

app, architecture, artifact = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
assert architecture in ('arm64', 'x86_64')
source = artifact / 'Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
framework = app / 'Contents/Frameworks/Sparkle.framework'
subprocess.run(['ditto', str(source), str(framework)], check=True)
magic_values = {bytes.fromhex(s) for s in ('cffaedfe', 'cefaedfe', 'cafebabe', 'bebafeca', 'feedfacf', 'feedface')}
for binary in framework.rglob('*'):
    if binary.is_symlink() or not binary.is_file():
        continue
    with binary.open('rb') as f:
        magic = f.read(4)
    if magic not in magic_values:
        continue
    slices = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
    if architecture not in slices:
        raise SystemExit(f'Sparkle component lacks {architecture}: {binary.name}')
    if len(slices) > 1:
        temporary = binary.with_suffix('.thin')
        subprocess.run(['lipo', str(binary), '-thin', architecture, '-output', str(temporary)], check=True)
        temporary.chmod(binary.stat().st_mode)
        temporary.replace(binary)
for path in (framework / 'Headers', framework / 'Modules'):
    if path.is_symlink(): path.unlink()
for name in ('Headers', 'Modules'):
    shutil.rmtree(framework / 'Versions/B' / name, ignore_errors=True)
licenses = app / 'Contents/Resources/Licenses'
licenses.mkdir(parents=True, exist_ok=True)
shutil.copyfile(artifact / 'LICENSE', licenses / 'Sparkle-LICENSE.txt')
print(f'Bundled Sparkle 2.10.0 ({architecture}), including native installer helpers.')
