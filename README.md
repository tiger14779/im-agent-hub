# IM Agent Hub

一个独立部署的即时通讯代理系统，基于 OpenIM Server 作为消息引擎。

## 架构图

```
┌────────────────────────────────────────────────────────────┐
│                    用户端 / 管理端                           │
├──────────────────┬─────────────────┬───────────────────────┤
│  H5 聊天前端      │  管理后台前端    │                       │
│  (仿微信界面)     │  (Element Plus) │                       │
│  端口: 3000(dev) │  端口: 3001(dev)│                       │
└────────┬─────────┴────────┬────────┘                       │
         │                  │                                 │
         ▼                  ▼                                 │
┌────────────────────────────────────────────────────────────┤
│              Go 业务后端 (Gin)  :8080                        │
│  ┌──────────────────┐  ┌────────────────────────────────┐  │
│  │  /api/client/*   │  │  /api/admin/* (JWT 保护)        │  │
│  │  H5 登录 API     │  │  用户/客服/设置管理              │  │
│  └──────────────────┘  └────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  SQLite 数据库  ./data/agent_hub.db                   │   │
│  │  用户 | 客服 | 管理员                                  │   │
│  └──────────────────────────────────────────────────────┘   │
└────────────────────────┬───────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────────────┐
│              OpenIM Server (消息引擎)                        │
│  API: :10002  │  WebSocket: :10001                          │
│  MongoDB :37017 │ Redis :16379 │ MinIO :10005               │
└────────────────────────────────────────────────────────────┘
```

## 功能特性

- **无需用户注册**：管理后台创建用户，用 ID 直接登录
- **固定客服对接**：每个用户绑定一个客服，无需加好友
- **淘宝伪装入口**：商品详情页作为入口，隐藏真实聊天功能
- **URL 直接进入**：`/chat?id=USER_ID` 带 ID 直接进入聊天
- **消息类型支持**：文本、图片、语音、文件
- **自动清理**：聊天记录超过 45 天自动清理
- **独立部署**：每个代理独立一套，完全隔离

## 快速部署

### 方式一：Docker 部署（推荐）

1. 修改配置文件：

```bash
cp server/config/config.yaml config.yaml
# 编辑 config.yaml，修改 OpenIM 服务器地址、密钥等
vim config.yaml
```

2. 构建并运行：

```bash
docker-compose up -d
```

3. 访问：
   - H5 聊天：`http://YOUR_SERVER_IP:8080/`
   - 管理后台：`http://YOUR_SERVER_IP:8080/admin/`

### 方式二：本地构建部署

```bash
# 1. 安装依赖并构建前端
make install
make build-h5
make build-admin

# 2. 构建 Go 后端
make build-server

# 3. 修改配置
cp server/config/config.yaml ./config.yaml
vim config.yaml

# 4. 运行
./bin/chat-app
```

## 开发模式

需要同时启动三个服务：

```bash
# 终端 1：Go 后端
make dev-server

# 终端 2：H5 前端（访问 http://localhost:3000）
make dev-h5

# 终端 3：管理后台（访问 http://localhost:3001/admin/）
make dev-admin
```

## 配置说明

编辑 `server/config/config.yaml`：

```yaml
server:
  port: 8080
  jwt_secret: "修改为复杂的随机字符串"  # ⚠️ 必须修改

openim:
  api_url: "http://YOUR_OPENIM_SERVER:10002"  # OpenIM API 地址
  ws_url: "ws://YOUR_OPENIM_SERVER:10001"      # WebSocket 地址
  admin_user_id: "imAdmin"                      # OpenIM 管理员 ID
  secret: "openIM123"                           # OpenIM 密钥

admin:
  username: "admin"     # 管理后台账号
  password: "admin123"  # 管理后台密码（首次启动后可在后台修改）

cleanup:
  enabled: true
  retention_days: 45    # 消息保留天数
  cron: "0 3 * * *"    # 每天凌晨 3 点执行清理
```

## API 文档

### H5 客户端 API

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/client/auth/login` | 用户登录（只需 userId） |

**登录请求示例：**
```json
POST /api/client/auth/login
{ "userId": "user_abc123" }

响应：
{
  "code": 0,
  "data": {
    "token": "eyJ...",
    "serviceUserId": "service_001",
    "wsUrl": "ws://...:10001",
    "apiUrl": "http://...:10002"
  }
}
```

### 管理后台 API（需要 JWT）

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/admin/auth/login` | 管理员登录 |
| GET | `/api/admin/stats` | 统计数据 |
| GET | `/api/admin/users` | 用户列表（分页） |
| POST | `/api/admin/users` | 创建用户 |
| PUT | `/api/admin/users/:id` | 编辑用户 |
| DELETE | `/api/admin/users/:id` | 删除用户 |
| POST | `/api/admin/users/batch` | 批量创建用户 |
| GET | `/api/admin/services` | 客服列表 |
| POST | `/api/admin/services` | 创建客服 |
| PUT | `/api/admin/services/:id` | 编辑客服 |
| DELETE | `/api/admin/services/:id` | 删除客服 |
| GET | `/api/admin/settings` | 获取设置 |
| PUT | `/api/admin/settings` | 更新设置 |

## 项目结构

```
im-agent-hub/
├── web/
│   ├── h5/                        ← H5 聊天前端（Vue3 + TypeScript）
│   │   └── src/
│   │       ├── views/             ← Chat, Shop（淘宝伪装页）, Login
│   │       ├── components/        ← 消息气泡、输入框、图片预览等
│   │       ├── services/          ← OpenIM SDK 封装
│   │       └── stores/            ← 用户状态、聊天状态
│   │
│   └── admin/                     ← 管理后台（Vue3 + Element Plus）
│       └── src/
│           ├── views/             ← 登录、仪表盘、用户/客服管理、设置
│           └── components/        ← 布局、表格、表单等
│
├── server/                        ← Go 业务后端（Gin）
│   ├── api/                       ← HTTP 路由和处理器
│   ├── service/                   ← 业务逻辑
│   ├── model/                     ← 数据模型
│   ├── database/                  ← SQLite 初始化
│   ├── config/                    ← 配置
│   └── pkg/                       ← JWT、响应工具
│
├── Dockerfile                     ← 多阶段构建
├── docker-compose.yml
└── Makefile
```

## 用户登录流程

```
1. 管理员在后台创建用户 → 生成用户 ID（如 user_abc123）
2. 管理员在后台生成登录链接：https://domain/chat?id=user_abc123
3. 将链接发给用户
4. 用户点击链接 → H5 页面提取 id 参数
5. 前端调用 POST /api/client/auth/login { userId: "user_abc123" }
6. 后端验证用户存在 → 调用 OpenIM API 获取 userToken
7. 前端用 token 初始化 OpenIM SDK，连接 WebSocket
8. 自动打开与绑定客服的会话
```

## 注意事项

1. 每个代理需要独立部署一套，包括 OpenIM Server 和本项目
2. 生产环境务必修改 `jwt_secret` 和管理员密码
3. MinIO（文件存储）由 OpenIM Server 自带管理，图片和文件通过 OpenIM API 上传
4. 语音消息录制需要 HTTPS 环境（浏览器安全限制）