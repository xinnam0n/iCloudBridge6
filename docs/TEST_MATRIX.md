# iPod touch 5 / iOS 6.1.3 测试矩阵

日期：2026-10-22（Australia/Sydney）。依据本项目 `src/Tweak.m`、`src/IB6Policy.h/.m`、现有合成测试及 [架构分析](ARCHITECTURE.md)。本文件是可执行的验证规程，**所有实机结果仍待测试，不能据此声称 iCloud 已恢复**。

当前没有重新取得 `/mnt/data/GsService2-1.log`、`/mnt/data/ipod.log` 原文件。以下保留用户报告：某次 GSA init/complete 成功，complete 含 `hsc=200/ec=0/M2/spd/np`；loginDelegates 返回 status 0 和服务 token；另有 required dataclasses、CalDAV Keychain -25300、missing store、backupd accountID null。原始文件补齐后，应记录 hash、日志行号和事务/进程边界；不能用转述代替原始证据。

## 1. 通过的含义

| 层次 | 合格证据 | 不能据此宣称 |
|---|---|---|
| 静态检查 | 文件、配置、注入范围和日志代码检查通过 | armv7 编译、加载或行为正确 |
| native 合成测试 | 真实 Foundation 执行策略/回调 fixture，输出逐场景 PASS | iOS 6 的 Foundation/ABI 与 macOS 完全相同 |
| 设备加载 | 系统版本、包版本、目标进程存在及 `loaded`/`cap_*` 记录 | 任意登录/服务成功 |
| GSA | 特定 transaction 成功 response 的 status 与字段 presence | 后续 renewal 全部成功、native credentials 已保存 |
| provisioning | native 消费、dataclass、save completion 和原查询结果 | 所有服务可用或推送正常 |
| 单服务同步 | 两设备受控对象读写与原服务协议结果一致 | Backup、照片、文档等其他服务已恢复 |

所有测试记录应填：测试 ID、时间窗口、设备系统 build、包版本/源码 commit、配置布尔值、进程/PID、IB6 session、预期、实测、结论、日志文件位置。不要记录 Apple ID、密码、验证码、DSID 数值、tokens、APNs token、邮件或联系人内容。

## 2. 测试准备与停止条件

1. 保留现有账户和设备数据，先按 README 的备份、安装及卸载说明准备恢复路径；测试本身不注销账户、不删数据库、不清 Keychain、不移除 stores。
2. 固定 GSAPort/TLSFix 版本和配置，记录 iCloudBridge6 文件 hash；完成各组 A/B 比较前不要更新上游。
3. 控制一次测试只改变一个变量，使用 Settings 的正常登录/开关操作。重启相关进程只用于让新库/配置生效，由 README 指导；不能用一串全局 daemon kill 充当修复。
4. 如真实账号已经登录，优先使用正常服务刷新和 Settings 既有操作；不要仅为制造新登录样本而退出账号。需重复认证时由用户执行单次正常流程，禁止脚本自动重试密码/2FA。
5. 测试数据使用独立、可识别且无个人信息的日历/联系人/邮件样本。创建、修改和删除只针对该测试对象；真实数据不能用作破坏性探针。
6. 遇到 SpringBoard/Settings/daemon crash loop、持续 renewal、异常账号变化或明显额外写入时，停止本组并禁用桥接层，保留记录。不要追加并行修复掩盖原因。

配置在目标进程初始化时读取；修改文件不表示已运行的进程热更新。每组开始先核对新的 `loaded`、session 和 mode。`ObserveSecurity` 默认关闭；它记录目标注入进程内原 Security 调用的 item class 与 OSStatus，不能可靠区分该进程内每一次 Keychain 操作属于哪个账户。

## 3. 四组隔离实验

| 组/ID | 配置状态 | 操作 | 预期 | 结果 |
|---|---|---|---|---|
| A00 无桥接基线 | 保留 GSAPort/TLSFix；iCloudBridge6 禁用或未加载 | 正常打开 Settings；按已可复现步骤做一次服务刷新/认证 | 记录已有成功与失败；没有 IB6 事件；不要求原问题必定每次出现 | 待实机 |
| B00 只观察 | `Mode=observe`；三个选项都为 false | 同 A00，保持其他变量 | 有 `loaded mode=observe` 和能力事件；正文/response/账户操作语义保留原行为 | 待实机 |
| B10 可选 OSStatus | 与 B00 相同，仅 `ObserveSecurity=true` | 单次受控 Calendar/Contacts 刷新 | 仅新增 `keychain_copy/add/update` 的 class/status；不枚举/取出额外 secret；原调用次数与返回值不因观察而改变 | 待实机 |
| C00 仅 response URL | `Mode=adapt`；`RestoreRequestURL=true`；`NormalizeNumericDSID=false`；Security false | 使用与 B00 相同正常流程 | 仅成功、schema 合格的 login delivery，且内部 response URL 为 settings endpoint 时映回原 login URL；`adapter changed=1 dsid=0 url=1`；其他数据不变 | 待实机 |
| D00 单独 numeric DSID | `Mode=adapt`；`NormalizeNumericDSID=true`；`RestoreRequestURL=false`；Security false | 仅在结构证据显示 DSID 类型可能有问题时做单次实验 | 在原允许 scope 内，现存正整数 DSID→完全相同十进制字符串；不能补缺值、改 token/dataclass、跨 scope 搬字段 | 待实机 |
| E00 返回观察/禁用 | 回到 B00 或禁用并按 README 重载 | 重做同一非破坏性刷新 | 新进程显示预期配置；适配停止；账户/Keychain无桥接专属持久修改需要回滚 | 待实机 |

不要一开始同时开两个适配项。C00 或 D00 没触发 `adapter changed=1` 可能是 guard 正确拒绝、GSAPort branch未经过proxy、capability不足或本来无需改写，不应描述成修复失败或成功。D00 只是类型兼容实验；当前没有原日志证明 numeric DSID 是根因。

## 4. 日志读法与 native 路径

`session` 是每个注入进程初始化生成的随机标签；`seq` 是该进程局部顺序；`tx` 是局部计数。**transport_body 与 delivery 的 tx 分别生成，不能按同一个数字直接关联；native hooks 的 tx=0 也不具备账户级关联能力。** 应结合 syslog 的进程/PID、受控操作时间窗口和 endpoint kind 推断阶段关系，并标记关联置信度。不得把它包装成已实现完整 distributed tracing。

每进程最多记录 2000 个事件，之后一次 `budget_exhausted`；达到预算后，日志缺失不能用来判定原方法未执行。新 session 应重新启动一组独立测试，不是无限重试。

| ID | 当前事件或信号 | 要判断的问题 | 正确解释/限制 |
|---|---|---|---|
| N00 | `loaded`；`cap_protocol`；`cap_transport`；`cap_accounts`；`cap_appleaccount`；`cap_delegate` | 对象加载及 runtime ABI 检查是否允许对应 hooks | 缺失类/不匹配签名应 skip；不能强制猜 selector 地址。cap计数不是业务成功 |
| N01 | `transport_body endpoint=gsa`；`gsa_hsc/gsa_ec` 或 root status；init/complete字段 presence | 哪一轮 GSA 真的成功 | init通常看 s/B/i/sp/c presence；complete看 M2/spd/np presence；不打印任何字段值 |
| N02 | 独立 `-22406` transaction | 是否有不同 caller/renewal失败 | 单独保留失败，不能把它覆盖为成功，也不能推翻另一轮真实成功；定位时间/PID/阶段 |
| N03 | `delivery_response`；`delivery_body`；endpoint/delegate status/token_count | GSAPort交还给native的形态与transport是否一致 | HTTP、root status、mobileme status分别判断；`*_token_count>0`不证明token有效或用途一致 |
| N04 | `delegate_tokens_begin/end`；`delegate_complete_begin/end` | native delegate消费是否真正执行 | begin/end仅证明原方法返回；void方法返回不等于持久化完成 |
| N05 | `provision_response_begin/end` | native `AAAccount`是否消费provisioning response | 无事件先查cap和实际流程，不直接补写整个response |
| N06 | `account_provisioned_begin count=...`；`account_enabled_begin count=...`；`account_enabled_one` | server provision与用户enabled是否走到native setter | 数量相同不等于集合相同；当前日志不记录dataclass标识，不能直接定位具体差异 |
| N07 | `account_dsid_begin/end`；`account_credential_begin/end` | identity/credential是否交给native对象 | 当前事件不记录参数非空或实际值；调用出现不能证明它们有效 |
| N08 | `native_save_tokens_begin/end`；`native_save_password_begin/end` | native保存函数是否被调用 | 是观察原函数，不是桥接层写secret；不因看到save_password就认为密码泄露或正确 |
| N09 | `account_save_begin/result`；`account_save_verified_begin/result` | native store completion是否返回success | caller未给completion时只有begin；success=1仍需consumer原查询和服务测试 |
| N10 | `configured_sync success=0/1` | native是否接受configured sync account | success=1不是所有dataclasses/服务同步成功 |
| N11 | `account_read_credential present=0/1`；可选Keychain OSStatus | 原consumer查询能否取得credential | present=1只说明对象存在；-25300是item未匹配，不等价Apple拒绝密码 |
| N12 | `account_store_changed`；dataaccessd等原有日志 | 保存后是否出现native通知与consumer刷新 | IB6监听本进程NSNotification；不能据此宣称Darwin广播或所有daemon都已reload |

当前第一版没有给每个 daemon 实现专有 reload/credential hook；daemon侧结论需要它们原有日志、用户正常服务行为，或后续经过版本验证的观察点。不要在报告中把架构候选hook写成已实现功能。

## 5. 离线 native/fixture 场景

这些场景使用合成 plist、合成protocol client和无网络对象，不使用真实账号。现有 `tests/native_policy.m` 可验证policy；proxy生命周期场景需同样经过真实Foundation运行的回调harness。**文件中存在case或静态audit通过，都不能替代执行结果**；最终运行记录以实际测试输出为准。

| ID | 输入/事件 | 必须验证的结果 | 覆盖层 |
|---|---|---|---|
| F00 | 四个允许endpoint；其他scheme/host/port/path；userinfo、编码别名、dot/path参数 | 只允许policy定义的HTTPS443目标；其他不适配；当前policy按scheme/host/port/path分类，query/fragment行为需如实记录 | policy |
| F01 | observe、缺Mode、缺适配选项、string `true`、number `1` | 无适配；布尔开关只接受真实CFBoolean | policy |
| F02 | HTTP401/403/500、3xx、有body但失败 | 状态/body/error保留，不伪造200/0，不取得适配authority | policy+proxy |
| F03 | malformed plist、array root、空data、非plist、缺identity/tokens | 原NSData对象不变；不会补token、dataclass或DSID | policy |
| F04 | root/delegate status缺失、非零、string `0`、float0、BOOL | 按endpoint guard拒绝；delegates要求overall和mobileme明确整数0；settings/login允许缺root status仅当其他shape guard满足 | policy |
| F05 | numeric DSID：正整数、LLONG_MAX、0/负数、BOOL、float、溢出、缺失、已有字符串 | 只转换允许的正整数；不经浮点舍入；已有字符串不重写；无token/dataclass变化 | policy |
| F06 | 多delegate；root和mobileme有不同identity/tokens | 只变选中endpoint scope的一项；其他delegate和root保持；禁止nested flatten/跨scope复制 | policy |
| F07 | XML与binary plist；重复调用 | 序列化格式保留；修改后再调用幂等；binary MIME不误改成XML | policy+proxy |
| F08 | response URL已正确、是settings内部URL、未知host、HTTP失败/schema失败 | 仅C00允许的login→settings情况修复；URL-only正文/headers不需要重序列化；不把error响应修成success | proxy |
| F09 | DSID转换后带旧Content-Length/Encoding/ETag/Digest等 | stale body metadata清理且长度对应新bytes；合法其他headers/HTTP status保留；适配结果禁缓存 | proxy |
| F10 | 正文恰为2MiB、跨chunk超过2MiB、单chunk超大 | 边界内可guard；超过立即放弃适配，按顺序完整回传原response与bytes一次；后续chunk不重复、不丢失 | proxy |
| F11 | response→部分data→failure；无response直接failure | held prefix正确释放，原NSError传回一次，无finish成功；不泄露body到日志 | proxy |
| F12 | stopLoading后，upstream已排队response/data/finish/failure | terminal tombstone继续拦住晚到回调，不新建活跃proxy；不再向原client发送任何事件；无重复terminal | proxy |
| F13 | client在didReceiveResponse/didLoadData内重入cancel；并发cancel/finish | 无死锁/崩溃；cancel之后不补data/finish；最多一次terminal回调 | proxy |
| F14 | redirect、重复response、auth challenge/cancel challenge、cache validity | 原callback语义保留；redirect后适配authority撤销；challenge不被代理自行接受；重复response不混合两份body | proxy |
| F15 | unique secret marker出现在未知key/value、error text、DSID/token/string status | 摘要和日志绝不出现marker；只输出固定词汇、有限integer/boolean、presence/count | privacy |
| F16 | 每类hook签名匹配、未知类、错误参数数/类型/BOOL编码 | 匹配才装；未知ABI skip；bool兼容只按实际encoding；不加载private framework强行满足 | runtime |
| F17 | 一次real original Security call、TLS重入/日志重入 | 原函数被调用一次，返回值不变，thread guard不造成递归或残留 | runtime |
| F18 | 超过日志预算；进程重新初始化 | 2001为一次budget事件，此后静默；新session独立；不改变原操作 | privacy/runtime |

host测试通过不能证明Apple当前接受请求；macOS合成回调通过也不能替代iOS6.1.3运行时测试。安装测试前需以实际工具链完成armv7构建与载入验证，步骤由README提供。

## 6. 单服务实机矩阵

先完成B00的native链，再评估C00/D00是否改变失败边界。每行分别记录「本地状态」与「后端/业务」，防止把UI显示或单个token存在误当同步恢复。

| ID / 服务 | 本地状态通过条件 | 后端/业务通过条件 | 边界与预期 |
|---|---|---|---|
| S01 Calendar | 既有主/child account有效；native dataclass启用与save成功；原credential查询可用；不再由缺配置导致missing store | native DAV发现principal/collection及有效multi-status；下载测试事件；受控新增/修改/删除在另一设备对应 | 手动刷新先于push；2xx/207只证明该次请求，仍需对象级结果 |
| S02 Contacts | 同上，单独确认CardDAV backing/child及native store | 独立CardDAV发现、下载测试联系人，再受控修改/删除 | Calendar成功不等价CardDAV成功；不复制CalDAV credential猜测修复 |
| S03 Reminders / Notes | 先确定本版native dataclass与消费者；保留用户开关 | 仅对实际走旧DAV/IMAP路径的测试项验收 | 现代升级版Reminders/Notes协议不得仅靠版本伪装宣称兼容 |
| S04 默认iCloud Mail | native child Mail配置、credential获取与启用链齐全 | 分别验证IMAP接收和SMTP发送一封非敏感测试邮件；记录TLS与SASL错误层 | iCloudMailFix手动账户方案不证明默认iCloud Mail provisioning已修好；ATOKEN字段不能从macOS盲移 |
| S05 Backup | 可观察backupd原account query不再为null；native设置与原token读取有证据 | **不设“iOS6官方新备份成功”验收** | Apple自2024-12-18终止iOS5–8新备份/旧备份访问；本地修复与服务终止独立；禁止伪造backup success |
| S06 ubiquity / ubd | 有正常entitlement的现存app检查identityToken/container可用性；实际job/loaded image确认 | 只有已实现并证明对应后端兼容后，才对独立测试文档验证冲突/删除/下载 | 旧Documents and Data已迁往Drive；identityToken非nil不等于现代Drive同步；不修改文档目录制造成功 |
| S07 librariand | 确认该固件job/进程和native account notification响应 | 实际查询/元数据与服务结果一致 | `LBAccountNotification`存在不证明具体reload selector；不能猜Darwin通知 |
| S08 mstreamd / My Photo Stream | 观察native账户/认证/push/poll状态，不能自动启用 | **不设旧My Photo Stream恢复验收** | My Photo Stream于2023-07-26关闭；Shared Albums与iCloud Photos另测另判 |
| S09 Shared Albums | 单独native账户能力、服务配置及消费者证据 | 仅当该协议仍可用且实际验证时记录独立结果 | 不能用Photo Stream终止推断所有照片服务终止，也不能反向以一个服务成功覆盖其他项 |
| S10 aosnotifyd / AOS | 实际账户服务注册、topic监听和认证状态 | 对目标服务使用正常功能触发；不得发位置/erase等破坏性命令 | 默认不remove/re-add账户；不是所有AOS服务都属于本次补层实现 |
| S11 APNs | 设备原identity/mTLS可用、apsd连接、原topic注册有证据 | 另一设备变更后，本机收到目标服务通知并触发刷新 | `X-APNS-Token`存在、TLS成功、GSA成功均不能单独证明push到达；不改identity/激活证书 |
| S12 IDS / iMessage | profile auth及独立registration bindings/validation流程成功 | 单独发送与接收测试消息；FaceTime再单独测试正常通话 | Madrid delegate token成功不等于IDS注册/消息/通话成功；不向未知服务重放token |

服务终止依据见 [EVIDENCE_SOURCES.md](EVIDENCE_SOURCES.md) 的 O04–O07；本地症状改善不能消除这些边界。

## 7. 失败判定树

```text
出现异常
  ├─ 没有loaded/capability不足
  │    → 检查注入范围、系统版本、包加载和ABI；记录skip，不猜签名
  ├─ GSA失败（含独立-22406）
  │    → 保留本次caller/时间/阶段，与成功transaction分开；不补写dataclass/secret
  ├─ GSA成功、delegates HTTP或status失败
  │    → 在服务授权响应边界定位；不强制改status为0
  ├─ delegates成功、native消费/provision事件缺失
  │    → 先核cap和路径；比较delivery结构/response metadata；C00独立验证
  ├─ native消费出现、provision/enable/save缺失或失败
  │    → 区分server能力、用户选择、主/child关系与native错误；不全开dataclasses
  ├─ save成功、原credential不存在或Keychain -25300
  │    → B10单独观察原查询；定位backing account/UUID/accessibility上下文；不复制主密码
  ├─ credential与local store可用、请求TLS失败
  │    → 检查TLSFix实际加载/trust/mTLS；不跳过证书验证
  ├─ TLS成功、具体服务401/协议不兼容
  │    → 单服务协议/鉴权分析；不能全局改版本或猜token mapping
  ├─ 手动刷新成功、push不来
  │    → 单独APNs identity/connection/topic链；不再重建账户
  └─ local状态完整、后端已官方终止
       → 标记unsupported/retired；报告本地改善，不能返回伪成功
```

每个分支到达后只改变一个有证据的变量，保存前后日志。通用通知策略始终是：用户正常操作→native账户保存→native通知/插件→consumer刷新。IB6只观察，不猜通知名，不广播伪事件，不blanket kill守护进程。

## 8. 结果记录模板

| 测试ID | 版本/配置 | 进程、session、时间窗口 | native结果 | 服务结果 | 证据文件/行号 | 结论 |
|---|---|---|---|---|---|---|
| 例：B00/S01 | 由测试者填写 | 由测试者填写；不含账号 | 未测试 | 未测试 | 原文件当前缺失 | 待验证 |

结论只能使用「通过」「失败」「未触发」「不适用」「未测试」「后端已终止」等明确状态。不能把未触发当通过；不能把设备成功写成只有合成测试依据；不能只写“iCloud works”覆盖所有服务。
