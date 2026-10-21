# 公开来源与证据台账

检索日期：2026-10-22（Australia/Sydney）。本台账仅记录本次实际取得并阅读的公开材料；上游验证报告不自动视为本设备验证。Synced `sources/` 保持只读。

## 证据等级

- **R：用户报告。** 引用对话/当前请求中的日志结论；当前没有重新取得原文件，故不引用虚构行号。
- **H：版本化运行时接口。** 可证明对象/selector声明，不能证明方法实现、时序、键映射或当前固件ABI。
- **S：公开项目源码。** 可证明固定版本实现；不等于设备正在运行该版本。
- **O：Apple官方说明/规范。** 可证明公开语义或服务边界；现代文档不能证明iOS6私有内部实现。
- **I：工程推断。** 需实机/fixture验证，不能当写入依据。

## 当前缺失的本案原始材料

| 资料 | 当前状态 | 允许使用的结论 | 补齐后要做 |
|---|---|---|---|
| `/mnt/data/GsService2-1.log` | 当前Windows工作区未取得原文件；引用对话只保留结果转述 | R：某次complete含hsc200/ec0/M2/spd/np | 保留只读原副本和hash；确定事务、调用者、时间；与失败transaction分开 |
| `/mnt/data/ipod.log` | 当前未取得原文件 | R：required dataclasses、-25300、missing store、backupd accountID null | 逐条定位时间/进程；匹配原native操作；不可假定全属同一事务 |
| 先前上传AquaTransport/TLSFix source | 当前没有找到可重新阅读的上传副本 | 仅能另用本次公开固定commit | 比对上传版本、设备包和当前上游；不混同 |
| iPod touch5/iOS6.1.3的AppleAccount/AccountsDaemon/daemon binaries | 当前未取得 | 只能以6.1头文件做候选hook | 用运行时method encoding/loaded image、合法取得的固件或设备dump确认 |
| 当前已安装GSAPort/TLSFix版本及配置 | 未实机读取 | 不可声称等于上游main | 记录dpkg版本、filter、镜像hash、系统build |

## H：iOS 6.1固定运行时头文件

来源为作者使用RuntimeBrowser导出的接口；这不是Apple公开支持的私有API契约。Git tag `6.1`（annotated tag `ee780af2247b2e8aa26b5f98305c1287c8de4251`）解析到commit **`76cc1d4a6e6bc5546f04448535f9e64ec22a9716`**，tag日期2013-02-03。所有下列链接固定到该commit。它们不是6.1.3的声明证明。

[Tag对象](https://api.github.com/repos/nst/iOS-Runtime-Headers/git/tags/ee780af2247b2e8aa26b5f98305c1287c8de4251)。曾查看2013-02-23 snapshot `d576a9cc197412e81aa87624b755e59b4f00e3cd`帮助定位，最终selector依据以已重读的6.1 tag为准；不采用仓库当前master作为iOS6依据。

| ID | 实际阅读文件 | 可支持的边界 |
|---|---|---|
| H01 | [ACAccount.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/Frameworks/Accounts.framework/ACAccount.h) | parent/child、DSID、dataclass集合与per-dataclass properties、credential |
| H02 | [ACAccountStore.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/Frameworks/Accounts.framework/ACAccountStore.h) | save/verify/renew、XPC proxy、credentialForAccount、支持/启用/provision查询 |
| H03 | [ACAccountCredential.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/Frameworks/Accounts.framework/ACAccountCredential.h) | 分服务Apple ID token与password字段；不证明网络token mapping |
| H04 | [AAAccount.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AppleAccount.framework/AAAccount.h) | BasicAccount到ACAccount桥接、provision更新、configured sync、native token save |
| H05 | [AAProvisioningResponse.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AppleAccount.framework/AAProvisioningResponse.h) | provisionedDataclasses/dataclassProperties解析结果接口 |
| H06 | [AAAuthenticationResponse.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AppleAccount.framework/AAAuthenticationResponse.h) | authToken/fmipToken/personID接口 |
| H07 | [AAResponse.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AppleAccount.framework/AAResponse.h) | HTTP/data/plist parsing与response/error接口 |
| H08 | [AADelegateAccountSetupHelper.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AppleAccount.framework/AADelegateAccountSetupHelper.h) | delegate response调整、token存储、complete边界 |
| H09 | [AASetupAssistantSetupDelegatesResponse.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AppleAccount.framework/AASetupAssistantSetupDelegatesResponse.h) | delegate status/dsid/service response消费接口 |
| H10 | [AASetupAssistantService.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AppleAccount.framework/AASetupAssistantService.h) | setup assistant fetch tokens/setup delegates请求边界 |
| H11 | [AAKeychainManager.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AppleAccount.framework/AAKeychainManager.h) | service/username/access group参数化凭据管理；无具体值映射 |
| H12 | [ACDKeychainManager.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AccountsDaemon.framework/ACDKeychainManager.h) | AccountsDaemon内部credential set/get/remove边界 |
| H13 | [ACDAccountNotifier.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AccountsDaemon.framework/ACDAccountNotifier.h) | will/did account change与notification plugins |
| H14 | [ACDAccountStore.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AccountsDaemon.framework/ACDAccountStore.h) | 守护侧save、关系/权限与credential查询边界 |
| H15 | [AccountsManager.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AccountSettings.framework/AccountsManager.h) | legacy账户保存、dataclass通知、child与sync store |
| H16 | [BasicAccount.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AccountSettings.framework/BasicAccount.h) | legacy账户child/dataclass与用户确认动作 |
| H17 | [DAKeychain.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/DataAccess.framework/DAKeychain.h) | DataAccess persistent UUID与URL两类凭据边界 |
| H18 | [DAAccount.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/DataAccess.framework/DAAccount.h) | DataAccess backingCredentialAccount/persistentUUID/local store/DAV同步 |
| H19 | [DAAccountManager.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/DataAccess.framework/DAAccountManager.h) | 账户通知响应、reload与native store管理边界 |
| H20 | [APSConnection.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/ApplePushService.framework/APSConnection.h) | APS identity/publicToken/connection/topics |
| H21 | [AOSNotifySession.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AOSNotification.framework/AOSNotifySession.h) | AOS account服务与topic监听接口 |
| H22 | [LBAccountNotification.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/Librarian.framework/LBAccountNotification.h) | AccountNotificationProtocol的account changes接口 |
| H23 | [MSMediaStreamDaemon.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/CoreMediaStream.framework/MSMediaStreamDaemon.h) | 按personID认证/push/poll/media stream状态 |
| H24 | [FTProfileAuthenticationMessage.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/FTServices.framework/FTProfileAuthenticationMessage.h) | profile authentication与profile ID/token输出 |
| H25 | [FTRegistrationMessage.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/FTServices.framework/FTRegistrationMessage.h) | IDS registration、validationData、bindings与版本/capabilities |
| H26 | [FTPushHandler.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/FTServices.framework/FTPushHandler.h) | 独立push注册/connection/token/topics |
| H27 | [NSFileManager.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/Frameworks/Foundation.framework/NSFileManager.h) | 6.1存在ubiquity identity/container公共API |
| H28 | [AAAccountManager.h](https://github.com/nst/iOS-Runtime-Headers/blob/76cc1d4a6e6bc5546f04448535f9e64ec22a9716/PrivateFrameworks/AppleAccount.framework/AAAccountManager.h) | primary account、dataclass筛选、reload/save facade |

## S：公开上游固定版本

| ID | 项目/固定版本 | 实读内容与可用结论 | 适用边界 |
|---|---|---|---|
| S01 | [Epixx512/GSAPort](https://github.com/Epixx512/GSAPort/tree/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d) `a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d` | [Tweak.x](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/Tweak.x) L429–435 endpoint识别、L993–1049 login→authenticate→settings、L1052–1150 delegates/token替换、[filter](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/GSAPort.plist) | 当前上游有authentication之外的转换；设备所装版本未知；未明确授权源码不复制 |
| S02 | [nfzerox/TLSFix](https://github.com/nfzerox/TLSFix/tree/d98825f45322f9a743fc3703eedc77098bec7efc) `d98825f45322f9a743fc3703eedc77098bec7efc` | [README](https://github.com/nfzerox/TLSFix/blob/d98825f45322f9a743fc3703eedc77098bec7efc/README.md)、[filter](https://github.com/nfzerox/TLSFix/blob/d98825f45322f9a743fc3703eedc77098bec7efc/src/tlsfix.plist)：SecureTransport shadow/OpenSSL、系统trust、client identity说明 | README设计描述；本次未审计全部crypto engine，未实机验证 |
| S03 | [Wowfunhappy/AquaTransport](https://github.com/Wowfunhappy/AquaTransport/tree/4af032dbba7f57715523abed75fba406110ab614) `4af032dbba7f57715523abed75fba406110ab614` | [docs/ICLOUD.md](https://github.com/Wowfunhappy/AquaTransport/blob/4af032dbba7f57715523abed75fba406110ab614/docs/ICLOUD.md)：response metadata、DAV/device headers、Mail ATOKEN、native anisette架构与作者验证报告 | OS X10.7–10.9；不证明iOS6 selectors或服务接受；旧Wowfunhappy/TLSFix URL已重定向 |
| S04 | [victorlobe/iCloudMailFix-Tweak](https://github.com/victorlobe/iCloudMailFix-Tweak/tree/229f836e9cae3cf02408ff6f777f01ab822ba1ac) `229f836e9cae3cf02408ff6f777f01ab822ba1ac` | [README](https://github.com/victorlobe/iCloudMailFix-Tweak/blob/229f836e9cae3cf02408ff6f777f01ab822ba1ac/README.md)：本地TLS代理、手动Mail账户、默认iCloud Mail尚不支持 | 有限服务替代路径；不能证明全账户provisioning已修复 |
| S05 | [Apple OSS Security](https://github.com/apple-oss-distributions/Security/blob/db15acbe6a7f257a859ad9a3bb86097bfe0679d9/base/SecBase.h) `db15acbe6a7f257a859ad9a3bb86097bfe0679d9` | `errSecItemNotFound=-25300`常量 | 常量映射，非该次查询根因 |

## O：官方语义、服务边界与协议

| ID | 来源 | 本文采用的有限结论 |
|---|---|---|
| O01 | [Apple ACAccountStore](https://developer.apple.com/documentation/accounts/acaccountstore?language=objc) | 账户save/renew和store change通知的公共语义；不是iOS6跨进程private notification名称 |
| O02 | [iCloud Fundamentals](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/iCloudFundametals.html) | identityToken非nil不代表已访问container；需container API，账户可用性通知与文件协调；文档后期含CloudKit内容，不能整体按2012功能解释 |
| O03 | [iCloud File Management](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/iCloud/iCloud.html) | app通过系统daemon和file coordination访问文档；不证明某daemon名称/selector |
| O04 | [Apple Backup旧版终止说明](https://support.apple.com/en-au/120863) | 自2024-12-18起iOS5–8不能新建备份、旧备份不可访问；本地accountID修复不能承诺恢复此服务 |
| O05 | [My Photo Stream shutdown](https://support.apple.com/en-us/102645) | 2023-07-26服务关闭；与iCloud Photos/Shared Albums不能混同 |
| O06 | [Documents and Data迁移存档](https://support.apple.com/en-us/111757) | 旧document sync服务已停止并迁往Drive；不等于iOS6本地ubiquity框架具现代Drive协议 |
| O07 | [Apple iOS8开发发布说明](https://developer.apple.com/news/?id=06022014b) | CloudKit为iOS8新增能力，不能假定iOS6有native CloudKit consumer |
| O08 | [RFC4791 CalDAV](https://www.rfc-editor.org/rfc/rfc4791.html) | DAV日历协议基础；非iCloud私有鉴权规范 |
| O09 | [RFC6352 CardDAV](https://www.rfc-editor.org/rfc/rfc6352.html) | DAV地址簿协议基础；非native Keychain schema |
| O10 | [RFC6578 WebDAV Sync](https://www.rfc-editor.org/rfc/rfc6578.html) | collection同步token/变更语义；sync-token不能当authentication token |

## 未成立的证据跳跃

- GSA一次成功 ≠ 每次renewal的credential相同。
- loginDelegates返回token ≠ iOS6已消费并保存正确item。
- header里有setter ≠ 可在任意进程无授权调用；也不等于设置后native数据库/Keychain/child/store全部一致。
- -25300 ≠ password被Apple拒绝；需要原查询上下文。
- notification回调出现 ≠ server完成同步；APNs连通 ≠ IDS/profile/各topic注册成功。
- macOS适配成功报告 ≠ iOS6兼容；当前上游main ≠ 设备已安装版本。
- 合成测试/源码检查通过 ≠ armv7 Mach-O编译/载入成功 ≠ 用户实机业务恢复。

