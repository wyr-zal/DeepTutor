# DeepTutor Mobile

DeepTutor 的 Flutter Android 学习客户端，提供以会话为中心的聊天学习闭环：

1. 正式版自动连接构建时配置的 DeepTutor 服务；需要鉴权时再登录。
2. 在聊天消息流中发送普通问题，或切换到 `deep_question` 配置内联出题。
3. 通过统一 WebSocket 长连接接收流式回答、题目和会话状态。
4. 在题目卡片内文字作答；可直接使用系统输入法提供的语音转文字。
5. 在原题目卡片内通过 Judge WebSocket 流式接收 AI 评判。
6. 右滑查看、加载、重命名和删除服务端会话；离线摘要缓存按服务器和账号隔离。

## 开发环境

- Windows Flutter：`F:\Dev\Flutter`（当前验证使用 3.44.8 / Dart 3.12.2）
- Windows Android SDK：`F:\Dev\AndroidSdk`（compile/target SDK 36，min SDK 24）
- Windows Android AVD：`F:\Dev\AndroidAvd`
- 共享 Pub/Gradle 缓存：`F:\Dev\PubCache`、`F:\Dev\Caches\gradle`
- JDK 17 或更高版本（当前使用 `D:\Develop\JDK\jdk21`）

```bat
cd mobile
F:\Dev\Flutter\bin\flutter.bat pub get
F:\Dev\Flutter\bin\flutter.bat analyze
F:\Dev\Flutter\bin\flutter.bat test
F:\Dev\Flutter\bin\flutter.bat build apk --debug
```

Debug 构建允许连接 `http://` 开发服务器。Release 构建只接受 HTTPS/WSS，避免 Android 明文传输策略与生产安全边界不一致。

## 一键构建脚本

`scripts/build.bat` 是唯一实际构建实现，固定使用 Windows 原生 Flutter、Android SDK、JDK、Pub 缓存和 Gradle 缓存。`scripts/build.ps1` 是 PowerShell 入口；`scripts/build.sh` 仅供从 WSL 触发时转调 Windows CMD，**不会使用 WSL Flutter 或 WSL Gradle**。

```bat
cd mobile\scripts
build.bat debug
set SERVER_URL=https://deeptutor.example.com & build.bat release
set SERVER_URL=https://deeptutor.example.com & build.bat both
```

常用环境变量（放命令前面）：

| 变量 | 作用 |
| --- | --- |
| `SERVER_URL` | 烧入固定服务地址。**release 必填**，缺失时脚本直接报错拦下，避免打出装机后提示“尚未配置服务地址”的哑包 |
| `ALLOW_SERVER_ENTRY=1` | 即使 release 也开放“App 内手动填服务器地址”输入框；与 `SERVER_URL` 二选一，适合地址常变的场景 |
| `CLEAN=1` | 构建前先 `flutter clean`（最干净，但更慢；平时不需要） |
| `INSTALL=1` | 打完自动 `adb install` 到已连接设备/模拟器 |
| `NO_TREE_SHAKE=1` | 关闭图标 tree-shaking（排查图标丢失时用） |
| `DEEPTUTOR_FLUTTER_HOME` | 显式覆盖 Windows Flutter 根目录；默认 `F:\Dev\Flutter` |
| `DEEPTUTOR_ANDROID_HOME` | 显式覆盖 Windows Android SDK；默认 `F:\Dev\AndroidSdk` |
| `DEEPTUTOR_ANDROID_AVD_HOME` | 显式覆盖 Windows AVD 目录；默认 `F:\Dev\AndroidAvd` |
| `DEEPTUTOR_PUB_CACHE` | 显式覆盖 Pub 缓存；默认 `F:\Dev\PubCache` |
| `DEEPTUTOR_GRADLE_USER_HOME` | 显式覆盖 Gradle 缓存；默认 `F:\Dev\Caches\gradle` |
| `DEEPTUTOR_JAVA_HOME` | 显式覆盖 JDK；默认 `D:\Develop\JDK\jdk21` |

> 构建必须从 Windows 原生工具链执行。项目位于 `E:` 盘，Windows Flutter 与 Gradle 直接访问 `E:\ProjectOwn\DeepTutor\mobile`，不再经过 `/mnt/e` 跨文件系统构建。项目级 `kotlin.incremental=false` 用于规避 `E:` 项目与 `F:` 共享 Pub 缓存之间的 Kotlin 跨盘路径错误。

以下 `flutter build apk` 原始命令等价于脚本内部所做的事，需要精细控制时可直接使用。

正式版必须在构建时固定服务地址，普通用户不会看到服务器地址输入框：

```powershell
& F:\Dev\Flutter\bin\flutter.bat build apk --release `
  --dart-define=DEEPTUTOR_FIXED_SERVER_URL=https://deeptutor.example.com
```

Debug 构建也应通过 `DEEPTUTOR_FIXED_SERVER_URL` 注入实际部署地址。未提供该参数时才显示开发服务器连接页；应用会先检测 `/api/v1/auth/status`，未启用鉴权则直接进入聊天，启用鉴权后才显示用户名和密码。若确需在非 Debug 构建中开放手动服务器配置，可显式添加 `--dart-define=DEEPTUTOR_ALLOW_SERVER_ENTRY=true`。

当前 Cloudflare 临时 Tunnel 验证构建示例（临时域名重启后可能变化）：

```powershell
& F:\Dev\Flutter\bin\flutter.bat build apk --debug `
  --dart-define=DEEPTUTOR_FIXED_SERVER_URL=https://widespread-nightlife-shame-trees.trycloudflare.com
```

## Release 签名

Release 构建不会回退到 debug keystore。复制示例文件并填写真实签名信息：

```bash
cp android/key.properties.example android/key.properties
flutter build apk --release
```

也可通过以下环境变量提供签名配置：

- `DEEPTUTOR_ANDROID_STORE_FILE`
- `DEEPTUTOR_ANDROID_STORE_PASSWORD`
- `DEEPTUTOR_ANDROID_KEY_ALIAS`
- `DEEPTUTOR_ANDROID_KEY_PASSWORD`

未配置完整签名时，Release 构建会明确失败。不要提交 `android/key.properties`、keystore 或任何真实密码。

> 本机已生成 `android/deeptutor-release.jks` + `android/key.properties`（均被 `.gitignore` 忽略，不会进版本库）。**请自行备份这两个文件**：keystore 决定 App 身份，只有同一 keystore 签名的包才能覆盖升级、才能上架；丢失后无法再发布可平滑升级的新版本。

## 后端契约

- 原生登录：`POST /api/v1/auth/token`
- 登录状态：`GET /api/v1/auth/status`
- 知识库：`GET /api/v1/knowledge/list`
- 统一聊天/出题：`WS /api/v1/ws?token=...`（`capability=chat|deep_question`）
- AI 评判：`WS /api/v1/question/judge?token=...`
- 服务端会话：`GET/PATCH/DELETE /api/v1/sessions[/{id}]`

Web 端继续使用原有 HttpOnly cookie 登录；移动端 token 存入 Android secure storage，并通过 Bearer header 或 WebSocket query 参数传递。

## 产物

- Debug：`build/app/outputs/flutter-apk/app-debug.apk`
- Release：`build/app/outputs/flutter-apk/app-release.apk`

安装前可用 Android Build Tools 验证签名：

```bash
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
```
