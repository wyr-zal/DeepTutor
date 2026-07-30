# DeepTutor Mobile

DeepTutor 的 Flutter Android 学习客户端，覆盖以下 MVP 闭环：

1. 输入 DeepTutor 服务器地址并登录。
2. 选择知识库并配置题型、难度和数量。
3. 通过 WebSocket 流式接收题目。
4. 文字回答，或长按录音并上传后端 STT 转写。
5. 通过 WebSocket 流式接收 AI 评判。
6. 查看服务端会话和按服务器、账号隔离的本机答题记录。

## 开发环境

- Flutter 3.24 或更高版本
- Android SDK（当前验证使用 compile/target SDK 36，min SDK 24）
- JDK 17 或更高版本

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Debug 构建允许连接 `http://` 开发服务器。Release 构建只接受 HTTPS/WSS，避免 Android 明文传输策略与生产安全边界不一致。

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

## 后端契约

- 原生登录：`POST /api/v1/auth/token`
- 登录状态：`GET /api/v1/auth/status`
- 知识库：`GET /api/v1/knowledge/list`
- 出题：`WS /api/v1/question/generate?token=...`
- STT：`POST /api/v1/voice/stt`
- AI 评判：`WS /api/v1/question/judge?token=...`
- 服务端会话：`GET /api/v1/sessions`

Web 端继续使用原有 HttpOnly cookie 登录；移动端 token 存入 Android secure storage，并通过 Bearer header 或 WebSocket query 参数传递。

## 产物

- Debug：`build/app/outputs/flutter-apk/app-debug.apk`
- Release：`build/app/outputs/flutter-apk/app-release.apk`

安装前可用 Android Build Tools 验证签名：

```bash
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
```
