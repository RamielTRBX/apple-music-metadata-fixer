# Apple Music 音乐信息订正 1.3.0

首个公开版本。

## 1.3.0

- Added perceptual album-artwork comparison.
- Rejects candidate albums whose covers clearly differ from the local artwork.
- Keeps artwork comparison optional when either side has no image.

## 1.2.1

- Fixed `Shandy Gaff` being incorrectly matched to `Aoi`.
- Fixed `Adapt` being incorrectly matched to `魚図鑑`.
- Required exact track positions to pass the duration check before a candidate
  can be used.
- Added verified mappings for `シャンディガフ` and `アダプト(ADAPT)`.

## 功能

- 自动检测 Apple Music 资料库中新增的歌曲。
- 按艺人、专辑、曲序和时长匹配官方元数据。
- 专辑搜索失败时使用歌曲名进行二次匹配。
- 支持英文、日文和中文作品的官方标题语言。
- 识别简繁体中文差异。
- 避免用英文标题覆盖已有日文或中文标题。
- 自动保存修改备份，并支持一键撤销。
- 区分需要处理的歌曲与已经正确的非日文作品。

## 安装

1. 下载并打开 DMG。
2. 将应用拖入“应用程序”。
3. 首次运行时允许应用控制“音乐”。

## 隐私与安全

- 不上传音频。
- 不需要额外账号。
- 只通过 Apple iTunes Search API 查询艺人、专辑和歌曲名称。
- 修改前自动生成本地备份。

## 说明

本应用使用 ad-hoc 签名，未经过 Apple 公证。本项目与 Apple Inc. 无隶属关系。
