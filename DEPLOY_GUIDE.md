# GitHub Pages Deployment Guide

## 📋 部署步骤

### 1. 启用 GitHub Pages
1. 进入仓库 Settings → Pages
2. 选择 "Deploy from a branch"
3. 选择 `gh-pages` 分支，根目录 `/`
4. 保存设置

### 2. 创建 gh-pages 分支
```bash
# 创建并切换到 gh-pages 分支
git checkout --orphan gh-pages
git reset --hard

# 添加需要发布的文件
git add index.html
git add charts/

# 提交
git commit -m "Add GitHub Pages site with Helm chart"

# 推送分支
git push origin gh-pages
```

### 3. 更新 Chart 仓库配置
创建 `index.yaml` 文件用于 Helm 仓库索引：
```bash
helm package ./charts/ocserv
helm repo index . --url https://yourusername.github.io/ocserv-docker/
```

### 4. 自动化部署（可选）
创建 GitHub Actions 工作流：

```yaml
# .github/workflows/deploy-pages.yml
name: Deploy GitHub Pages

on:
  push:
    branches: [ main ]
    paths:
      - 'charts/ocserv/**'
      - 'index.html'

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pages: write
    steps:
    - uses: actions/checkout@v4
    - name: Setup Helm
      uses: azure/setup-helm@v3
      with:
        version: 'v3.12.0'
    
    - name: Package Chart
      run: |
        helm package ./charts/ocserv --destination ./docs
        helm repo index ./docs --url https://yourusername.github.io/ocserv-docker/
    
    - name: Setup Pages
      uses: actions/configure-pages@v3
    
    - name: Upload artifact
      uses: actions/upload-pages-artifact@v2
      with:
        path: ./docs
    
    - name: Deploy to GitHub Pages
      id: deployment
      uses: actions/deploy-pages@v2
```

## 🎯 访问地址

部署完成后，Helm Chart 和文档将通过以下地址访问：

- **主页**: https://yourusername.github.io/ocserv-docker/
- **Chart 仓库**: https://yourusername.github.io/ocserv-docker/index.yaml

## 🔄 更新流程

### 自动更新
1. 修改 Chart 或 index.html
2. 推送到 main 分支
3. GitHub Actions 自动部署到 gh-pages

### 手动更新
1. 修改 Chart 或 index.html
2. 切换到 gh-pages 分支
3. 同步 main 分支的更改
4. 推送 gh-pages 分支

## 📦 Helm 仓库配置

用户可以通过以下方式添加仓库：

```bash
helm repo add ocserv https://yourusername.github.io/ocserv-docker/
helm repo update
helm install ocserv/ocserv
```

## 🛠️ 本地开发

```bash
# 启动本地服务器预览
python3 -m http.server 8000

# 或者使用 Node.js
npx serve .

# 访问 http://localhost:8000
```

## 📝 自定义域名

可以在仓库设置中配置自定义域名：

1. Settings → Pages
2. Custom domain
3. 添加 CNAME 或 A 记录
4. 更新 index.html 中的仓库链接