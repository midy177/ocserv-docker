#!/bin/bash
set -euo pipefail

# =============================================================================
# OCServ Quick Deploy Script
# 快速部署 OCServ VPN 到 Kubernetes
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly REPO_URL="${REPO_URL:-https://yourusername.github.io/ocserv-docker}"
readonly CHART_NAME="ocserv"
readonly NAMESPACE="${NAMESPACE:-default}"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# =============================================================================
# Functions
# =============================================================================

check_dependencies() {
    log_info "检查依赖..."
    
    local deps=("helm" "kubectl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log_error "$dep 未安装，请先安装 $dep"
            echo ""
            echo "安装方法："
            echo "  Helm: https://helm.sh/docs/intro/install/"
            echo "  kubectl: https://kubernetes.io/docs/tasks/tools/"
            exit 1
        fi
    done
    
    log_info "依赖检查完成"
}

add_helm_repo() {
    log_info "添加 Helm 仓库..."
    
    if helm repo list | grep -q "^ocserv"; then
        log_info "OCServ 仓库已存在，更新中..."
        helm repo update ocserv
    else
        helm repo add ocserv "$REPO_URL"
    fi
}

create_namespace() {
    if [[ "$NAMESPACE" != "default" ]]; then
        log_info "创建命名空间: $NAMESPACE"
        kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    fi
}

install_chart() {
    log_info "安装 OCServ Helm Chart..."
    
    local install_cmd="helm install $CHART_NAME ocserv/$CHART_NAME"
    
    if [[ "$NAMESPACE" != "default" ]]; then
        install_cmd="$install_cmd --namespace $NAMESPACE"
    fi
    
    # 添加常用配置选项
    install_cmd="$install_cmd --set routeInjector.enabled=true"
    install_cmd="$install_cmd --set network.defaultDomain=vpn.example.com"
    
    log_info "执行安装命令: $install_cmd"
    eval "$install_cmd"
}

show_success_info() {
    log_info "OCServ 安装完成！"
    echo ""
    echo "🎯 后续操作："
    echo ""
    echo "1. 检查部署状态:"
    if [[ "$NAMESPACE" != "default" ]]; then
        echo "   kubectl get pods -n $NAMESPACE"
        echo "   kubectl get svc -n $NAMESPACE"
    else
        echo "   kubectl get pods"
        echo "   kubectl get svc"
    fi
    echo ""
    echo "2. 获取 NodePort (如果使用 NodePort):"
    if [[ "$NAMESPACE" != "default" ]]; then
        echo "   kubectl get svc $CHART_NAME -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}'"
    else
        echo "   kubectl get svc $CHART_NAME -o jsonpath='{.spec.ports[0].nodePort}'"
    fi
    echo ""
    echo "3. 连接 VPN:"
    echo "   服务器地址: <你的节点IP>:<NodePort>"
    echo "   用户名: admin (默认)"
    echo "   密码: 查看 values.yaml 或使用自定义密码"
    echo ""
    echo "4. 更多信息:"
    echo "   项目主页: $REPO_URL"
    echo "   文档地址: $REPO_URL#configuration"
}

show_usage() {
    echo "用法: $SCRIPT_NAME [选项]"
    echo ""
    echo "选项:"
    echo "  -n, --namespace NAMESPACE    指定 Kubernetes 命名空间 (默认: default)"
    echo "  -r, --repo URL              指定 Helm 仓库地址"
    echo "  -h, --help                 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $SCRIPT_NAME                           # 使用默认配置安装"
    echo "  $SCRIPT_NAME -n vpn                    # 安装到 vpn 命名空间"
    echo "  $SCRIPT_NAME -r https://custom.repo.com   # 使用自定义仓库"
}

# =============================================================================
# Main
# =============================================================================

main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -r|--repo)
                REPO_URL="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log_info "开始 OCServ 快速部署..."
    echo "配置信息："
    echo "  仓库地址: $REPO_URL"
    echo "  Chart 名称: $CHART_NAME"
    echo "  命名空间: $NAMESPACE"
    echo ""
    
    check_dependencies
    add_helm_repo
    create_namespace
    install_chart
    show_success_info
}

# =============================================================================
# Script Entry
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi