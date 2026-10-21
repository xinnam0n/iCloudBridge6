# iCloudBridge6 0.1 design — 2026-10-22

目标：在 iPod touch 5 / iOS 6.1.3（10B329、armv7）上，把成功认证之后的 iCloud 配置链变成可追踪、可逐步适配的流程。用户已要求分析、制定计划并实施，本轮连续执行。

## 证据边界

- 当前项目 `sources/` 为空；`/mnt/data/GsService2-1.log` 和 `/mnt/data/ipod.log` 不在此 Windows 文件系统。read_thread 返回附件占位而非附件字节。
- GSA init/complete 可成功、loginDelegates status 0 和 service tokens，以及 dataclasses / CalDAV -25300 / store / backupd accountID null，属于用户给定及原聊天报告。本轮没有重新验证原始抓包，也不能把不同 transaction 拼成一轮。
- 当前上游 GSAPort a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d 已实现部分协议转换。设备所装版本未知。
- 精确 iOS 6.1 header tag 可作为 ABI 候选依据，6.1.3 必须运行时复核。现代 master headers 不当作旧版证明。

## 实现选择

1. 独立 Theos rootful tweak；不修改 GSAPort、TLSFix、系统文件或旧 Mountain Lion PoC。
2. 默认 observe：GSAPortProtocol 的公开 NSURLProtocolClient 边界代理，记录最终响应的固定结构指标；Accounts / AppleAccount 原生调用前后记录固定事件；Security API 只记录调用种类、item class 和 OSStatus，不读任何 Keychain 内容。
3. 不再注册 NSURLProtocol，不重做 GSA，不篡改 TLS/证书/客户端身份，不记录 URL 查询、请求正文、账户标识、token、密码或 APNs token。
4. opt-in adapt：只在成功的、白名单 setup 响应中，可将内部 settings response URL 对齐回原 login caller 的请求 URL；另有独立默认关闭的开关，把已存在的正整数 DSID 转成等值十进制字符串。不新增身份、不改变 token、不自动启用 dataclass。显式启用后仅在内存响应副本上转换，让原生 AppleAccount 消费、保存和发通知。
5. 不凭猜测创建 CalDAV/CardDAV/Mail/Backup/ubiquity Keychain 项，不向其他服务复制 mmeAuthToken，不手工改 Accounts 数据库。直接凭据写入必须等待实机服务名、access group、parent/child account 和返回 schema 证据。
6. 保留失败 HTTP / plist / application status；重入保护、最大 2 MiB、类型检查、能力日志和 kill switch。observe 模式立即转发原回调；adapt 模式仅对三个 setup 白名单响应短暂缓存，失败或溢出回退原字节。

## 完成标准与当前可交付范围

交付完整可构建的源码、原生策略测试、主机日志审计工具及其测试、架构与证据账本、安装/回滚/实机矩阵。必须区分：Windows 已执行的测试；需要 macOS/Theos/合法 iOS SDK 的 native build；需要用户 iPod 的运行验证。没有实机证据前，不能称 iCloud 同步已修复。

后续修复分支由诊断结果决定：响应失败继续查上游；token 有但原生 sink 未被调用查 delegate/provisioning；原生 Keychain 写失败查 OSStatus/entitlements；credential 成功后单独验证 DAV、备份、ubiquity 和推送协议。
