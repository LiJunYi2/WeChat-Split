# 微信多开脚本说明

## 启动命令

1个分身
```shell
sudo bash wechat_multi_open_v3.sh
```

多个分身：n 替换成你要的数字

```shell
sudo bash wechat_multi_open_v3.sh n
```

## 核心原理

macOS 微信使用 **沙盒机制（Sandbox）** 存储数据，数据存储路径由 **Bundle Identifier** 决定。

### 应用程序 vs 数据文件夹

```
应用程序（可执行文件）
├── /Applications/WeChat.app          → Bundle ID: com.tencent.xinWeChat
├── /Applications/WeChat2.app         → Bundle ID: com.tencent.xinWeChat2
└── /Applications/WeChat3.app         → Bundle ID: com.tencent.xinWeChat3

数据文件夹（聊天记录、登录信息等）
├── ~/Library/Containers/com.tencent.xinWeChat/
├── ~/Library/Containers/com.tencent.xinWeChat2/
└── ~/Library/Containers/com.tencent.xinWeChat3/
```

**关键点**：应用程序和数据文件夹是**完全分离**的！

## 数据保留机制

### 为什么重新创建应用后数据还在？

1. **删除应用时**：
   - ✅ 删除了 `/Applications/WeChat2.app`（应用程序）
   - ❌ **不会**删除 `~/Library/Containers/com.tencent.xinWeChat2/`（数据文件夹）

2. **重新创建应用时**：
   - ✅ 创建新的 `/Applications/WeChat2.app`
   - ✅ 设置 Bundle ID 为 `com.tencent.xinWeChat2`
   - ✅ macOS 自动将应用关联到 `~/Library/Containers/com.tencent.xinWeChat2/`
   - ✅ 登录信息、聊天记录自动恢复

### 类比说明

| 概念 | 类比 |
|------|------|
| 应用程序 | 房子的钥匙 |
| Bundle Identifier | 钥匙的编号 |
| 数据文件夹 | 房子本身 |

- 扔掉钥匙（删除应用）→ 房子还在
- 配一把相同编号的钥匙（重新创建应用）→ 还能打开同一个房子

## v3.0 脚本的改进

### 新增功能

1. **数据检测**：
   - 运行前检测现有数据文件夹
   - 显示每个数据文件夹的大小

2. **数据关联提示**：
   - 创建应用时提示是否有现有数据
   - 显示数据关联状态

3. **详细信息展示**：
   - 显示每个微信的 Bundle ID
   - 显示数据存储路径
   - 显示数据文件夹大小

### 执行效果示例

```
================================================
     macOS 微信多开自动化脚本 v3.0
================================================

[信息] 将创建 2 个微信实例（原版 + 1 个分身）
[信息] 检测到微信应用: /Applications/WeChat.app
[步骤] 检查现有数据...

[信息] 未发现现有数据，这是首次创建

[步骤] 检查并清理旧的应用程序...
[信息] 未发现旧的应用程序

[步骤] 开始创建微信分身...

[步骤] 创建第 2 个微信分身...
[信息]   [1/4] 复制应用...
[信息]   [2/4] 修改 Bundle Identifier 为 com.tencent.xinWeChat2
[信息]   [3/4] 重新签名应用...
[信息]   [4/4] 启动微信实例...
[信息] ✓ WeChat2.app 创建并启动成功
[数据]   → 首次启动，将创建新的数据文件夹

[信息] 创建完成: 成功 1 个，失败 0 个

================================================
     创建完成！
================================================

[信息] 当前系统中的微信实例：

  1. WeChat.app (原版)
  2. WeChat2.app (分身)

[步骤] 数据文件夹信息

微信数据存储在以下位置（按 Bundle Identifier 区分）：

  1. WeChat.app
     Bundle ID: com.tencent.xinWeChat
     数据路径: ~/Library/Containers/com.tencent.xinWeChat/
     数据大小:  45G

  2. WeChat2.app
     Bundle ID: com.tencent.xinWeChat2
     数据路径: ~/Library/Containers/com.tencent.xinWeChat2/
     数据大小: 尚未创建（首次登录后生成）


[信息] 重要说明：
  1. 所有微信实例已在后台启动
  2. 可以在 Dock 或启动台中找到它们
  3. 每个实例可以登录不同的账号
  4. 微信升级后需要重新运行此脚本
  5. 重新运行不会丢失数据（数据和应用是分离的）
  6. 删除应用程序不会删除数据文件夹

[信息] 如需删除某个分身：
  • 删除应用：在应用程序文件夹中将 WeChatX.app 拖到废纸篓
  • 删除数据：手动删除 ~/Library/Containers/com.tencent.xinWeChatX/
```

## 数据管理

### 查看数据文件夹

```bash
# 查看所有微信数据文件夹
ls -d ~/Library/Containers/com.tencent.xinWeChat*/

# 查看详细信息
ls -lh ~/Library/Containers/com.tencent.xinWeChat*/
```

### 查看数据大小

```bash
# 查看所有微信数据的总大小
du -sh ~/Library/Containers/com.tencent.xinWeChat*/

# 查看特定微信的数据大小
du -sh ~/Library/Containers/com.tencent.xinWeChat2/
```

### 备份数据

```bash
# 备份 WeChat2 的数据
cp -R ~/Library/Containers/com.tencent.xinWeChat2/ ~/Desktop/WeChat2_backup/

# 备份所有微信数据
cp -R ~/Library/Containers/com.tencent.xinWeChat*/ ~/Desktop/WeChat_backup/
```

### 删除数据

**注意**：删除数据会清空聊天记录、登录信息等，请谨慎操作！

```bash
# 删除 WeChat2 的数据（会清空聊天记录）
rm -rf ~/Library/Containers/com.tencent.xinWeChat2/

# 删除所有微信分身的数据（保留原版）
rm -rf ~/Library/Containers/com.tencent.xinWeChat[2-9]/
rm -rf ~/Library/Containers/com.tencent.xinWeChat1[0-9]/
```

## 常见问题

### Q1: 删除应用后数据会丢失吗？

**A**: 不会。删除 `/Applications/WeChatX.app` 只删除应用程序，数据文件夹 `~/Library/Containers/com.tencent.xinWeChatX/` 会保留。

### Q2: 重新运行脚本后需要重新登录吗？

**A**: 不需要。如果数据文件夹还在，重新创建的应用会自动关联，打开就是已登录状态。

### Q3: 如何彻底删除某个微信分身？

**A**: 需要同时删除应用和数据：

```bash
# 删除应用
sudo rm -rf /Applications/WeChat2.app

# 删除数据
rm -rf ~/Library/Containers/com.tencent.xinWeChat2/
```

### Q4: 微信升级后数据会丢失吗？

**A**: 不会。微信升级只更新应用程序，不会影响数据文件夹。重新运行脚本后数据会自动关联。

### Q5: 可以手动迁移数据到另一台 Mac 吗？

**A**: 可以。步骤如下：

1. 在旧 Mac 上备份数据文件夹
2. 在新 Mac 上运行脚本创建应用
3. 将备份的数据文件夹复制到新 Mac 的 `~/Library/Containers/`
4. 重启应用，数据会自动加载

### Q6: 数据文件夹里有什么？

**A**: 包含但不限于：

- 聊天记录数据库
- 登录凭证
- 接收的文件
- 缓存的图片和视频
- 应用设置

## 技术细节

### macOS 沙盒机制

macOS 使用沙盒（Sandbox）隔离应用数据：

- 每个应用有独立的容器（Container）
- 容器路径由 Bundle Identifier 决定
- 应用只能访问自己的容器
- 删除应用不会自动删除容器

### Bundle Identifier 的作用

Bundle Identifier 是应用的唯一标识符：

- 格式：`com.公司名.应用名`
- 用于区分不同的应用
- 决定数据存储路径
- 决定应用的权限和配置

### 为什么要重新签名？

修改 Bundle Identifier 后需要重新签名：

- macOS 会验证应用的签名
- 签名不匹配会拒绝运行
- 使用 `codesign --sign -` 进行本地签名
- 本地签名足够让应用运行

## 安全建议

1. **定期备份**：建议定期备份数据文件夹到外部存储
2. **谨慎删除**：删除数据前先确认是否需要备份
3. **版本同步**：微信升级后及时重新运行脚本
4. **空间监控**：定期检查数据文件夹大小，避免占用过多空间
