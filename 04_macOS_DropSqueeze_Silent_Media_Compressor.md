# 项目四：DropSqueeze — macOS 剪贴板/截图/录屏零操作静默压缩器 (macOS)

## 1. 市场定位与竞品降维打击分析
* **目标人群**：独立开发者、自媒体博主、产品经理、UI 设计师、技术文档写作者（每天高频使用微信、飞书、Slack、Notion、GitHub Issue 贴图/贴视频的人群）。
* **市场现状与对标竞品**：
  * `TinyPNG`（网页端，每次要打开浏览器上传下载，极度打断心流）。
  * `ImageOptim`（开源老牌，界面简陋，不支持视频/GIF，不支持剪贴板静默接管）。
  * `Clop` / `Compresto`（海外独立开发者新秀，证明了该赛道在 Mac 端月入 $10k+ 的极强吸金能力，但在中文本土化工作流和 Mac App Store 内仍有巨大空间）。
* **核心破局点（USP）**：
  * **“零感知、零操作”剪贴板原地瘦身**：用户按下 `Cmd + Shift + 4` 截图到剪贴板，原本 Retina 屏幕截出来的 **8MB PNG**，在 0.3 秒内由后台自动无损压缩为 **600KB PNG 或 WebP** 并重新写回剪贴板，用户直接 `Cmd + V` 粘贴到飞书/Notion/GitHub，速度飞快且不占云盘配额！
  * **刘海屏 (Notch) 悬浮拖拽黑洞**：把录制的 `.mov` 拖到屏幕顶部刘海下方，松手即刻转为高画质小体积 `.mp4` 或高帧率 `.gif`。

---

## 2. 中英文高权重 ASO 关键词矩阵

### 2.1 英文市场 (Mac App Store & 官网 SEO)
* **App Title (30 字符以内)**：
  `DropSqueeze: Image & Video Zip` *(30 chars)*
* **Subtitle (30 字符以内)**：
  `Compress PNG, MP4, GIF & WebP` *(29 chars)*
* **Keywords (100 字符以内)**：
  `compressor,imageoptim,tinypng,shrink,resize,video,mp4,mov,gif,webp,heic,png,jpg,pdf,clipboard,batch` *(99 chars)*

### 2.2 中文市场 (Mac App Store)
* **App Title (30 字符以内)**：
  `秒压 DropSqueeze - 截图录屏无损压缩与转码` *(26 chars)*
* **Subtitle (30 字符以内)**：
  `剪贴板图片自动瘦身·MOV转MP4/GIF·批量转WebP` *(29 chars)*
* **Keywords (100 字符以内)**：
  `图片压缩,视频压缩,无损压缩,截图,录屏,格式转换,mov转mp4,转gif,webp,heic转jpg,pdf压缩,批量修改尺寸,菜单栏,剪贴板,tinypng,图床,设计师工具,自媒体` *(96 chars)*

---

## 3. MVP 核心功能清单 (1~2 周开发周期)

### P0（首版必做）
1. **剪贴板静默监听器 (Clipboard Guard)**：轮询 `NSPasteboard.general.changeCount`，一旦检测到新增图片或刚复制的视频文件，立即在后台调用硬件加速压缩并替换剪贴板内容，同时在屏幕角落（或刘海下方）弹出一个极简灵动的气泡提示：*“已省下 84% 空间 (6.2MB → 980KB) [撤销]”*。
2. **特定文件夹全自动看门狗 (Folder Watcher)**：默认监控系统 `Desktop`（桌面）或用户自定义的截图保存目录。只要系统生成 `Screen Shot ...png` 或 `Screen Recording ...mov`，1 秒内原地压缩或自动转码为 `.mp4`。
3. **刘海屏 / 悬浮窗拖拽区 (Drop Zone)**：鼠标拖拽任意图片/视频文件移动时，屏幕边缘自动浮现压缩舱，支持一键拖入批量压缩并直接拖出到邮件或聊天窗口。

---

## 4. Swift 架构设计与核心技术栈

### 4.1 推荐目录与模块架构
```text
DropSqueeze/
├── App/
│   ├── DropSqueezeApp.swift          // MenuBarExtra 常驻菜单栏入口
│   └── NotchFloatingPanel.swift      // NSPanel (nonactivatingPanel) 刘海悬浮窗
├── Core/
│   ├── Watchers/
│   │   ├── PasteboardMonitor.swift   // Timer 监听 NSPasteboard.changeCount + 防死循环写入标记
│   │   └── DirectoryWatcher.swift    // DispatchSourceFileSystemObject 监听截图文件夹
│   ├── Engines/
│   │   ├── ImageSquasher.swift       // ImageIO + vImage / 内置 pngquant & cwebp 二进制调用
│   │   ├── VideoTranscoder.swift     // AVAssetExportSession / VideoToolbox 硬件加速 H.264/HEVC
│   │   └── GIFGenerator.swift        // CGImageDestination 调色板量化生成高质量 GIF
└── Features/
    ├── MenuBarPopover/               // 今日节省空间统计、历史最近 10 个压缩项、快速拖拽槽
    ├── RulesSettings/                // 监控目录配置、分辨率缩放规则 (如 Retina 2x 自动缩至 1x)
    └── Paywall/                      // StoreKit 2 买断与订阅管理
```

### 4.2 核心技术实现要点
* **防止剪贴板监听死循环（极其关键！）**：
  当你的 App 把压缩后的图片写回 `NSPasteboard` 时，`changeCount` 也会加 1。必须在写入时附带一个自定义的私有 `NSPasteboard.PasteboardType("com.yourname.dropsqueeze.processed")`。监听器一旦读到包含该标记的剪贴板项，直接跳过！
* **零外部重度依赖的视频极速压缩**：
  在 Mac App Store 沙盒内，无需打包几百兆的 FFmpeg，直接使用苹果原生 `AVAssetReader` + `AVAssetWriter` 配合 Apple Silicon 的 `VideoToolbox` 硬件编码器，调节比特率（Bitrate）与分辨率，速度比纯 CPU 软压快 5~10 倍，且安装包体积可控制在 **5MB 以内**！

---

## 5. 商业化定价与付费墙 (Paywall) 埋点设计

### 5.1 价格锚点策略
* **免费版**：每日免费自动压缩 **15 张图片 + 3 个视频**；支持手动拖拽单张压缩。
* **Pro 版（Mac 用户最爱买断制）**：
  * 年度通行证：`$9.99 / 年`
  * **终身买断版 (Lifetime)**：`$16.99`（¥98 买断，主推项，标注“不到一杯咖啡钱，省下几十 GB 硬盘与云盘空间”）

### 5.2 高转化付费墙触发埋点
1. **埋点 A（配额耗尽瞬间拦截）**：当用户一天内截了第 16 张图，状态栏气泡弹出：*“今日免费极速瘦身额度已用完（本周已为您累计节省 142 MB 空间），一键解锁无限自动瘦身”*。用真实帮他省下的 MB 数字刺激多巴胺付费！
2. **埋点 B（高阶格式与降采样拦截）**：开启 **“截图自动从 Retina @2x 缩放到标准 @1x 尺寸”**、**“自动转换为 WebP 格式”** 或 **“录屏 MOV 自动转高帧率 GIF”** 开关时弹出付费墙。
3. **埋点 C（文件夹自动监控数量）**：添加第 2 个自定义监控文件夹时触发。

---

## 6. Mac App Store (MAS) 沙盒避坑与双轨发行指南
1. **MAS 沙盒权限处理 (App Sandbox)**：
   * 上架 Mac App Store 必须开启 Sandbox。为了监控用户的“桌面”或“截图文件夹”，必须通过 `NSOpenPanel` 让用户手动点选一次该文件夹，然后使用 **Security-Scoped Bookmarks (`bookmarkData(options: .withSecurityScope)`)** 将权限持久化保存在 `UserDefaults` 中，这样重启电脑后依然能静默监控！
2. **双轨赚钱建议**：
   * 同时准备一个通过 **Developer ID 公证 (Notarized)** 的官网直装版（集成 Sparkle 自动更新 + LemonSqueezy/Paddle 收款），官网版可以免去用户首次授权文件夹的步骤，并可无缝内嵌 `pngquant`/`ffmpeg` CLI 处理极端格式。
