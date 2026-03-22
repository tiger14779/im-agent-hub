.PHONY: all build dev-h5 dev-admin dev-server build-h5 build-admin build-server docker clean

# 默认目标
all: build

# ===== 开发模式 =====

# 启动 H5 开发服务器（端口 3000）
dev-h5:
	cd web/h5 && npm run dev

# 启动管理后台开发服务器（端口 3001）
dev-admin:
	cd web/admin && npm run dev

# 启动 Go 后端开发服务器（端口 8080）
dev-server:
	cd server && go run main.go

# ===== 构建 =====

# 构建 H5 前端
build-h5:
	cd web/h5 && npm install && npm run build
	rm -rf server/static/h5
	mkdir -p server/static/h5
	cp -r web/h5/dist/. server/static/h5/

# 构建管理后台前端
build-admin:
	cd web/admin && npm install && npm run build
	rm -rf server/static/admin
	mkdir -p server/static/admin
	cp -r web/admin/dist/. server/static/admin/

# 构建 Go 后端
build-server:
	mkdir -p bin
	cd server && CGO_ENABLED=1 go build -o ../bin/chat-app .

# 构建所有
build: build-h5 build-admin build-server

# ===== 安装依赖 =====

install-h5:
	cd web/h5 && npm install

install-admin:
	cd web/admin && npm install

install: install-h5 install-admin
	cd server && go mod download

# ===== Docker =====

# 构建并运行 Docker 容器
docker:
	docker build -t im-agent-hub:latest .

docker-run:
	docker-compose up -d

docker-stop:
	docker-compose down

docker-logs:
	docker-compose logs -f

# ===== 清理 =====

clean:
	rm -rf bin/
	rm -rf web/h5/dist/
	rm -rf web/admin/dist/
	rm -rf server/static/h5/
	rm -rf server/static/admin/
	rm -rf server/data/

# ===== 帮助 =====

help:
	@echo "可用命令："
	@echo "  make dev-h5       - 启动 H5 前端开发服务器 (端口 3000)"
	@echo "  make dev-admin    - 启动管理后台开发服务器 (端口 3001)"
	@echo "  make dev-server   - 启动 Go 后端开发服务器 (端口 8080)"
	@echo "  make build        - 构建所有前端和后端"
	@echo "  make build-h5     - 只构建 H5 前端"
	@echo "  make build-admin  - 只构建管理后台"
	@echo "  make build-server - 只构建 Go 后端"
	@echo "  make docker       - 构建 Docker 镜像"
	@echo "  make docker-run   - 启动 Docker 容器"
	@echo "  make clean        - 清理构建产物"
