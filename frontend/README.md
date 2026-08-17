# Flutter 客户端

本目录已包含 Android 与 Web 平台工程。启动后端和 MySQL 后，在本目录运行：

```powershell
flutter pub get
flutter run -d chrome --web-port 5173
```

Android 模拟器访问本机后端默认使用 `http://10.0.2.2:8080`。真机或部署环境通过启动参数指定后端地址，例如：

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8080
```

常用验证命令：

```powershell
dart format lib test
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
```

Web 调试使用 `5173` 端口时已匹配后端默认 CORS 配置；其他 Web 域名需要加入后端 `CORS_ALLOWED_ORIGINS`。
