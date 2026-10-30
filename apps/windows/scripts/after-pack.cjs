'use strict';
// electron-builder afterPack: embeds the app icon and version info into FeishuIsland.exe.
// Cross-building on macOS cannot run rcedit (it needs Wine), so this uses pure-JS resedit.
const fs = require('node:fs');
const path = require('node:path');
const ResEdit = require('resedit');

exports.default = async function afterPack(context) {
  if (context.electronPlatformName !== 'win32') return;
  const exe = path.join(context.appOutDir, context.packager.appInfo.productFilename + '.exe');
  const target = fs.existsSync(exe) ? exe : path.join(context.appOutDir, 'FeishuIsland.exe');
  const version = context.packager.appInfo.version;
  const data = fs.readFileSync(target);
  const executable = ResEdit.NtExecutable.from(data, { ignoreCert: true });
  const res = ResEdit.NtExecutableResource.from(executable);
  const iconFile = ResEdit.Data.IconFile.from(fs.readFileSync(path.join(__dirname, '..', 'assets', 'icon.ico')));
  ResEdit.Resource.IconGroupEntry.replaceIconsForResource(res.entries, 1, 1033, iconFile.icons.map(i => i.data));
  const [vi] = ResEdit.Resource.VersionInfo.fromEntries(res.entries);
  const [a, b, c] = version.split('.').map(Number);
  vi.setFileVersion(a, b, c, 110, 1033); vi.setProductVersion(a, b, c, 110, 1033);
  vi.setStringValues({ lang: 1033, codepage: 1200 }, { FileDescription: '一切在岛', ProductName: '一切在岛', CompanyName: '虚实传媒', OriginalFilename: 'FeishuIsland.exe', InternalName: 'FeishuIsland', LegalCopyright: '虚实传媒' });
  vi.outputToResourceEntries(res.entries);
  res.outputResource(executable);
  fs.writeFileSync(target, Buffer.from(executable.generate()));
  console.log('  • 已写入图标与版本信息 ' + path.basename(target));
};
