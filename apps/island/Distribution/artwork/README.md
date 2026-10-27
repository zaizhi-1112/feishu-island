# 一切在岛发布图标

来源是本人在2026-10-27发布请求中提供的蓝绿尾翼云朵插画。使用内置 imagegen 做透明背景提取，输出已复制为本目录 `island-mascot-transparent.png`；网页使用 `site/mascot.png`，中台使用 `site/icon.png`（256×256、透明PNG、54220字节）。原始生成文件保留。build52至build55曾只更新网页/中台图标；build56将同一透明云朵原图用于Resources/AppIcon.png，重新生成全部iconset与AppIcon.icns，构建脚本每次打包前重新生成图标，避免安装包沿用旧图。

人工查看透明提取结果，保留了白色云朵、蓝绿尾翼、面罩、双眼、笑脸与水彩质感；这是生成式背景提取，不作像素完全一致的保证。缩小网页资源使用sips，保留透明通道。

提示词：

> Use case: background-extraction. Edit target: the attached blue-and-teal, smiling white cloud mascot illustration. Create a faithful transparent PNG cutout for the product icon. Change ONLY the outer white paper/background to fully transparent, including the blank spaces around the silhouette and between the left tail and the cloud. Keep every part of the original mascot unchanged: the cloud body's opaque white and pale blue watercolor texture, navy outline, blue/teal layered tail, dark navy face visor, two white circle-slash eyes, small white smiling mouth, pale-blue cheeks and small front puff/hand. Preserve the exact pose, proportions, colors, original hand-drawn watercolor aesthetic and silhouette. Do not add text, a rounded-square tile, backdrop, shadow, decorations, or extra body parts. Center the complete silhouette with small even transparent margins, no clipping. This is background extraction, not redesign.
