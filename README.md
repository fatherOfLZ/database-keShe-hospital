# 住院信息管理系统

Spring Boot REST API 与 Flutter（Android/Web）客户端的单仓库课程设计项目。

## 目录

- `backend/`: Spring Boot 3、MySQL 8、Flyway、JWT 后端
- `frontend/`: Flutter 跨端客户端源代码
- `住院信息管理系统-实体与关联设计.md`: 概念模型说明

## 本地运行

1. 创建 MySQL 数据库：`CREATE DATABASE hospital_management DEFAULT CHARACTER SET utf8mb4;`
2. 在 `backend/` 设置环境变量 `DB_USERNAME`、`DB_PASSWORD`，必要时设置 `DB_URL`。
3. 执行 `mvnw.cmd spring-boot:run`。项目已处理 Windows 中文目录下 Spring Boot 参数文件的
   classpath 编码问题；Flyway 会自动建表并初始化角色、演示账号和基础目录。
4. 默认演示账号：`admin / Admin123!`、`admission / Admission123!`、`doctor / Doctor123!`。

后端默认地址为 `http://localhost:8080`，接口前缀为 `/api/v1`。

Flutter SDK 与 Android SDK 安装完成后，在 `frontend/` 执行 `flutter pub get`、`flutter run -d chrome` 或 `flutter run`。
