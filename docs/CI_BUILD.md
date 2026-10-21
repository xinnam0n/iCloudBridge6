# GitHub 构建与 Cydia 仓库发布

工作流 `.github/workflows/build-and-publish.yml` 分三个阶段：Mac 编译并执行 Foundation policy/proxy 测试；Linux 交叉编译真实 armv7 tweak；两者通过后才把验证过的 `.deb` 和 Cydia 索引部署到 GitHub Pages。PR 只测试和构建，不发布。没有账号密码、Apple token、设备 SSH 凭据或 PAT。

## 固定输入及来源

| 输入 | 固定版本 | 来源与核验 |
| --- | --- | --- |
| Theos | `304e0799973e8145f32e4ca2de6c747a84b758ce` | [官方仓库 commit](https://github.com/theos/theos/commit/304e0799973e8145f32e4ca2de6c747a84b758ce)；submodules 使用此 commit 记录的版本 |
| Linux x86_64 clang/cctools/ldid | `sbingner/llvm-project` 的 `v10.0.0-2` | [发布说明及工具链](https://github.com/sbingner/llvm-project/releases/tag/v10.0.0-2)；[Theos 历史官方安装文档](https://github.com/theos/theos/wiki/Installation-Linux/a055b938fd3a5b777d2913ab8dec3e93cde31000) |
| 工具链 SHA-256 | `0e4e21888517d0cd8c96d1e297dd17125546a0366410a33b811910083cabe110` | 本轮下载公开 release asset 计算；安装脚本在解包前必须匹配 |
| SDK | 社区镜像 `growtopiajaw/iPhoneOS-SDK` 的 `v1.0` release，asset ID `29205306`，`iPhoneOS6.1.sdk.zip` | [SDK 发布页](https://github.com/growtopiajaw/iPhoneOS-SDK/releases/tag/v1.0)，固定下载路径与下列 hash |
| SDK SHA-256 | `2696df17fc48e1b6ea3f7acd346b5f2356fb5c6cc60b0f3aaca0c24522d761de` | 本轮实际下载计算；与 [iPadScreen 作者记录](https://github.com/demirfirat/ipadScreen#ipad-app) 中的 hash 相同 |
| GitHub Actions | checkout v4、setup-python v5、artifact v4、Pages actions | 均固定到官方仓库在本轮核查的 40 字符 commit，而非浮动 tag |

上游工具链和 SDK 发布没有 Apple 官方签名证明，本项目固定的是本次取回字节的 hash，不能把社区镜像表述为 Apple 认证来源。SDK 固定 release 路径、asset ID 和完整内容 hash；release tag 本身可以移动，hash 才是此二进制输入的内容锁定。SDK 和工具链只进入临时构建目录，不上传到本项目源码或 Cydia 仓库，也不执行 SDK 内附工具。Linux 系统包和 GitHub runner 镜像仍由平台更新；这是固定主要输入的可复建流程，不保证逐字节相同输出。

## SDK 与目标系统的区别

实际交叉编译确认源码可编译为 armv7，但固定 Theos SDK 9.3 的 `libSystem.tbd` 引用了其目录里缺失的 `liblaunch`，而 10.3 的合并 stubs 缺少 ARMv7 必需的 `_objc_msgSend_stret`、`___udivdi3`、`__Unwind_SjLj_Register/Resume/Unregister` 导出，均未通过链接。CI 因此使用经过实际验证的 SDK 6.1 社区镜像，不补造导出、不添加动态查找来掩盖未解析符号。

本地 Makefile 和 CI 均使用 `TARGET=iphone:clang:6.1:6.0 ARCHS=armv7`。`6.0` 是最低部署版本，`6.1` 是编译 SDK。安装脚本在 hash 校验后读取 SDKSettings，要求 Version 为 6.1、CanonicalName 为 iphoneos6.1，并解析七个核心真实 dylib 的 armv7 slice；额外要求上述五个缺失导出确实存在于对应库的 armv7 符号表。报告包含各库 hash。SDK 6.1 构建仍不等于 iOS 6.1.3 实机成功；动态调用的私有 selector 仍依赖运行时 ABI/能力检查和实机测试。

交叉编译使用 `-fno-optimize-sibling-calls`，避免 clang 10 / 该版 cctools 对 ARM/Thumb ARC 尾调用分支的链接问题；实际失败位置为 `flushOriginal:` 中的 `_objc_release`。此选项保留普通调用/返回，不关闭 ARC、异常处理或链接符号检查。选项含义见 [Clang 命令行参考](https://clang.llvm.org/docs/ClangCommandLineReference.html#cmdoption-clang-foptimize-sibling-calls)，跨模式尾调用为何需要特殊 shim 见 [LLVM Mach-O ShimPass](https://android.googlesource.com/toolchain/lld/+/35c021c49f44cd4e06875c4b1398a2b3464132bb/lib/ReaderWriter/MachO/ShimPass.cpp)。

旧 SDK 没有新版 clang 使用的 `SDKSettings.json`。实际构建已确认最低版本为 6.0，但 SDK 被记录为 n/a；`-sdk_version` 会被 clang 生成的 `-platform_version` 覆盖而忽略。安装脚本因此只在临时 SDK 目录新增一个构建元数据文件 `SDKSettings.json`，其中 `Version` 直接取自已经验证的 SDKSettings.plist（6.1），不改 SDK 的头文件或 dylib 字节。此文件供 clang 正确生成 `-platform_version ios 6.0 6.1`；成品仍必须通过最低 6.0、SDK 6.1 的严格检查，检查前输出真实 load commands。

这一行为依据 Clang 10 的实际源码：[DarwinSDKInfo.cpp](https://github.com/llvm/llvm-project/blob/llvmorg-10.0.0/clang/lib/Driver/DarwinSDKInfo.cpp) 只从 JSON 中读取 Version；[Darwin.cpp](https://github.com/llvm/llvm-project/blob/llvmorg-10.0.0/clang/lib/Driver/ToolChains/Darwin.cpp) 的 addPlatformVersionArgs 在 SDKInfo 缺失时传入 0.0.0。没有补造二进制 SDK 标记或放宽验收条件。

发布前读取包内真实 dylib，拒绝其他架构、最低系统版本不等于 6.0、SDK 字段不等于 6.1、现代/其他平台的 Mach-O 版本命令、未知 linked library、缺少 Substrate 链接或缺少嵌入签名。保留 SDK 元数据/armv7 导出验证报告、`otool`、undefined symbols、签名 entitlement 读取结果、包 SHA-256、source commit/run id。结构检查不能证明设备接受签名或所有私有 API 行为正常。

Theos 使用 `THEOS_PLATFORM_DEB_COMPRESSION_TYPE=gzip`，Cydia 发布器另行校验 `control.tar.gz` 与 `data.tar.gz`，以避免 iOS 6 的旧 dpkg 不支持现代压缩格式。没有安装/卸载脚本、自动杀 daemon 或强制 respring。

## 本地复现

在 Linux x86_64、已安装 `build-essential fakeroot rsync curl perl git libxml2 libtinfo5 xz-utils unzip dpkg-dev` 的环境执行：

```sh
export THEOS="$(mktemp -d)/theos"
bash tools/ci-bootstrap.sh
export PATH="$THEOS/toolchain/linux/iphone/bin:$PATH"
make clean TARGET=iphone:clang:6.1:6.0 ARCHS=armv7
make package FINALPACKAGE=1 TARGET=iphone:clang:6.1:6.0 ARCHS=armv7 THEOS_PLATFORM_DEB_COMPRESSION_TYPE=gzip ADDITIONAL_CFLAGS="-Werror=unguarded-availability -fno-optimize-sibling-calls"
```

Mac 测试使用 `sh tests/run-native.sh`；Python 测试使用 `python3 -m unittest discover -s tests -p 'test_*.py' -v`。Mac 测试通过只证明测试覆盖的主机行为，设备测试矩阵仍见 `TEST_MATRIX.md`。

## 首次发布与后续更新

GitHub 仓库 Settings → Pages → Build and deployment 选择 **GitHub Actions**。推送 main 自动触发；也可 Actions → **Build iOS 6 package and Cydia repository** → Run workflow。任何测试、编译、二进制或包格式检查失败都会阻止部署，保留原已上线站点。通过后 Pages 首页会显示可复制的 Cydia source 地址、当前包下载和实验状态；`build-reports/` 提供此构建证据。

CI 从 `control` 的 Version 读取基础版本，并用 Theos 的公开 `PACKAGE_VERSION` 接口生成唯一版本：`基础版本+ci.GITHUB_RUN_NUMBER.GITHUB_RUN_ATTEMPT`。例如第 10 次工作流的第 2 次尝试为 `0.1.0+ci.10.2`；下一次 run 为 `0.1.0+ci.11.1`。工具先校验基础版本与正整数编号，构建后再核对 `.deb` 内实际 Version，避免复用同一公共版本的文件名。正式功能版本仍应提升 `control` 的 Version。

此覆盖行为已核查 [固定 Theos 的 package.mk](https://github.com/theos/theos/blob/304e0799973e8145f32e4ca2de6c747a84b758ce/makefiles/package.mk)：用户 `PACKAGE_VERSION` 优先于默认 `THEOS_PACKAGE_BASE_VERSION`，`FINALPACKAGE=1` 时仍有效。编号随同一工作流的 run/attempt 增长；本工作流不保留历史版本池，新的成功部署仅提供当前构建。不要将较旧 run 的手动重跑当作发布新版本；应发起新 workflow_dispatch 获得新的 run number。

诊断包默认 observe，候选适配仍需用户在保留 baseline 后逐项启用。仓库能下载安装不等于已恢复同步，实机结果必须单独记录。
