# 骏耀K歌 (junyao-ktv)

局域网 K 歌系统，运行在飞牛 fnOS 上。手机扫码点歌，电视/投影仪全屏播放，应用数据与 MV 曲库统一存储于应用默认共享目录，首次打开「曲库管理」时设置密码。

- 当前版本：`1.0.26`
- 运行平台：飞牛 fnOS（Docker 应用）
- 支持架构：x86_64, aarch64

## 功能特性

- 手机扫码点歌，电视端全屏播放
- 原唱/伴唱切换（基于 HLS 多音轨，不中断播放、进度可寻址）
- VAAPI 硬件转码优先，自动回退软件编码 (libx264)
- 支持视频格式：`.mp4` `.mkv` `.avi` `.flv` `.mov` `.webm` `.mpg`
- HLS 转码缓存每日自动清理，避免长期占用磁盘空间
- 渐进式曲库扫描 / 渐进式转码，边转边播
- 曲库管理后台（增删改歌曲、密码保护）

## 目录结构

```
.
├── manifest              # 应用包基础信息（飞牛 fnOS 应用中心识别用）
├── ICON.PNG / ICON_256.PNG
├── config/                # 应用级资源声明 / 运行权限
│   ├── resource
│   └── privilege
├── wizard/                # 安装/卸载向导脚本
├── cmd/                   # 安装/升级/卸载生命周期回调，运行状态探测
└── app/
    ├── ui/                 # 桌面入口图标与配置
    ├── config/             # Docker 项目资源声明（同 config/，随 app 一起打包）
    └── docker/
        ├── Dockerfile
        ├── docker-compose.yml
        ├── server/         # Node.js 后端 (Express + better-sqlite3 + ffmpeg)
        │   ├── index.js    # 路由、鉴权、HLS 播放、点歌队列、WebSocket
        │   ├── scanner.js  # 曲库扫描（含音轨探测、断链/死目录容错）
        │   ├── hlsgen.js   # HLS 转码（VAAPI 硬件加速 + 每日缓存清理）
        │   ├── db.js       # SQLite 表结构与迁移
        │   └── logger.js
        └── web/            # 电视端 / 手机点歌页 / 曲库管理后台的前端页面
```

## 本地打包为 .fpk

本项目使用飞牛官方的 `fnpack` 工具打包。在仓库根目录执行：

```bash
fnpack build
```

成功后会在当前目录生成 `junyao-ktv.fpk`，可在飞牛 fnOS 应用中心的「手动安装」入口安装，或使用：

```bash
appcenter-cli install-fpk junyao-ktv.fpk
```

`fnpack` 工具本身不随本仓库分发，请从飞牛开发者文档/工具页获取对应平台版本。

## 配置项

`app/docker/docker-compose.yml` 中可调整的环境变量：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `VAAPI_DEVICE` | `/dev/dri/renderD128` | 核显硬件转码渲染节点路径 |
| `HLS_CACHE_MAX_AGE_DAYS` | `3` | HLS 缓存最长保留天数，超过自动清理，不影响源 MV 文件 |
<img width="1920" height="919" alt="image" src="https://github.com/user-attachments/assets/5aa93b2c-0911-49ed-8710-6039eae27041" />
<img width="1920" height="919" alt="image" src="https://github.com/user-attachments/assets/b4f95eb3-d98a-41df-97f3-c5a6d7721b96" />
<img width="1920" height="919" alt="image" src="https://github.com/user-attachments/assets/e5c98caf-b7bf-4279-ba70-d576f7d14f55" />
<img width="1920" height="919" alt="image" src="https://github.com/user-attachments/assets/fcee82e3-101e-4947-a81e-3037c4b39f9b" />
<img width="1920" height="919" alt="image" src="https://github.com/user-attachments/assets/7bd9ca0f-2d80-4dc9-a07f-47e4b43461d3" />









