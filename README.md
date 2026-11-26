# 短视频资料库（ShortsLibrary）

自用 iOS 17+ 本地收藏库，支持抖音、快手、小红书的视频/图片/图文，以及 B站的视频/图片/动态/音频解析入库。

## 当前能力

- 首页统一输入框：粘贴任意平台分享文案，实时识别平台并一键解析入队
- 首页自动识别剪贴板中的抖音/快手/小红书/B站链接，并提示一键解析
- 支持系统分享面板：在其他 App 分享文本或链接时选择“短视频资料库”，通过 App Group 回传后自动解析入库
- 粘贴分享文案或链接，自动提取 URL
- 解析公开分享页的标题、作者、文案、封面、视频/音频直链、图片列表
- WKWebView 兜底读取公开页面，不模拟登录
- 原样下载封面、视频、图文原图，不转码
- 下载进度显示、断点续传、失败保留元数据
- 后台 `URLSession` 下载，App 被系统重新拉起时仍可完成文件落盘
- 下载队列：常规解析与重试任务统一入队，支持并发数设置、仅 Wi-Fi 下载、完成通知
- 最近删除：30 天后自动清理，支持恢复与彻底删除
- `library.json` 元数据备份与恢复
- SwiftData 管理元数据，原文件存于 App 沙盒 `Library/Application Support/ShortsLibrary/`
- 资料库浏览、搜索、分享、保存到相册、导出到备忘录、删除
- 可选 AI 解析：预设 Qwen-VL / 豆包 / 智谱 / Kimi / OpenAI / 自定义 OpenAI 兼容接口，结合平台文案与视频关键帧生成摘要、关键看点和标签
- iPad 自适应分栏界面

## AI 解析与隐私

AI 解析默认关闭。开启后，标题、平台文案、封面和抽帧画面会发送到你在「我的」→「AI 解析设置」中选择的服务商；API Key 按服务商隔离保存在系统 Keychain，不写入 `library.json` 备份。服务商预设均为 OpenAI 兼容 Chat Completions 接口，可自由切换模型或填写自定义地址。

## 明确不做

- 不破解平台签名/风控参数
- 不模拟登录、不注入 Cookie
- 不去水印、不调用私有接口
- 不批量抓取或分发他人内容

## 运行

1. 用 Xcode 打开 `ShortsLibrary.xcodeproj`
2. 选择目标设备或模拟器
3. 在 Signing & Capabilities 中选择你的 Personal Team（免费 Apple ID 即可）
4. 修改 Bundle Identifier 为唯一值（默认 `com.leo.shortslibrary`）
5. Command + R 运行

免费签名 7 天到期后，不要删除 App，直接重新从 Xcode 运行覆盖安装即可保留沙盒数据。侧栏“数据”区可导出/恢复 `library.json`；该 JSON 只含元数据，原媒体文件请通过系统分享面板另行备份。

## 工程生成

`project.pbxproj` 由 `generate_xcodeproj.py` 生成。新增 Swift 文件后执行：

```bash
python3 generate_xcodeproj.py
```

## 依赖

无第三方依赖。iOS 17 / Swift 5 语言模式。
