# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

TKE 实践指南 - 腾讯云 TKE (Tencent Kubernetes Engine) 的实战经验电子书，使用 Docusaurus 构建。

在线地址: https://imroc.cc/tke

## 常用命令

```bash
# 安装依赖
npm install

# 本地开发服务器
npm start

# 构建静态站点
npm run build

# 类型检查
npm run typecheck

# 清理缓存
npm run clear

# 本地预览构建结果
npm run serve
```

## 项目架构

### 目录结构

- `docs/` - Markdown 文档内容，按主题分类（networking、storage、autoscaling 等）
- `codeblock/` - 可复用的代码示例文件（YAML 配置等），通过 FileBlock 组件引用
- `src/components/` - 自定义 React 组件
- `src/theme/` - Docusaurus 主题覆盖
- `sidebars.ts` - 侧边栏导航配置
- `docusaurus.config.ts` - 站点配置

### 自定义组件

**FileBlock** - 用于在文档中引用 `codeblock/` 目录下的代码文件：

```jsx
<FileBlock file="nginx.yaml" />
<FileBlock file="nginx.yaml" showFileName />
```

也可引用任意位置的文件：

```jsx
<FileBlock file="@site/docs/example.yaml" />
```

### 代码高亮标记

支持自定义魔法注释用于高亮代码行：

- `// highlight-next-line` - 高亮下一行
- `// highlight-add-line` - 标记为新增行（绿色）
- `// highlight-update-line` - 标记为更新行
- `// highlight-error-line` - 标记为错误行

## 内容编写

- 文档使用 MDX 格式，支持在 Markdown 中使用 React 组件
- 新增文档后需在 `sidebars.ts` 中添加对应条目
- 代码示例优先放在 `codeblock/` 目录并用 FileBlock 引用，便于复用和维护

## 多语言支持

本项目支持中英双语，默认使用中文。

### 目录结构

- `docs/` - 中文文档（默认语言）
- `i18n/en/docusaurus-plugin-content-docs/current/` - 英文翻译文档
- `i18n/en/docusaurus-plugin-content-docs/current.json` - 侧边栏目录名称翻译

### 翻译流程

当用户说"翻译 @xxx.md"时，执行中译英：

1. **翻译文档内容**：将 `docs/` 下的中文文档翻译为英文，放到 `i18n/en/docusaurus-plugin-content-docs/current/` 对应路径下
   - 例如：`docs/networking/pod-eip.md` → `i18n/en/docusaurus-plugin-content-docs/current/networking/pod-eip.md`

2. **翻译目录名称**（如有新目录）：在 `i18n/en/docusaurus-plugin-content-docs/current.json` 中添加侧边栏分类的英文翻译，格式：
   ```json
   "sidebar.tkeSidebar.category.中文目录名": {
     "message": "English Category Name",
     "description": "The label for category 中文目录名 in sidebar tkeSidebar"
   }
   ```

### 本地预览英文版

```bash
npm start -- --locale en
```
