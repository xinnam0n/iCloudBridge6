# iCloudBridge6 0.1.0

面向 **iPod touch 5 / iOS 6.1.3（armv7、rootful jailbreak）** 的诊断 Alpha。默认只观察；不保存密码/token，不直接创建或修改 Keychain 项，不自动启用同步。**尚未完成 iPod 实机验证，不能称为已恢复 iCloud 同步的修复插件。**

## GitHub 与 Cydia 软件源

- 源码：[xinnam0n/iCloudBridge6](https://github.com/xinnam0n/iCloudBridge6)
- 软件源目标地址：`https://xinnam0n.github.io/iCloudBridge6/`
- [构建与发布状态](https://github.com/xinnam0n/iCloudBridge6/actions)

软件源只在 Objective-C 原生测试、armv7 构建和包校验全部成功后更新；未通过时不会发布空包或假包。请以软件源网页的版本/下载信息及对应 Actions 结果确认实际可用性。在 Cydia → 软件源 → 编辑 → 添加中输入上述地址；需要设备的 HTTPS/TLS 支持正常。

公开 CI 使用固定版本的 Theos、官方 SDK 9.3 和最低运行版本 iOS 6.0，并检查 Mach-O 架构、签名及依赖；这与本地默认 SDK 6.1 构建选择不同，均不替代 iOS 6.1.3 实机验证。见 [CI 构建说明](docs/CI_BUILD.md) 和 [Cydia 发布说明](docs/CYDIA_REPO.md)。

用户本轮补充版本为 `1.1`；由于问题同时询问 GSAPort/TLSFix，暂不把这个数字强行归到某个包。安装前记录两个包的完整版本和设备 build。当前公开 GSAPort 的 2026-10-20 源码已包含部分 provisioning response 转换，不能用它替代设备安装版本的证据。

## 从这里阅读

- [架构、账户/凭据/daemon/推送/协议边界](docs/ARCHITECTURE.md)
- [证据来源与缺失材料](docs/EVIDENCE_SOURCES.md)
- [上游 GSAPort / TLSFix / AquaTransport 源码分析](docs/UPSTREAM.md)
- [用户补充的 1.1 版本与公开历史对照](docs/VERSION_1_1.md)
- [设计与实施计划](docs/DESIGN.md)、[实施记录](docs/IMPLEMENTATION_PLAN.md)
- [iPod 实机测试矩阵](docs/TEST_MATRIX.md)
- [验证状态](docs/VALIDATION.md)

`sources/` 和原 Mountain Lion PoC 均未修改。本 Work 环境没有取得 `/mnt/data/GsService2-1.log`、`/mnt/data/ipod.log` 的原始字节，也未找到原上传 AquaTransport/TLSFix 源码；文档明确将相关成功与错误保留为用户报告。公开源码另行固定版本引用。

## 已实现的行为

1. 只在白名单进程注入：Preferences、accountsd、dataaccessd、backupd、ubd、librariand、mstreamd、aosnotifyd。它不注入 apsd / imagent，不改 APNs/IDS。
2. 检查 `GSAPortProtocol` 的继承和方法 ABI 后，代理其 NSURLProtocolClient；观察 **GSAPort 转换后的最终响应**。不再注册一个抢占请求的 NSURLProtocol。
3. 同步网络调用单独记录 transport 指标；原生 AppleAccount/Accounts hooks 记录 delegate、provision、dataclass 集合大小、credential/save 调用及保存结果。异步 callback 和每个进程独立；**不同 tx 不是已关联的同一认证事务**。
4. 可选观察 SecItemCopyMatching/Add/Update 的原始 OSStatus 和固定 item class。原查询及结果保持不变，不记录 service/account/access group、返回数据或错误描述。默认关闭。
5. 可选最小转换仅作用于成功、结构完整且带 tokens/既有 DSID 的 setup 响应：
   - `RestoreRequestURL`：当旧 login caller 收到内部 `get_account_settings` 的 response URL，把 URL 对齐回它原来的 login 请求。保留正文、状态和头字段。属于源码支持的兼容候选，尚未证明是本案根因。
   - `NormalizeNumericDSID`：把同一个已存在的正整数 DSID 转成等值十进制字符串。tokens、dataclasses、其他 delegate 均不变。它是待实机验证的类型兼容假设，默认关闭。

observe 立即按原顺序转发；adapt 缓存最多 2 MiB，完成后再交付，可能改变交付时机。失败 HTTP、失败 application status、畸形/过大正文、缺失 identity/tokens 均保留原字节。不猜测 dataclass/service-token 映射，不向 CalDAV/CardDAV/Mail/Backup/ubiquity 复制通用 token。持久化仍由系统原生消费链完成。

## 构建与原生测试

需要一台 Mac，或可生成 **armv7 / iOS 6** dylib 的 Theos 工具链，以及合法取得、兼容该编译器的 iOS SDK。此工作区没有这些组件；不要把主机 Python 测试当作 tweak 编译成功。避免直接选择只支持新设备/新系统的工具链。

在工程目录执行（已配置 `THEOS`）：

```sh
sh tests/run-native.sh
make clean package FINALPACKAGE=1
```

默认 `TARGET=iphone:clang:6.1:6.0`、`ARCHS=armv7`，使用 SDK 6.1，最低系统 6.0。若你的 SDK/toolchain 布局不同，显式调整 TARGET；禁止用提高部署版本的方式静默掩盖旧系统符号问题。对输出 dylib 用 `file` / `lipo -info` 确认 armv7，并用 `otool -l` 检查最低系统版本；在 iPod 上验证依赖和实际加载。Native tests 在 Mac 测 Foundation 策略/代理，仍不能证明 iOS 6 ABI 或服务器兼容。

主机端离线工具测试只需 Python 3：

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

## 安装、首次观察

先保留现状：不要注销 Apple ID、删除账户、清空 Keychain、改 Accounts 数据库或重置同步库。先记录系统 build、GSAPort/TLSFix 完整包名和版本，以及其他同时注入的 tweak。SSH 到设备后可运行 `dpkg -l`，在本地保留与这两个包相关的行；版本号本身不能唯一证明二进制对应哪个 commit。

以下命令在你的 Mac 工程目录执行，`IPOD_HOST` 是你自己的设备地址，`IB6_DEB` 指向刚构建出的实际文件名：

```sh
IPOD_HOST=your-ipod-address
IB6_DEB=packages/your-actual-package.deb
scp "$IB6_DEB" "root@$IPOD_HOST:/var/tmp/icloudbridge6.deb"
scp config/observe.plist "root@$IPOD_HOST:/var/tmp/ib6-prefs.plist"
ssh "root@$IPOD_HOST"
```

在设备 SSH 会话执行：

```sh
dpkg -i /var/tmp/icloudbridge6.deb
cp /var/tmp/ib6-prefs.plist /var/mobile/Library/Preferences/local.legacyapple.icloudbridge6.plist
chown mobile:mobile /var/mobile/Library/Preferences/local.legacyapple.icloudbridge6.plist
chmod 600 /var/mobile/Library/Preferences/local.legacyapple.icloudbridge6.plist
```

安装脚本不会杀进程或发同步通知。设置仅在新进程加载时读取；完成准备后由你手动重启设备，确保各守护进程以相同设置启动。先观察一次正常的系统登录/renewal，不连续反复输入凭据。收集 `IB6` 日志、进程时间和 native 错误；不同日志流不能只靠相近时间强行串成同一事务。

日志 `cap_protocol client=1 stop=1` 表示最终响应代理已装上；`cap_accounts` / `cap_appleaccount` / `cap_delegate` 的 hooks 数量说明实际可用能力。类还未加载时没有相应事件，绝不代表配置链成功。框架延迟加载会触发重新发现。每个进程最多 2000 条正常事件，之后标记 `budget_exhausted`，需要新进程才能重新计数。

## 分别启用候选适配

只在 baseline/observe 已取得后测试，一次改变一个开关。`config/adapt.example.plist` 只打开 response URL 转换，numeric DSID 转换仍关着。把所选配置复制到同一 preferences 路径并手动重启；复现同一原生操作，对比最终 response、原生配置/保存调用和服务结果。

若要诊断 Keychain 的 `-25300`，仅将 `ObserveSecurity` 设为 plist boolean `true`。这可能覆盖该进程其他服务的 Keychain 调用；单独状态码无法认定是哪一个 CalDAV item。不要为追求详细日志打开 GSAPort/TLSFix 自身的明文凭据 dump。

只有在响应中确认存在数字 DSID 且消费者有类型不兼容证据时，才单独测试 `NormalizeNumericDSID=true`。未知 response schema 会拒绝转换；这应触发进一步取证，不能删除 guard 或用硬编码 token/账户字段绕过。

## 离线审计已有日志

可将缺失的原始日志重新放入本地私有目录（例如 `private-evidence/`，不要加入源码包），工具不修改输入。它只输出 hash、数量、固定状态和行号，不输出原行、账户标识、token 或 proof：

```sh
python3 tools/audit.py --gsa-plist private-evidence/GsService2-1.log --syslog private-evidence/ipod.log --output evidence-report.json
```

另有 `--delegate-plist` 用于单份 loginDelegates plist。输出文件必须是新文件，工具拒绝覆盖。单份 GSA complete 的 hsc/ec/M2/spd/np 只能证明服务器报告该轮成功，不能替代客户端 M2 校验，更不能证明 Keychain 已落地。原 syslog 仍可能由其他组件写入敏感内容；分享此工具的精简报告与 `IB6` 行即可。

## 停用、回滚与恢复

正常停用：将配置中的 `Enabled` 改为 boolean `false`，手动重启。卸载：`dpkg -r local.legacyapple.icloudbridge6`，再手动重启，以卸载已经映射进进程的 dylib。配置可保留用于审计；本包没有凭据缓存。

如出现启动/Preferences 崩溃，通过 SSH 或 jailbreak 的禁用 tweak/安全模式进入设备，将 `/Library/MobileSubstrate/DynamicLibraries/iCloudBridge6.dylib` 改名为 `iCloudBridge6.dylib.disabled`，再重启。不要批量移动其他 tweak 或删除 Keychain。

适配层没有直接账户/Keychain写入，因此没有自制数据库回滚器；若原生消费者已持久化服务器配置，卸载 tweak 不会撤销该原生保存。恢复同步选项应通过系统 UI 逐项完成，避免引入另一份账户状态。

## 验收范围

先验收认证、native provisioning、credential 可用性，再逐服务验收 DAV/Mail 等。Apple 官方已关闭 iOS 5–8 iCloud Backup、My Photo Stream，旧 Documents and Data 也已终止/迁移。具体来源和限制见架构报告；不能以 `backupd` 不再为 null 或 `ubd` 不再报错宣布恢复这些云端服务。

代码许可证见 LICENSE。上游源码未复制到本工程；源码与文档链接保留各项目原有权利。
