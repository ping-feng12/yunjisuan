#!/bin/bash
set -euo pipefail  # 遇到错误立即退出，避免隐藏问题

# ==============================================
# 配置区（可根据实际情况修改）
# ==============================================
PROJECT_NAME="my-web-app"          # 项目名称（用于Docker网络/容器前缀）
COMPOSE_FILE="docker-compose.yml"  # 编排文件路径（默认当前目录）
SERVICE_PORT=8080                  # 前端服务端口（需与docker-compose.yml一致）
REQUIRED_DOCKER_VERSION="20.10"    # 最低Docker版本要求
REQUIRED_COMPOSE_VERSION="2.0"     # 最低Docker Compose版本要求


# ==============================================
# 函数：打印带颜色的日志
# ==============================================
log_info() { echo -e "\033[34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[32m[SUCCESS]\033[0m $*"; }
log_error() { echo -e "\033[31m[ERROR]\033[0m $*" >&2; }


# ==============================================
# 步骤1：检查操作系统（仅支持Ubuntu 22.04）
# ==============================================
check_os() {
    if ! grep -q "Ubuntu 22.04" /etc/os-release; then
        log_error "当前系统不是Ubuntu 22.04，可能无法正常运行！"
        exit 1
    fi
    log_info "检测到Ubuntu 22.04系统，继续..."
}


# ==============================================
# 步骤2：检查并安装Docker
# ==============================================
install_docker() {
    if command -v docker &> /dev/null; then
        log_info "Docker已安装，版本：$(docker --version | awk '{print $3}' | cut -d',' -f1)"
    else
        log_info "开始安装Docker..."
        # 卸载旧版本
        sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
        # 安装依赖
        sudo apt-get update && sudo apt-get install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release
        # 添加Docker GPG密钥
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        # 设置Docker仓库
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
            https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        # 安装Docker Engine
        sudo apt-get update && sudo apt-get install -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-compose-plugin  # Docker Compose V2（推荐）
        # 启动Docker并设置开机自启
        sudo systemctl enable --now docker
        # 验证安装
        docker --version || { log_error "Docker安装失败！"; exit 1; }
        log_success "Docker安装成功"
    fi
}


# ==============================================
# 步骤3：检查Docker Compose（V2优先，兼容V1）
# ==============================================
check_compose() {
    if command -v docker compose &> /dev/null; then
        COMPOSE_CMD="docker compose"
        COMPOSE_VERSION=$(${COMPOSE_CMD} version --short)
        log_info "Docker Compose V2已安装，版本：${COMPOSE_VERSION}"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        COMPOSE_VERSION=$(${COMPOSE_CMD} --version | awk '{print $3}' | cut -d',' -f1)
        log_info "Docker Compose V1已安装，版本：${COMPOSE_VERSION}"
    else
        log_error "未找到Docker Compose！请检查Docker安装是否正确"
        exit 1
    fi

    # 检查版本是否满足要求
    if [[ "${COMPOSE_VERSION}" < "${REQUIRED_COMPOSE_VERSION}" ]]; then
        log_error "Docker Compose版本过低（需≥${REQUIRED_COMPOSE_VERSION}，当前${COMPOSE_VERSION}）"
        exit 1
    fi
}


# ==============================================
# 步骤4：修复文件权限（避免root属主问题）
# ==============================================
fix_permissions() {
    log_info "修复项目文件权限..."
    # 递归设置当前目录及子文件的所有者为当前用户（避免sudo启动容器后文件属主为root）
    sudo chown -R "$USER:$USER" ./*
    # 给脚本添加执行权限（防止复制后无权限）
    chmod +x "$0"  # 给自身脚本加执行权限（可选）
    log_success "权限修复完成"
}


# ==============================================
# 步骤5：启动服务（docker-compose up -d）
# ==============================================
start_services() {
    if [ ! -f "${COMPOSE_FILE}" ]; then
        log_error "未找到 ${COMPOSE_FILE}！请确保文件存在于当前目录"
        exit 1
    fi

    log_info "启动服务（使用 ${COMPOSE_CMD}）..."
    ${COMPOSE_CMD} up -d --build  # --build 强制重新构建镜像（如需跳过可去掉）

    # 等待服务启动（最多等60秒，避免启动慢导致验证失败）
    log_info "等待服务启动（最多60秒）..."
    local timeout=60
    while [ $timeout -gt 0 ]; do
        if ${COMPOSE_CMD} ps | grep -q "Up"; then
            break
        fi
        sleep 5
        timeout=$((timeout - 5))
    done

    if [ $timeout -le 0 ]; then
        log_error "服务启动超时！请查看日志：${COMPOSE_CMD} logs"
        exit 1
    fi
    log_success "服务启动成功"
}


# ==============================================
# 步骤6：验证服务状态
# ==============================================
verify_services() {
    log_info "验证服务状态..."
    # 显示容器运行状态
    ${COMPOSE_CMD} ps
    
    # 验证前端服务是否可访问
    log_info "验证前端服务（端口 ${SERVICE_PORT}）..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${SERVICE_PORT}" | grep -q "200"; then
        log_success "前端服务访问正常（http://localhost:${SERVICE_PORT}）"
    else
        log_warn "前端服务暂时无法访问，可能仍在启动中（可稍后重试）"
    fi

    # 验证数据库连接（需后端服务暴露健康检查接口，或通过日志判断）
    log_info "验证后端与数据库连接..."
    if ${COMPOSE_CMD} logs backend | grep -q "Connected to database"; then
        log_success "后端成功连接数据库"
    else
        log_warn "后端数据库连接日志未找到，请检查后端代码或日志：${COMPOSE_CMD} logs backend"
    fi
}


# ==============================================
# 主流程
# ==============================================
main() {
    log_info "===== 开始初始化 ${PROJECT_NAME} ====="
    check_os
    install_docker
    check_compose
    fix_permissions
    start_services
    verify_services
    log_success "===== 初始化完成！====="
    echo -e "\n🎉 服务已启动，可通过以下方式访问："
    echo -e "  - 前端页面：\033[34mhttp://localhost:${SERVICE_PORT}\033[0m"
    echo -e "  - 查看服务状态：${COMPOSE_CMD} ps"
    echo -e "  - 停止服务：${COMPOSE_CMD} down\n"
}

# 执行主函数
main