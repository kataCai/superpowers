# GitHub 代理 Git 操作 Skill 设计

## 背景

在公司网络环境下，针对 GitHub 执行 `git push`、`git pull`、`git fetch` 时，可能出现以下问题：

- `error: RPC failed; HTTP 302 curl 22 The requested URL returned error: 302`
- `send-pack: unexpected disconnect while reading sideband packet`
- `fatal: the remote end hung up unexpectedly`
- 只读访问正常，但写入或大包上传阶段被公司网络、中间代理或登录跳转拦截

当前已有一份可用参考脚本位于：

- `E:\notes\foam-daily-notes\notes\tools\github-push\setup-git-proxy-and-push.ps1`

该脚本已经验证了以下策略可行：

- 仅对当前仓库写入 Git 本地配置
- 使用 `schannel` 处理 TLS
- 仅对 `https://github.com` 配置 `socks5h` 代理
- 对 `push` 结果做远端哈希校验，避免“报错但实际已成功”的误判

本次目标是在个人 skill 目录中补充一个可复用 skill，用于统一处理这类 GitHub 网络受限场景。

## 目标

新增一个通用 skill，用于在 GitHub 网络受限时，以固定流程执行受代理保护的 Git 操作：

1. 启动 Clash Verge
2. 等待代理可用
3. 执行固定的 GitHub Git 操作
4. 如果 Clash Verge 是本次脚本启动的，则在结束后关闭

## 非目标

以下内容不在本次 skill 范围内：

- 不支持任意 Git 命令字符串透传
- 不处理 GitLab、Gitee 或其他代码托管平台
- 不修改 Git 全局配置
- 不自动处理 merge 冲突
- 不替代仓库自己的同步策略，如 `merge`、`rebase`、`fast-forward only`

## 目标目录

skill 放置目录为：

`E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\`

计划包含以下文件：

- `SKILL.md`
- `invoke-github-git-with-clash.ps1`

## 触发条件

当满足以下任一条件时，应优先考虑使用该 skill：

- 对 GitHub 的 `push`、`pull`、`fetch` 在公司网络下失败
- 错误中出现 `HTTP 302`、`RPC failed`、`remote end hung up unexpectedly`
- 直连 GitHub 只读访问正常，但上传或推送阶段失败
- 已知当前网络环境需要通过 Clash Verge 代理访问 GitHub

## 设计方案

### 方案一：纯文档 skill

仅提供 `SKILL.md`，由使用者手动完成 Clash Verge 启动、Git 命令执行和关闭。

优点：

- 实现最简单
- 风险最低

缺点：

- 复用性较差
- 容易遗漏启动或关闭步骤
- 无法沉淀稳定的自动校验流程

### 方案二：skill + 自包含 PowerShell 脚本

在 skill 目录内同时提供文档和脚本，脚本负责完成 Clash Verge 生命周期控制与固定 Git 操作执行。

优点：

- skill 自包含，迁移成本低
- 可沉淀稳定的重试、校验与清理逻辑
- 复用成本最低

缺点：

- 需要补充少量进程判断和错误处理逻辑

### 方案三：直接引用外部工具目录脚本

skill 文档中直接依赖 `E:\notes\foam-daily-notes\notes\tools\github-push\` 下现有脚本。

优点：

- 初始改动最少

缺点：

- skill 与外部目录耦合
- 后续迁移、共享与维护都较脆弱
- skill 本身不自包含

### 推荐方案

采用方案二：`skill + 自包含 PowerShell 脚本`。

原因：

- 既能复用现有脚本中已验证的 Git 代理配置策略
- 又能把技能文档、脚本实现和使用方式集中到一个 skill 目录中
- 更适合作为长期复用的个人技能能力沉淀

## Skill 结构设计

### SKILL.md 职责

`SKILL.md` 负责定义：

- 何时使用该 skill
- 支持的固定操作范围
- 推荐执行顺序
- 脚本调用方式
- 常见错误与验证方式
- 为什么需要在 Git 操作前后显式控制 Clash Verge 生命周期

### PowerShell 脚本职责

`invoke-github-git-with-clash.ps1` 负责：

1. 检测当前是否位于 Git 仓库中
2. 检测 Clash Verge 是否已在运行
3. 如果未运行，则启动 `C:\Program Files\Clash Verge\clash-verge.exe`
4. 等待 Clash Verge 代理端口或只读 GitHub 连通性达到可用状态
5. 对当前仓库写入 GitHub 相关本地代理配置
6. 执行固定类型的 Git 操作
7. 对 `push` 结果执行远端一致性校验
8. 如果 Clash Verge 是由本次脚本启动，则在结束时关闭
9. 在失败路径下也保证清理逻辑执行

## 操作范围

脚本仅支持以下固定操作：

- `push`
- `pull`
- `fetch`

### push

默认行为：

- 推送当前分支到 `origin`

补充校验：

- 如果 `git push` 报错，但远端分支头与本地分支头一致，则按成功处理

### fetch

默认行为：

- 执行 `git fetch origin`

边界：

- 不自动执行 `merge` 或 `rebase`

### pull

默认行为：

- 执行 `git pull`

边界：

- 仅负责网络代理包装
- 不覆盖仓库已有的 `pull.rebase`、`branch.*` 等 Git 行为配置

## Clash Verge 生命周期策略

Clash Verge 路径固定为：

`C:\Program Files\Clash Verge\clash-verge.exe`

生命周期策略如下：

- 如果脚本启动前 Clash Verge 未运行，则由脚本启动，并在脚本结束后关闭
- 如果脚本启动前 Clash Verge 已运行，则脚本只复用该实例，不在结束时关闭

这样可以避免误关闭用户手动启动并正在服务其他任务的代理实例。

## Git 配置策略

脚本应优先复用现有参考脚本中已验证可行的仓库级配置思路：

- `http.sslBackend schannel`
- `http.version HTTP/1.1`
- `http.expect false`
- `http.sslVerify true`
- `http.maxRequests 1`
- `core.compression 0`
- 清理残留的 `http.proxy`、`https.proxy`
- 仅为 `https://github.com` 配置 `socks5h://127.0.0.1:7897` 形式的仓库级代理

配置范围要求：

- 只写入当前仓库的 `--local` 配置
- 不改动全局 Git 配置

## 成功判定

### push

优先按以下顺序判定：

1. `git push` 直接成功
2. `git push` 失败，但远端分支哈希与本地一致，则按成功处理
3. 两者都不满足，则按失败处理

### fetch / pull

判定方式：

- 以 Git 命令退出码为准
- 不额外引入自动重试的合并判断逻辑

## 错误处理

脚本至少需要覆盖以下错误场景：

- 未在 Git 仓库内执行
- Clash Verge 可执行文件不存在
- Clash Verge 启动后长时间不可用
- GitHub 连通性预检失败
- `push` 失败且远端哈希未更新
- `pull` 或 `fetch` 命令退出非零

错误输出原则：

- 明确说明失败发生在哪个阶段
- 尽量给出下一步处理建议
- 无论成功还是失败，都执行必要的清理逻辑

## 风险与约束

### pull 行为差异

`git pull` 的实际行为可能受仓库本地配置影响，例如：

- `pull.rebase`
- 当前分支是否配置 upstream
- 是否存在本地未提交修改

因此该脚本只负责代理网络通路，不负责统一 `pull` 策略。

### 启动等待时机

Clash Verge 进程启动后，代理端口未必立即可用。脚本需要包含显式等待或连通性检查，否则会出现偶发失败。

### 进程识别边界

关闭 Clash Verge 时，必须以“是否由本次脚本启动”为判断依据，而不是简单地结束同名进程。

## 验证策略

实现完成后，至少验证以下场景：

1. Clash Verge 未启动时执行 `push`
2. Clash Verge 已启动时执行 `push`
3. Clash Verge 未启动时执行 `fetch`
4. `push` 报错但远端实际已更新的场景
5. 非 Git 仓库中执行脚本的失败场景
6. Clash Verge 路径不存在时的失败场景

## 结论

本次 skill 采用“自包含文档 + 自包含脚本”的方式实现，在不污染全局配置的前提下，为 GitHub 网络受限环境下的 `push`、`pull`、`fetch` 提供统一且可复用的执行流程。
