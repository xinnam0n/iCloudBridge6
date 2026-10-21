# 首次本地交付验证状态与后续 CI

目标：iPod touch 5 / iOS 6.1.3。日期：2026-10-22。

以下记录首次 Windows 本地交付时的验证范围。后续 GitHub 构建结果以 [Actions](https://github.com/xinnam0n/iCloudBridge6/actions) 和软件源 build-reports 为准；CI 的 native 测试和二进制验证也不代表 iPod 实机测试。

## 已执行

- 检查本地项目、synced sources 及引用聊天：原始附件没有同步；只保留用户报告，不伪造原日志行号。
- 读取固定版本上游源码与 iOS 6.1 headers；明确与设备 6.1.3/已安装版本的差别。
- Windows 上执行 `python -m unittest discover -s tests -p 'test_*.py' -v`：8 项通过。涵盖单份 GSA complete 成功、失败与 init 区分、多 transaction 不合并、畸形状态、凭据不回显、固定 syslog 指标、解析失败和拒绝覆盖证据。
- 独立源码审查发现并修正代理取消后的回调复活、状态竞争、cache policy和 binary plist MIME问题。取消/完成后保留无 payload 的终态代理；所有回调串行检查终态。
- 3 份 plist 配置均成功解析；9 份 Markdown 文档的相对文件链接均存在。另一次独立审查发现的 URL-only header 测试预期已与生产行为对齐。
- 源码归档使用 tools/package.py 的显式允许范围；生成后复读 ZIP 每个成员并检查完整性，内含逐文件 MANIFEST.sha256，另提供整个 ZIP 的 SHA256。归档排除原始日志、私有证据、缓存、构建输出和设备二进制。

## 提供但尚未运行

- Native policy fixtures：exact endpoint、失败/畸形/缺字段、bool/float/overflow DSID、token/其他 delegate 不变、XML/binary 格式、幂等和隐私。
- Native proxy fixtures：回调顺序、observe 字节、取消/终态、超限、重复 response、错误回退、URL metadata 转换与 cache policy。
- `tests/run-native.sh`：需要 macOS Foundation/clang；它验证主机策略和代理，仍不能证明 iOS ABI。
- Theos armv7 dylib / .deb 构建：当前没有 Apple SDK、Theos、clang 或可用 WSL build 环境，未生成可安装二进制。
- 实机加载、hook 能力、GSAPort/TLSFix 共存、账户/Keychain 持久化和真实服务同步：未运行，需按 TEST_MATRIX.md 检验。

因此本交付是 **诊断与最小元数据适配的源码版本**，不是经过 iOS 6.1.3 验证的通用 iCloud 修复。源码静态检查和主机工具测试不能替代 native build 或设备成功。
