---
name: github-proxied-git
description: 当受限网络环境下 GitHub 的 push、pull 或 fetch 失败时使用，尤其适用于出现 HTTP 302、RPC failed 或 remote end hung up unexpectedly 等错误的情况。
---

# GitHub 代理 Git 操作

## 概述

当当前网络无法直接访问 GitHub 时，通过 Clash Verge 执行受限的 GitHub Git 操作。该技能仅在必要时启动 Clash Verge，按仓库粒度应用本地代理配置，执行固定的 `push`、`pull` 或 `fetch` 操作，并且只会在本次运行启动了 Clash Verge 的情况下将其关闭。

## 适用场景

在以下情况使用此技能：

- `git push`, `git pull`, or `git fetch` against GitHub fails on the current network
- Errors include `HTTP 302`, `RPC failed`, `remote end hung up unexpectedly`, or similar upload-stage disconnects
- GitHub access is known to require Clash Verge on the current machine

- 当前网络环境下，针对 GitHub 的 `git push`、`git pull` 或 `git fetch` 执行失败
- 报错包含 `HTTP 302`、`RPC failed`、`remote end hung up unexpectedly`，或其他类似的传输阶段断连问题
- 当前机器访问 GitHub 已知需要依赖 Clash Verge

在以下情况不要使用此技能：

- The remote is not GitHub
- The task requires arbitrary Git command passthrough
- The task needs global Git proxy changes

- 远端仓库不是 GitHub
- 任务需要透传任意 Git 命令，而不是固定操作
- 任务需要修改全局 Git 代理配置

## 支持的操作

- `push`
- `pull`
- `fetch`

该包装脚本只支持以上固定操作，不接受任意 Git 命令字符串。

## 执行流程

1. 确认目标仓库就是当前工作仓库。
2. 使用一个固定操作运行 PowerShell 包装脚本。
3. 由脚本检测 Clash Verge 是否已在运行。
4. 由脚本仅为当前仓库应用面向 GitHub 的本地 Git 代理配置。
5. 检查脚本执行结果，尤其是 `push` 之后的远端校验步骤。

## 脚本路径

执行：

```powershell
powershell -ExecutionPolicy Bypass -File ".\notes\skills\github-proxied-git\invoke-github-git-with-clash.ps1" -Operation push
```

按需将 `push` 替换为 `pull` 或 `fetch`。

## 预期行为

- 如果 Clash Verge 未运行，脚本会启动 `C:\Program Files\Clash Verge\clash-verge.exe`
- 如果 Clash Verge 已在运行，脚本会复用当前实例，并在结束后保持其运行状态
- Git 配置变更只会使用 `--local` 写入当前仓库
- `push` 在将错误判定为真实失败前，会先检查远端分支头是否已与本地分支头一致
- 脚本退出时，会强制关闭当前用户的 Windows 系统代理，并清理相关代理设置

## 验证方式

`push` 成功后，可通过以下命令验证：

```powershell
git rev-parse HEAD
git ls-remote origin HEAD
```

`fetch` 或 `pull` 成功后，可通过以下命令验证：

```powershell
git status --short --branch
```

## 常见问题

| 问题 | 处理方式 |
|---------|----------|
| 找不到 Clash Verge 可执行文件 | 运行前先确认 `C:\Program Files\Clash Verge\clash-verge.exe` 存在 |
| `push` 仍然报传输错误 | 重试前先检查远端与本地分支头是否其实已经一致 |
| 仓库存在本地未提交改动 | 执行 `pull` 前先检查 `git status --short --branch` |
| 用户原本就已打开 Clash Verge | 除非是脚本本次启动的，否则不要关闭 |
| 用户希望保留现有 Windows 系统代理 | 本次会话不要使用此技能，因为脚本退出时会强制关闭系统代理 |
