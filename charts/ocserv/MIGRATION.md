# 从 deploy/deploy.yaml 到 Helm Chart 的迁移指南

## 概述

本文档说明了如何从原始的 `deploy/deploy.yaml` 迁移到新的 Helm Chart。

## 主要变化

### 1. 文件结构

**原始结构：**
```
deploy/deploy.yaml  (单一文件，包含所有资源)
```

**新结构：**
```
charts/ocserv/
├── Chart.yaml                    # Chart 元数据
├── values.yaml                   # 可配置参数
├── values-example.yaml           # 示例配置
├── README.md                     # 使用文档
└── templates/                    # 模板文件
    ├── _helpers.tpl             # 辅助模板
    ├── rbac.yaml                # RBAC 资源
    ├── serviceaccount.yaml      # ServiceAccount
    ├── configmap.yaml           # ConfigMap
    ├── deployment.yaml          # Deployment
    ├── service.yaml             # Service
    ├── ingress.yaml             # Ingress (可选)
    ├── hpa.yaml                 # HPA (可选)
    └── httproute.yaml           # HTTPRoute (可选)
```

### 2. 配置参数映射

以下是原始 YAML 中的硬编码值到 values.yaml 参数的映射：

| 原始位置 | 原始值 | values.yaml 参数 |
|----------|--------|------------------|
| ConfigMap: ocserv.conf - dns | `172.20.0.10` | `network.dns[0]` |
| ConfigMap: ocserv.conf - route | `10.0.0.0/16` | `network.routes[0]` |
| ConfigMap: ocserv.conf - route | `172.20.0.0/16` | `network.routes[1]` |
| ConfigMap: ocserv.conf - ipv4-network | `10.7.7.0` | `network.vpn.ipv4Network` |
| ConfigMap: ocserv.conf - ipv4-netmask | `255.255.255.0` | `network.vpn.ipv4Netmask` |
| ConfigMap: ocserv.conf - default-domain | `ocserv.example.com` | `network.defaultDomain` |
| Deployment: env - POD_CIDR | `10.0.0.0/16` | `network.podCidr` |
| Deployment: env - VPN_CIDR | `10.7.7.0/24` | `network.vpn.cidr` |
| Deployment: env - CA_ORG | `yeastar` | `ocserv.env.caOrg` |
| Deployment: env - SERV_DOMAIN | `x5j85ws-rditspp.exampe.com` | `ocserv.env.servDomain` |
| Deployment: env - SERV_ORG | `ys_ops` | `ocserv.env.servOrg` |
| Deployment: env - USER_ID | `6X2m13^sssdegrDS@` | `ocserv.env.userId` |
| Deployment: image | `1228022817/ocserv:latest@sha256:...` | `image.repository`, `image.tag`, `image.digest` |
| Deployment: replicas | `1` | `replicaCount` |
| ConfigMap: ocserv.conf - tcp-port | `4443` | `service.tcpPort` 和 `ocserv.config.tcpPort` |
| ConfigMap: ocserv.conf - udp-port | `4443` | `service.udpPort` 和 `ocserv.config.udpPort` |

### 3. 资源对应关系

| 原始 deploy.yaml | Helm Chart 模板 |
|------------------|-----------------|
| Role | `templates/rbac.yaml` |
| ServiceAccount | `templates/serviceaccount.yaml` |
| RoleBinding | `templates/rbac.yaml` |
| ConfigMap (ocserv-config) | `templates/configmap.yaml` |
| ConfigMap (route-injector-manifest) | `templates/configmap.yaml` |
| Deployment | `templates/deployment.yaml` |
| Service (新增) | `templates/service.yaml` |

### 4. 迁移步骤

#### 步骤 1：备份现有配置

```bash
kubectl get deployment ocserv -o yaml > ocserv-backup.yaml
kubectl get configmap ocserv-config -o yaml > ocserv-config-backup.yaml
```

#### 步骤 2：删除原有部署（可选）

```bash
kubectl delete -f deploy/deploy.yaml
```

#### 步骤 3：自定义 values.yaml

复制 `values-example.yaml` 并根据需求修改：

```bash
cp charts/ocserv/values-example.yaml my-values.yaml
# 编辑 my-values.yaml
```

#### 步骤 4：验证配置

```bash
helm template ocserv charts/ocserv -f my-values.yaml > rendered.yaml
# 检查 rendered.yaml 确保配置正确
```

#### 步骤 5：部署

```bash
helm install ocserv charts/ocserv -f my-values.yaml
```

或者升级现有部署：

```bash
helm upgrade ocserv charts/ocserv -f my-values.yaml
```

### 5. 配置修改对比

**原始方式：**
1. 编辑 `deploy/deploy.yaml`
2. 找到需要修改的配置项（可能在多个位置）
3. 手动修改硬编码的值
4. `kubectl apply -f deploy/deploy.yaml`

**Helm Chart 方式：**
1. 编辑 `my-values.yaml`（所有配置集中在一个地方）
2. `helm upgrade ocserv charts/ocserv -f my-values.yaml`

### 6. 常见配置修改示例

#### 修改 VPN 网段

**原始方式：**
需要修改 deploy.yaml 的多个位置：
- ConfigMap 中的 `ipv4-network`
- ConfigMap 中的 `ipv4-netmask`
- Deployment initContainer 中的 `VPN_CIDR`

**Helm Chart 方式：**
只需修改 values.yaml：
```yaml
network:
  vpn:
    ipv4Network: "10.8.0.0"
    ipv4Netmask: "255.255.255.0"
    cidr: "10.8.0.0/24"
```

#### 修改 DNS 服务器

**原始方式：**
编辑 ConfigMap 中的 `dns` 行

**Helm Chart 方式：**
```yaml
network:
  dns:
    - "8.8.8.8"
    - "8.8.4.4"
```

#### 添加路由

**原始方式：**
在 ConfigMap 中添加新的 `route` 行

**Helm Chart 方式：**
```yaml
network:
  routes:
    - "10.0.0.0/8"
    - "172.16.0.0/12"
    - "192.168.0.0/16"
```

### 7. 新增功能

Helm Chart 提供了一些原始 YAML 没有的功能：

1. **版本管理和回滚**
   ```bash
   helm rollback ocserv 1
   ```

2. **灵活的 Service 类型**
   可以轻松切换到 LoadBalancer、ClusterIP 等

3. **可选的 LDAP 支持**
   通过 `ldap.enabled` 开关

4. **资源限制配置**
   通过 `resources` 参数

5. **自动配置更新检测**
   Deployment 包含 ConfigMap 的 checksum，配置变更会自动触发 Pod 重启

### 8. 验证迁移成功

```bash
# 检查 Helm release
helm list

# 检查 Pod 状态
kubectl get pods -l app.kubernetes.io/name=ocserv

# 检查 Service
kubectl get svc -l app.kubernetes.io/name=ocserv

# 查看日志
kubectl logs -f deployment/ocserv

# 测试连接
# (使用 VPN 客户端连接到服务)
```

### 9. 故障排查

如果遇到问题，可以：

1. 查看渲染后的 YAML：
   ```bash
   helm get manifest ocserv
   ```

2. 查看 Helm 值：
   ```bash
   helm get values ocserv
   ```

3. 回滚到之前的版本：
   ```bash
   helm rollback ocserv
   ```

### 10. 最佳实践

1. **版本控制**：将 `my-values.yaml` 加入版本控制系统
2. **敏感信息**：使用 Kubernetes Secrets 管理密码等敏感信息
3. **环境隔离**：为不同环境（开发、测试、生产）使用不同的 values 文件
4. **备份**：定期备份 Helm values 和证书

## 总结

使用 Helm Chart 的主要优势：

- **参数化**：所有配置集中管理，易于修改
- **可重用**：可以在多个环境中使用相同的 Chart
- **版本管理**：支持版本控制和回滚
- **模板化**：减少重复配置
- **标准化**：符合 Kubernetes 社区最佳实践