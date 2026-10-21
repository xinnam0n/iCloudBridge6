# GitHub 构建与 Cydia 仓库发布

工作流 `.github/workflows/build-and-publish.yml` 分三个阶段：Mac 编译并执行 Foundation policy/proxy 测试；Linux 交叉编译真实 armv7 tweak；两者通过后才把验证过的 `.deb` 和 Cydia 索引部署到 GitHub Pages。PR 只测试和构建，不发布。没有账号密码、Apple token、设备 SSH 凭据或 PAT。

## 固定输入及来源

| 输入 | 固定版本 | 来源与核验 |
| --- | --- | --- |
| Theos | `304e0799973e8145f32e4ca2de6c747a84b758ce` | [官方仓库 commit](https://github.com/theos/theos/commit/304e0799973e8145f32e4ca2de6c747a84b758ce)；submodules 使用此 commit 记录的版本 |
| Linux x86_64 clang/cctools/ldid | `sbingner/llvm-project` 的 `v10.0.0-2` | [发布说明及工具链](https://github.com/sbingner/llvm-project/releases/tag/v10.0.0-2)；[Theos 历史官方安装文档](https://github.com/theos/theos/wiki/Installation-Linux/a055b938fd3a5b777d2913ab8dec3e93cde31000) |
| 工具链 SHA-256 | `0e4e21888517d0cd8c96d1e297dd17125546a0366410a33b811910083cabe110` | 本轮下载公开 release asset 计算；安装脚本在解包前必须匹配 |
| SDK | 官方 `theos/sdks` 的 `iPhoneOS9.3.sdk`，commit `0222fd5413cf4b9af096f37b4621afa2688572f7` | [SDK 仓库](https://github.com/theos/sdks/tree/0222fd5413cf4b9af096f37b4621afa2688572f7/iPhoneOS9.3.sdk) |
| GitHub Actions | checkout v4、setup-python v5、artifact v4、Pages actions | 均固定到官方仓库在本轮核查的 40 字符 commit，而非浮动 tag |

上游工具链发布没有独立 checksum/signature，本项目固定的是本次取回字节的 hash，不能把它表述为上游签名。SDK 和工具链只进入临时构建目录，不上传到本项目源码或 Cydia 仓库。Linux 系统包和 GitHub runner 镜像仍由平台更新；这是固定主要输入的可复建流程，不保证逐字节相同输出。

## SDK 与目标系统的区别

源码 Makefile 为有旧开发环境的用户保留 `iphone:clang:6.1:6.0`。CI 使用明确的 `TARGET=iphone:clang:9.3:6.0 ARCHS=armv7`；官方 SDK 仓库没有 6.1。`6.0` 是最低部署版本，`9.3` 是编译 SDK，不能把此构建称为 SDK 6.1 构建或 iOS 6.1.3 实机成功。编译对未做保护的较新 API 使用 availability 错误检查；动态调用的私有 selector 仍依赖源码中的运行时 ABI/能力检查和实机测试。

发布前读取包内真实 dylib，拒绝其他架构、最低系统版本不等于 6.0、SDK 字段不等于 9.3、现代/其他平台的 Mach-O 版本命令、未知 linked library、缺少 Substrate 链接或缺少嵌入签名。保留 `otool`、undefined symbols、签名 entitlement 读取结果、包 SHA-256、source commit/run id。结构检查不能证明设备接受签名或所有私有 API 行为正常。

Theos 使用 `THEOS_PLATFORM_DEB_COMPRESSION_TYPE=gzip`，Cydia 发布器另行校验 `control.tar.gz` 与 `data.tar.gz`，以避免 iOS 6 的旧 dpkg 不支持现代压缩格式。没有安装/卸载脚本、自动杀 daemon 或强制 respring。

## 本地复现

在 Linux x86_64、已安装 `build-essential fakeroot rsync curl perl git libxml2 libtinfo5 xz-utils dpkg-dev` 的环境执行：

```sh
export THEOS="$(mktemp -d)/theos"
bash tools/ci-bootstrap.sh
export PATH="$THEOS/toolchain/linux/iphone/bin:$PATH"
make clean TARGET=iphone:clang:9.3:6.0 ARCHS=armv7
make package FINALPACKAGE=1 TARGET=iphone:clang:9.3:6.0 ARCHS=armv7 THEOS_PLATFORM_DEB_COMPRESSION_TYPE=gzip ADDITIONAL_CFLAGS=-Werror=unguarded-availability
```

Mac 测试使用 `sh tests/run-native.sh`；Python 测试使用 `python3 -m unittest discover -s tests -p 'test_*.py' -v`。Mac 测试通过只证明测试覆盖的主机行为，设备测试矩阵仍见 `TEST_MATRIX.md`。

## 首次发布与后续更新

GitHub 仓库 Settings → Pages → Build and deployment 选择 **GitHub Actions**。推送 main 自动触发；也可 Actions → **Build iOS 6 package and Cydia repository** → Run workflow。任何测试、编译、二进制或包格式检查失败都会阻止部署，保留原已上线站点。通过后 Pages 首页会显示可复制的 Cydia source 地址、当前包下载和实验状态；`build-reports/` 提供此构建证据。

CI 从 `control` 的 Version 读取基础版本，并用 Theos 的公开 `PACKAGE_VERSION` 接口生成唯一版本：`基础版本+ci.GITHUB_RUN_NUMBER.GITHUB_RUN_ATTEMPT`。例如第 10 次工作流的第 2 次尝试为 `0.1.0+ci.10.2`；下一次 run 为 `0.1.0+ci.11.1`。工具先校验基础版本与正整数编号，构建后再核对 `.deb` 内实际 Version，避免复用同一公共版本的文件名。正式功能版本仍应提升 `control` 的 Version。

此覆盖行为已核查 [固定 Theos 的 package.mk](https://github.com/theos/theos/blob/304e0799973e8145f32e4ca2de6c747a84b758ce/makefiles/package.mk)：用户 `PACKAGE_VERSION` 优先于默认 `THEOS_PACKAGE_BASE_VERSION`，`FINALPACKAGE=1` 时仍有效。编号随同一工作流的 run/attempt 增长；本工作流不保留历史版本池，新的成功部署仅提供当前构建。不要将较旧 run 的手动重跑当作发布新版本；应发起新 workflow_dispatch 获得新的 run number。

诊断包默认 observe，候选适配仍需用户在保留 baseline 后逐项启用。仓库能下载安装不等于已恢复同步，实机结果必须单独记录。
