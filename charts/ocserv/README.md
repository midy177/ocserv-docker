# OCServ Helm Chart

这是一个用于在 Kubernetes 集群中部署 OCServ (OpenConnect VPN Server) 的 Helm Chart。

## 功能特性

- 完整的 OCServ VPN 服务器部署
- 支持自定义 DNS、路由和网段配置
- 可选的 LDAP 认证支持
- 自动路由注入机制
- 灵活的配置选项

## 前置要求

- Kubernetes 1.19+
- Helm 3.0+
- 具有足够权限创建 RBAC 资源的集群访问权限

## 安装

### 基本安装

```bash
helm install ocserv ./charts/ocserv
```

### 使用自定义配置安装

```bash
helm install ocserv ./charts/ocserv -f my-values.yaml
```

### 指定命名空间

```bash
helm install ocserv ./charts/ocserv -n vpn --create-namespace
```

## 配置说明

### 核心配置参数

#### 网络配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `network.podCidr` | Kubernetes Pod CIDR | `10.0.0.0/16` |
| `network.vpn.cidr` | VPN 网络 CIDR（ipv4Network 和 ipv4Netmask 自动生成） | `10.7.7.0/24` |
| `network.dns` | DNS 服务器列表 | `["172.20.0.10"]` |
| `network.routes` | 推送给客户端的路由 | `["10.0.0.0/16", "172.20.0.0/16"]` |
| `network.defaultDomain` | 默认域名 | `ocserv.example.com` |

#### OCServ 环境变量

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `ocserv.env.caOrg` | CA 组织名称 | `yeastar` |
| `ocserv.env.servOrg` | 服务器组织名称 | `ys_ops` |
| `ocserv.env.userId` | 用户 ID | `6X2m13^sssdegrDS@` |

#### 服务配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `service.type` | Service 类型 | `NodePort` |
| `service.tcpPort` | TCP 端口 | `4443` |
| `service.udpPort` | UDP 端口 | `4443` |

#### 镜像配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `image.repository` | 镜像仓库 | `1228022817/ocserv` |
| `image.tag` | 镜像标签 | `latest` |
| `image.digest` | 镜像摘要（可选） | `sha256:4d99e883...` |
| `image.pullPolicy` | 镜像拉取策略 | `IfNotPresent` |

### LDAP 配置（可选）

要启用 LDAP 认证，请设置 `ldap.enabled=true` 并配置以下参数：

```yaml
ldap:
  enabled: true
  uri: "ldap://your-ldap-server/"
  base: "dc=example,dc=com"
  bindDn: "cn=admin,dc=example,dc=com"
  bindPassword: "your-password"
```

### 用户凭证

默认用户凭证通过 `users.credentials` 参数配置。格式为：`username:*:hashed_password`

要生成密码哈希，可以使用 `ocpasswd` 工具：

```bash
ocpasswd -c /tmp/ocpasswd username
```

## 使用示例

### 示例 1：修改 VPN 网段

创建 `my-values.yaml` 文件：

```yaml
network:
  vpn:
    cidr: "10.8.0.0/24"
```

应用配置：

```bash
helm upgrade ocserv ./charts/ocserv -f my-values.yaml
```

### 示例 2：修改 DNS 服务器

```yaml
network:
  dns:
    - "8.8.8.8"
    - "8.8.4.4"
```

### 示例 3：添加自定义路由

```yaml
network:
  routes:
    - "10.0.0.0/8"
    - "172.16.0.0/12"
    - "192.168.0.0/16"
```

### 示例 4：禁用路由注入

```yaml
routeInjector:
  enabled: false
```

### 示例 5：使用 LoadBalancer 服务

```yaml
service:
  type: LoadBalancer
  tcpPort: 443
  udpPort: 443
```

## 升级

```bash
helm upgrade ocserv ./charts/ocserv -f my-values.yaml
```

## 卸载

```bash
helm uninstall ocserv
```

## 故障排查

### 查看 Pod 日志

```bash
kubectl logs -f deployment/ocserv
```

### 查看初始化容器日志

```bash
kubectl logs -f deployment/ocserv -c route-injector-init
```

### 查看 ConfigMap

```bash
kubectl get configmap ocserv-config -o yaml
```

### 查看 Service

```bash
kubectl get svc ocserv
```

## 从原始 YAML 迁移

此 Helm Chart 是从 `deploy/deploy.yaml` 转换而来，主要改进包括：

1. **参数化配置**：所有关键配置（DNS、路由、网段等）都已抽象到 `values.yaml`
2. **模板化资源**：所有 Kubernetes 资源都使用 Helm 模板
3. **版本管理**：支持 Helm 的版本管理和回滚功能
4. **灵活部署**：可以轻松调整配置而无需修改模板文件

## 注意事项

1. **安全性**：建议在生产环境中使用 Secrets 管理敏感信息（如密码、证书等）
2. **网络策略**：确保集群网络策略允许必要的流量
3. **资源限制**：建议根据实际负载设置资源限制
4. **备份**：定期备份配置和证书

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

与原项目保持一致