# 多阶段构建 Dockerfile
# 阶段1：构建 H5 前端
FROM node:18-alpine AS h5-builder
WORKDIR /app/web/h5
COPY web/h5/package*.json ./
RUN npm install
COPY web/h5/ ./
RUN npm run build

# 阶段2：构建管理后台前端
FROM node:18-alpine AS admin-builder
WORKDIR /app/web/admin
COPY web/admin/package*.json ./
RUN npm install
COPY web/admin/ ./
RUN npm run build

# 阶段3：构建 Go 后端（PostgreSQL 驱动 pgx 为纯 Go，无需 CGO）
FROM golang:1.21-alpine AS backend-builder
WORKDIR /app/server
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -a -o chat-app .

# 阶段4：最终运行镜像
FROM alpine:latest
WORKDIR /app

# 安装运行时依赖
RUN apk add --no-cache ca-certificates tzdata

# 复制后端二进制
COPY --from=backend-builder /app/server/chat-app .

# 复制前端静态文件
COPY --from=h5-builder /app/web/h5/dist ./static/h5
COPY --from=admin-builder /app/web/admin/dist ./static/admin

# 复制配置文件模板
COPY server/config/config.yaml ./config/

# 创建数据目录
RUN mkdir -p ./data

EXPOSE 8080

CMD ["./chat-app"]
