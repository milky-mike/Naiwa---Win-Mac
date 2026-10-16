# 🐸 奶娃桌宠 · Naiwa Desktop Pet

一只可以悬浮在桌面上的互动奶娃，支持 **macOS** 和 **Windows**。包含五种高清姿势、透明背景动画，以及双击播放的原声捧腹大笑效果。

*A little interactive Naiwa desktop pet for macOS and Windows, featuring five poses, transparent animations and a laughing animation with original audio.*

> **下载前须知 / Before you start:** 本仓库提供的是**源代码与素材**，并非已签名的 macOS 安装程序或可以直接下载运行的 Windows `.exe`。请完整保留 `assets/`、`mac/`、`windows/` 的相对位置。
>
> This repository contains **source code and assets**, not prebuilt signed applications. Keep the folder layout intact.

## ✨ 功能 / Features

| 功能 | macOS | Windows |
|---|:---:|:---:|
| 透明背景、窗口置顶、拖动桌宠 | ✅ | ✅ |
| 待机时四种姿势每 10 秒切换 | ✅ | ✅ |
| 鼠标悬停轻微浮动、姿势过渡 | ✅ | ✅ |
| 单击切换抱肚子姿势 | ✅ | ✅ |
| 默认：单击变大并保持、再单击变小并保持 | ✅ | ✅ |
| 可设置：单击后自动鼓起并缩回 | ✅ | ✅ |
| 最后一次单击后闲置 10 秒恢复第一姿势 | ✅ | ✅ |
| 双击播放捧腹大笑动画（443 帧 / 30 FPS）及原声音轨 | ✅ | ✅ |
| 调整大笑循环、音量、静音、桌宠大小 | ✅ | ✅ |
| 菜单操作及设置保存 | ✅ | ✅ |

**点击模式 / Belly click mode：** 默认是「一次变大、再一次变小」；可以在菜单中改成「每次点击自动变大再缩回」。双击大笑时不会被待机倒计时打断。

## 📁 项目结构 / Project structure

```text
NaiwaDesktopPet/
├── assets/                   # Mac 和 Windows 共用的图像、动画和音频
│   ├── Stills/               # 姿势图及肚子变化帧
│   ├── LaughFrames/          # 大笑动画帧
│   ├── laugh_original_audio.m4a
│   ├── AppIcon.png
│   └── AppIcon.ico
├── mac/
│   ├── build.command         # macOS 构建脚本
│   └── Sources/main.swift
├── windows/
│   ├── start_windows.bat     # Windows Python 启动脚本
│   ├── build_windows.bat     # 构建 Windows exe
│   ├── main.py
│   ├── pet_state.py
│   └── requirements.txt
├── tests/                    # 无需图形界面的行为回归测试
├── .github/workflows/ci.yml # GitHub 自动测试及编译
└── README.md
```

> `assets/` **不能删除**：两个平台都需要它来加载奶娃图片、大笑动画和声音。Do not remove `assets/`.

## 🍎 macOS 运行 / Run on macOS

**要求：** macOS 13 或更新版本，Xcode Command Line Tools；支持 Apple Silicon / Intel，在本机编译。

1. 点击 GitHub 上的 **Code → Download ZIP**，或克隆仓库。
2. 打开 Terminal（终端），进入解压后的项目根目录。
3. 运行：

```bash
bash mac/build.command
```

4. 构建成功后打开 `mac/奶娃桌宠.app`。以后可以把完整 `.app` 复制到「应用程序 / Applications」。

如果提示缺少命令行工具：

```bash
xcode-select --install
```

如果 macOS 拦截未签名的程序，请先确认你信任此仓库代码，再到 **系统设置 → 隐私与安全性** 按系统提示单独允许启动。无需关闭整个系统的安全保护。

## 🪟 Windows 运行 / Run on Windows

**要求：** Windows 10 / 11（64 位），Python 3.10 或更新版本。[下载 Python](https://www.python.org/downloads/windows/)。

1. 下载并解压**整个仓库**。
2. 进入 `windows/` 文件夹。
3. 双击 `start_windows.bat`：首次运行会建立虚拟环境并安装所需依赖，然后启动桌宠（需要联网）。

若想在自己的 Windows 电脑上构建 `.exe`，双击 `windows/build_windows.bat`。构建成功后从以下位置启动：

```text
windows\dist\NaiwaPetWindows\NaiwaPetWindows.exe
```

**请保留 `dist\NaiwaPetWindows\` 整个文件夹，不能只复制 `.exe`。**

## 🖱️ 交互 / Controls

- **悬停 / Hover：** 奶娃轻微浮动；待机姿势按约 10 秒间隔轮换。
- **单击 / Click：** 进入抱肚子姿势。默认依次变大、变小并保持；可在菜单中选择自动鼓缩。
- **无操作 10 秒 / Idle after clicking：** 自动返回第一姿势，继续轮换。
- **双击 / Double-click：** 播放带原声的大笑动画；可从菜单修改循环次数、音量和静音。
- **菜单 / Menu：** macOS 使用菜单栏奶娃菜单；Windows 使用系统托盘或桌宠右键菜单。

## ⚠️ 说明 / Notes

- 本项目**未提供预编译安装包**。macOS 用户需要自行编译，Windows 用户需要 Python 环境或自行打包。
- 功能基于项目实现与先前的逻辑、资源检查说明；**不保证所有 Mac 和 Windows 机器均已完成实机验证**。出现构建或运行问题时，可在 GitHub Issues 中提供操作系统版本和完整错误日志。
- **素材与版权 / Assets and copyright：** 奶娃角色、图片、视频帧、音效或音乐可能涉及第三方权利。公开可下载不代表素材已获得自由再分发、修改或商用授权；使用或二次分发前请确认相应许可。
- 本项目为非官方的独立桌宠项目，不代表 OpenAI 或 Codex 官方产品。

---

### Quick start (English)

**macOS 13+:** Install Apple Command Line Tools if needed, open Terminal in the repository root and run `bash mac/build.command`. Launch the generated `mac/奶娃桌宠.app`.

**Windows 10/11:** Install Python 3.10+, keep the entire repository, then double-click `windows/start_windows.bat`. To build an executable on Windows, run `windows/build_windows.bat` and keep the entire generated `dist/NaiwaPetWindows/` directory.

**Controls:** Hover for idle animation, click for belly interaction (toggle or auto-pulse mode), and double-click for the laughter animation with audio. After 10 seconds without another click, the pet returns to its first idle pose.


## ✅ 测试 / Validation

在项目根目录执行：

```bash
python3 -m unittest discover -s tests -v
```

GitHub Actions 同时检查资源完整性、Python 行为逻辑、macOS 编译以及 Windows EXE 构建。自动化测试不能代替在真实 Mac/Windows 上的桌宠交互测试。

## ⚖️ 素材使用 / Asset rights

代码与素材的权利并非相同。本项目包含奶娃角色图片、视频拆帧和原音频。公开上传、再分发或商用前，请确认相应授权；公开可见不代表素材可以任意使用。目前仓库未设置统一开源许可证。
