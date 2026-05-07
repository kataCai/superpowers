# Fork 仓库 main 分支同步说明

## 背景

本文档用于说明当前 fork 仓库如何从上游仓库 `https://github.com/obra/superpowers.git` 的 `main` 分支同步更新到当前仓库的 `main` 分支。

当前仓库远端约定如下：

- `origin`：当前 fork 仓库 `https://github.com/kataCai/superpowers.git`
- `upstream`：上游仓库 `https://github.com/obra/superpowers.git`

## 已配置内容

仓库本地已配置以下 Git alias：

```bash
git sync-upstream
```

对应执行内容如下：

```bash
git checkout main && git fetch upstream && git fetch origin && git merge upstream/main && git push origin main
```

说明：

- 该 alias 写在当前仓库本地 `.git/config` 中，只对当前仓库生效。
- 该流程使用 `merge` 同步上游改动，适合 fork 仓库长期维护自有提交的场景。
- 执行过程中如果存在冲突，需要人工处理后再继续提交和推送。

## 推荐同步步骤

### 方式一：直接使用 alias

```bash
git sync-upstream
```

适用场景：

- 当前就在本仓库目录下操作。
- 希望用固定命令快速完成同步。

### 方式二：按步骤手动执行

```bash
git checkout main
git fetch upstream
git fetch origin
git merge upstream/main
git push origin main
```

适用场景：

- 需要逐步观察每一步结果。
- 需要在合并前先检查差异。

## 同步前检查

建议在同步前先执行以下命令：

```bash
git status --short --branch
```

用途说明：

- 确认当前位于正确分支。
- 确认工作区是否有未提交修改。
- 避免本地未提交内容影响合并结果。

如果需要先查看分支差异，可执行：

```bash
git log --oneline --graph --decorate main upstream/main origin/main -20
```

用途说明：

- 查看本地 `main`、上游 `upstream/main`、远端 `origin/main` 的相对位置。
- 在执行合并前提前判断是否可能出现较大差异或冲突。

## 冲突处理

当执行 `git merge upstream/main` 出现冲突时，按以下流程处理：

1. 执行 `git status` 查看冲突文件。
2. 打开冲突文件，按实际需要保留当前 fork 改动或上游改动。
3. 处理完成后执行 `git add <文件路径>` 标记冲突已解决。
4. 执行 `git commit` 完成 merge 提交。
5. 执行 `git push origin main` 推送结果。

如果希望放弃本次合并，可执行：

```bash
git merge --abort
```

说明：

- 该命令仅用于放弃当前未完成的 merge。
- 放弃前应确认当前没有需要保留的临时修改。

## 注意事项

- 不建议在工作区存在未提交改动时直接执行同步。
- 本文档默认同步目标是 `main` 分支，不适用于其他功能分支。
- 当前策略为 `merge`，不会改写已发布历史；因此相比 `rebase` 更适合长期维护 fork 主分支。
- 如果后续更换 fork 地址或上游地址，需要同步更新对应远端配置和本文档。
