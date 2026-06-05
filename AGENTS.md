## 项目概述

TKE 实践指南 - 腾讯云 TKE (Tencent Kubernetes Engine) 的实战经验电子书，使用 Docusaurus 构建。

- **在线地址**：https://imroc.cc/tke
- **作者**：roc（腾讯云 TKE 团队）
- **定位**：个人 TKE 实践经验沉淀，同时作为客户文档参考（有对应方案时直接抛链接给客户）
- **相关电子书**：[kubernetes 实践指南](https://imroc.cc/kubernetes)
- **CI/CD**：本项目通过 GitOps 自动将改动编译并同步到在线电子书。`git push` 后将自动触发 CI 流水线，编译后部署到在线站点，通常有**几分钟的延迟**才生效（具体时长取决于 CI 队列与构建速度）。建议在每次 push 后等待在线站点确认更新。

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

### 全局可用 MDX 组件

在 `src/theme/MDXComponents.tsx` 中注册了以下组件，文档中可直接使用无需 import：

- `FileBlock` - 引用代码文件
- `CodeBlock` - 代码块
- `Tabs` / `TabItem` - 标签页切换

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

支持自定义魔法注释用于高亮代码行（单行和块注释两种形式）：

| 效果     | 单行注释（高亮下一行）     | 块注释（高亮区间）                                        |
| -------- | -------------------------- | --------------------------------------------------------- |
| 普通高亮 | `// highlight-next-line`   | `// highlight-start` ... `// highlight-end`               |
| 新增行   | `// highlight-add-line`    | `// highlight-add-start` ... `// highlight-add-end`       |
| 更新行   | `// highlight-update-line` | `// highlight-update-start` ... `// highlight-update-end` |
| 错误行   | `// highlight-error-line`  | `// highlight-error-start` ... `// highlight-error-end`   |

注释前缀 `//` 适用于 YAML 时替换为 `#`。

## 内容编写

- 文档使用 MDX 格式，支持在 Markdown 中使用 React 组件
- 新增文档后需在 `sidebars.ts` 中添加对应条目（sidebar 名为 `tkeSidebar`）
- 代码示例优先放在 `codeblock/` 目录并用 FileBlock 引用，便于复用和维护
- 文档路由前缀为 `/`（docs 即站点根路径），如 `docs/networking/pod-eip.md` 对应 URL `/tke/networking/pod-eip`
- 支持 Mermaid 图表（已启用 `@docusaurus/theme-mermaid`）
- 支持图片缩放（`docusaurus-plugin-zooming`）
- 每篇文档底部自动展示 Giscus 评论（通过 `src/theme/DocItem/Layout/index.tsx` 注入）

### 文档主题分类

| 目录               | 内容                                         |
| ------------------ | -------------------------------------------- |
| `networking/`      | 网络指南（CNI、Ingress、Service、DNS 等）    |
| `storage/`         | 存储指南（CBS、CFS）                         |
| `autoscaling/`     | 弹性伸缩（KEDA、超级节点预占）               |
| `ai/`              | AI 推理部署（SGLang、vLLM、Ollama）          |
| `game/`            | 游戏方案（OKG、Agones、房间网络）            |
| `monitoring/`      | 监控指南（Prometheus、Grafana）              |
| `opa/`             | OPA 策略管理（Gatekeeper）                   |
| `images/`          | 镜像与仓库                                   |
| `deploy/`          | 常见应用部署（cert-manager、Harbor、GitLab） |
| `apps/`            | 应用管理（原地升级等）                       |
| `faq/`             | 常见问题                                     |
| `troubleshooting/` | 故障排查                                     |
| `appendix/`        | 附录（实用 YAML、kubectl 脚本、错误码）      |

## 多语言支持

本项目支持中英双语，默认使用中文。

### 目录结构

- `docs/` - 中文文档（默认语言）
- `i18n/en/docusaurus-plugin-content-docs/current/` - 英文翻译文档
- `i18n/en/docusaurus-plugin-content-docs/current.json` - 侧边栏目录名称翻译

### 自动同步翻译（必须遵守）

对 `docs/` 下的文档执行任何操作时，**必须**自动同步到英文版（`i18n/en/docusaurus-plugin-content-docs/current/` 对应路径）。具体规则：

1. **修改文档**：将修改的部分同步翻译到对应英文文件。如果英文文件不存在，则创建完整的英文翻译
2. **新增文档**：同时在对应路径下创建英文翻译
3. **删除文档**：同步删除对应的英文文件
4. **重命名/移动文档**：同步重命名/移动对应的英文文件
5. **新增侧边栏目录**：在 `i18n/en/docusaurus-plugin-content-docs/current.json` 中添加目录名翻译，格式：
   ```json
   "sidebar.tkeSidebar.category.中文目录名": {
     "message": "English Category Name",
     "description": "The label for category 中文目录名 in sidebar tkeSidebar"
   }
   ```

路径映射示例：`docs/networking/pod-eip.md` → `i18n/en/docusaurus-plugin-content-docs/current/networking/pod-eip.md`

### 手动翻译

当用户说"翻译 @xxx.md"时（一个或多个 md 文件），执行中译英：

1. **翻译文档内容**：将 `docs/` 下的中文文档翻译为英文，放到 `i18n/en/docusaurus-plugin-content-docs/current/` 对应路径下
   - 如果文档已存在，则对比中文版本和英文版本，只更新差异部分

2. **翻译目录名称**（如有新目录）：同"自动同步翻译"第 5 条

### 本地预览英文版

```bash
npm start -- --locale en
```

## 注意事项

- 任何修改自动 commit 并 push，无需确认
- commit message 使用中文
