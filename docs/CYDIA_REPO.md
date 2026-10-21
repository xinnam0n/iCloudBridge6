# iCloudBridge6 的 GitHub / Cydia 发布

本项目发布的是 **iOS 6 诊断 Alpha**。可下载或可安装不代表 iCloud 同步已经修复。首次实机目标仍为 iPod touch 5 / iOS 6.1.3、armv7、rootful jailbreak。默认只观察；转换功能默认关闭，没有新造凭据、写 Keychain、自动启用 dataclass 或强制重启守护进程的安装脚本。

## 仓库组成

源码仓库保存 Theos 工程、文档、测试和发布工具；Cydia 访问的是 GitHub Pages 上的平面 APT 目录。Pages 网站根目录应包含：

```text
index.html
.nojekyll
Packages
Packages.gz
Packages.bz2
Release
SHA256SUMS
repository.json
pool/
  local.legacyapple.icloudbridge6_<actual-version>_iphoneos-arm.deb
```

`Packages` 来自实际 `.deb` 的 control 元数据，补充相对下载路径、字节数和 MD5/SHA1/SHA256。保留 `Name`、`Author`、`Depends` 等 Cydia 字段及 Description 的续行。`Release` 为三个索引提供大小和校验值；`SHA256SUMS` 与 `repository.json` 便于在电脑上核对下载包。MD5/SHA1 仅为旧客户端兼容保留，额外提供 SHA256。

当前源 **未签名**，没有 `Release.gpg`、`InRelease` 或虚构的公钥。校验和不能替代发布者身份验证。若以后加入签名，应单独审查签名密钥、CI secrets、签名流程和设备上可信公钥的分发；当前生成器会拒绝覆盖含旧签名的目录，避免留下与新索引不匹配的签名。

## 生成条件

`tools/cydia_repo.py` 仅需 Python 3 标准库。它不编译 tweak，也不生成占位安装包。输入必须是真实构建结果，执行以下检查后才生成可订阅的索引：

1. Debian 2.0 `ar` 结构，按序包含 `debian-binary`、`control.tar.gz`、`data.tar.gz`。为 iOS 6 的旧 dpkg 使用 gzip；不接收 xz/zstd 包后假装兼容。
2. 单个 control stanza，包名为 `local.legacyapple.icloudbridge6`，架构为 `iphoneos-arm`，存在有效 Version、Description、Maintainer。
3. 存在非空 `/Library/MobileSubstrate/DynamicLibraries/iCloudBridge6.dylib` 和同名 `.plist`。后者仅能注入本项目已经审查的进程白名单，必须包含 Preferences 和 accountsd，不扩大到 apsd/imagent。
4. dylib 为 little-endian、32 位、CPU_TYPE_ARM / CPU_SUBTYPE_ARM_V7 的 `MH_DYLIB`，拥有可执行 segment 和一个 `LC_VERSION_MIN_IPHONEOS`，其最低版本不高于 6.1.3。拒绝 arm64、模拟器文件、文本伪装 dylib 和高于目标系统的部署版本。
5. 归档路径不越界，不接收 symlink、重复路径或 maintainer scripts。生成器不提取文件到系统位置，也不执行包内脚本。

这些检查只证明容器与一部分二进制结构符合目标；它们 **不证明源码出处、导入符号在 iOS 6 均可用、Substrate ABI 正确、签名可被设备接受或实际同步成功**。二进制的进一步检查由构建流程执行；最终还需 [实机测试矩阵](TEST_MATRIX.md)。代码签名区域若存在会检查边界，原 `.deb` 字节保持原样，不重签、不剥离 dylib 或签名。

未构建出通过检查的 `.deb` 时，不创建可安装条目，不将测试 fixture、空包、仅含 README 的包或源码 zip 当作插件发布。`tests/test_cydia_repo.py` 中的结构 fixture 只存在于临时测试目录，永远不能作为发布输入。

## 生成与部署

在 Theos 构建和需要的验证通过后，从工程根目录执行。三个变量分别设为本次实际 `.deb` 路径、已配置的 Pages 根 URL、实际 GitHub 源码 URL：

```sh
python3 tools/cydia_repo.py \
  --deb "$IB6_DEB" \
  --output repo-staging \
  --base-url "$PAGES_URL" \
  --repository-url "$REPOSITORY_URL"
```

`--base-url` 为 HTTPS，结尾 `/` 会自动补齐；不得包含用户名、密码、query 或 fragment。`--repository-url` 为 `https://github.com/owner/repository` 形式的真实仓库。不要将服务器 token、Apple ID 或设备日志加入 URL、仓库或工作流。

每次用新的 staging 目录生成，随后一次部署整份目录。所有输入检查都在写入前完成；各个文件采用临时文件加原子替换，但不提供整目录事务，不能在正在供客户端下载的目录里边改边发布。默认输出只包含本次构建包。

如需保留历史版本，可先将历史 `pool/` 拷到新的 staging 目录再执行。生成器会重新验证并索引其中每个 `.deb`，不会删除 pool 中的历史包，不允许同一版本对应不同字节；需要改变内容时递增 control Version。历史包若损坏，生成失败，现有索引不会被重写。不要将源码目录作为输出路径；生成器拒绝覆盖含其他文件的目录。

上传并部署 `repo-staging` 为 GitHub Pages artifact。是否启用 Pages、选择 Actions 构建来源、部署权限和公开 URL，以仓库实际状态为准。生成本地目录、上传源码、工作流显示绿色、Pages 可访问、Cydia 实机完成安装是五个不同的验收点，发布时逐一记录实际结果。

## 发布验证

电脑上运行：

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

发布后核对：

- Pages 根页面、`Release`、`Packages.bz2`、`Packages.gz` 和索引引用的 `.deb` 均返回实际文件，无 404/登录页/源码 HTML。
- 下载包 SHA256 与 `Packages`、`SHA256SUMS`、`repository.json` 相同。
- `Packages` 的 Architecture、Version、Depends 和 Filename 正确，文件大小符合实际字节数。
- 在 iPod 的 Cydia 添加实际 Pages 源 URL，刷新后只出现已经构建的版本，依赖解析通过，再执行一次安装、手动重启、观察和卸载测试。

GitHub Pages 的 HTTPS 在旧设备上是否可连接，取决于该设备实际网络/TLS 环境；TLSFix 已安装不等于 Cydia 的每条传输路径都已验证。若有 TLS/证书报错，应保留具体错误并诊断，不关闭证书验证，也不把未测试的 HTTP 跳转当作已可用源。可在电脑上核验后通过 README 的 SSH/dpkg 流程手工安装同一包。

源页面提供 `cydia://` 添加链接和可复制 URL，不依赖 JavaScript、外部字体、现代布局或客户端打包脚本，便于旧 Safari/Cydia 阅读。页面明确标注诊断 Alpha、默认观察、实机未验证和未签名。

## 设备安装和回滚

在 Cydia → 软件源 → 编辑 → 添加，输入已部署且通过下载检查的源地址，刷新后搜索 iCloudBridge6。安装后手动重启；首次不改变转换开关，不退出 Apple ID，不清空 Keychain。按 [README](../README.md) 和 [测试矩阵](TEST_MATRIX.md) 收集最少必要日志。

正常卸载可在 Cydia 移除包，或通过 SSH 执行：

```sh
dpkg -r local.legacyapple.icloudbridge6
```

再手动重启，移除已经载入进程的 dylib。如出现崩溃，使用 SSH 或越狱安全模式将本包的 dylib 改名为 `.dylib.disabled` 后重启，保留其他 tweak、账户与凭据。

## 格式依据

- [Saurik：How to Host a Cydia Repository](https://www.saurik.com/packaging.html)：Cydia 使用 APT 仓库、平面 Packages/Packages.bz2、Cydia 扩展字段、Release 与可选签名。其旧 UI 操作描述不作为当前设备 UI 的证据。
- [Debian dpkg：deb(5)](https://manpages.debian.org/bookworm/dpkg-dev/deb.5.en.html)：ar 的成员次序、Debian 2.0 格式以及各压缩格式的 dpkg 版本条件。
- [Debian Policy：Control files and their fields](https://www.debian.org/doc/debian-policy/ch-controlfields.html)：UTF-8、单字段、续行及 control stanza 规则。
- [Debian Policy：Filename / Size / MD5sum](https://www.debian.org/doc/debian-policy/ap-pkg-controlfields.html)：索引下载路径和包校验元数据。
- [Apple XNU：mach-o/loader.h](https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h)：32 位 Mach-O header、load commands、segment、minimum-version 和 code-signature 结构。
