# 基于 Docker 的三层 Web 应用容器化部署项目

本项目通过 **Docker + Docker Compose** 实现三层 Web 应用（前端 Nginx + 后端 Node.js + 数据库 MySQL）的容器化部署，解决传统部署中“环境不一致”“多服务协同繁琐”的痛点，支持**一键启动/停止**、**数据持久化**、**服务网络隔离**。

## 快速开始（一键复现）

### 1. 环境准备

操作系统：Ubuntu 22.04 LTS（推荐，脚本已适配）

权限：当前用户需加入 `docker`组（脚本会自动处理，或手动执行 `sudo usermod -aG docker $USER`后重启）

### 2. 克隆项目并启动

```bash
# 1. 克隆项目（替换为你的仓库地址）
git clone https://github.com/your-username/my-web-app.git
cd my-web-app

# 2. 赋予脚本执行权限
chmod +x setup.sh

# 3. 一键启动服务（自动安装依赖+构建镜像+启动容器）
./setup.sh
```

### 3. 验证服务

前端访问：打开浏览器访问 `http://localhost:8080`（默认端口，可在 `docker-compose.yml`中修改）；

后端 API：访问 `http://localhost:5000/api/users`（需后端实现对应接口）；

服务状态：执行 `docker compose ps`查看所有容器状态（需为 `Up`）。

## 项目目录结构

```markdown
my-web-app/                  # 项目根目录
├── frontend/                 # 前端服务（Nginx）
│   ├── Dockerfile            # 前端镜像构建文件
│   └── index.html            # 前端页面（示例）
├── backend/                  # 后端服务（Node.js）
│   ├── Dockerfile            # 后端镜像构建文件
│   ├── app.js                # 后端入口文件（示例）
│   └── package.json          # 后端依赖配置
├── database/                 # 数据库数据目录（持久化存储）
│   └── data/                 # MySQL 数据卷挂载点（自动生成）
├── scripts/                  # 辅助脚本
│   ├── start.sh              # 启动服务（调用 docker compose up -d）
│   └── stop.sh               # 停止服务（调用 docker compose down）
├── docker-compose.yml        # 多服务编排配置
├── setup.sh                  # 一键初始化脚本（安装依赖+启动服务）
└── README.md                 # 项目说明文档
```

## 常用命令

| 操作               | 命令                                                         | 说明                        |
| ------------------ | ------------------------------------------------------------ | --------------------------- |
| 启动服务           | `./setup.sh`或 `docker compose up -d`                        | 后台启动所有服务            |
| 停止服务           | `docker compose down`                                        | 停止并删除容器（数据保留）  |
| 查看服务状态       | `docker compose ps`                                          | 显示容器运行状态            |
| 查看实时日志       | `docker compose logs -f`                                     | 跟踪服务日志（Ctrl+C 退出） |
| 重新构建镜像       | `docker compose up -d --build`                               | 强制重新构建所有镜像        |
| 进入容器（如后端） | `docker compose exec backend sh`                             | 进入后端容器终端            |
| 备份数据库         | `docker compose exec db mysqldump -u root -p app_db > backup.sql` | 导出数据库数据              |

## 核心配置说明

### 1. `docker-compose.yml`关键配置

**服务依赖**：`backend`服务通过 `depends_on: [db]`确保数据库先启动；

**数据持久化**：`db`服务通过 `volumes: ./database/data:/var/lib/mysql`将 MySQL 数据挂载到宿主机，避免容器删除后数据丢失；

**网络隔离**：所有服务加入自定义 `app-network`桥接网络，仅允许服务间通过服务名（如 `db`、`backend`）通信。

### 2. 前端 `Dockerfile`（Nginx 示例）

```dockerfile
FROM nginx:alpine                  # 基础镜像（轻量 Alpine 版本）
COPY index.html /usr/share/nginx/html/  # 复制前端页面到 Nginx 默认目录
EXPOSE 80                          # 暴露 80 端口（容器内）
```

### 3. 后端 `Dockerfile`（Node.js 示例）

```dockerfile
FROM node:18-alpine                # 基础镜像（Node.js 18 + Alpine）
WORKDIR /app                       # 设置工作目录
COPY package*.json ./               # 复制依赖配置文件
RUN npm install                    # 安装依赖
COPY . .                           # 复制后端代码
EXPOSE 5000                        # 暴露 5000 端口（容器内）
CMD ["node", "app.js"]             # 启动命令
```

## 注意事项

**权限问题**：若脚本提示“权限不够”，请检查当前用户是否属于 `docker`组（执行 `groups`查看，若无则 `sudo usermod -aG docker $USER`后重启）；

1. **端口冲突**：若 `8080`端口被占用，需修改 `docker-compose.yml`中 `frontend`服务的 `ports`配置（如 `8081:80`）；
2. **数据安全**：`database/data`目录存储 MySQL 数据，请勿手动删除；若需重置数据，可删除该目录后重启服务；
3. **镜像拉取**：若 Docker 拉取镜像缓慢，可修改 `docker-compose.yml`添加国内镜像源（如 `https://hub-mirror.c.163.com`）。

## 故障排除

**服务启动失败**：执行 `docker compose logs [服务名]`查看具体错误（如 `docker compose logs backend`查看后端日志）；

**前端无法访问**：检查 `8080`端口是否被占用（`sudo lsof -i :8080`），或修改 `docker-compose.yml`中的端口映射；

**数据库连接失败**：确保 `docker-compose.yml`中 `db`服务的 `MYSQL_ROOT_PASSWORD`与后端环境变量 `DB_PASS`一致。

## 贡献与反馈

若需修改配置（如更换端口、添加服务），请编辑 `docker-compose.yml`或对应服务的 `Dockerfile`；

欢迎提交 Issue 或 PR 改进项目！