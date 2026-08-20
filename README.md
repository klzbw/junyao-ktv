# 骏耀K歌 · junyao-ktv

局域网自建 KTV 点歌系统。一台机器 + Docker，就能在家里/小型场所搭出电视端点歌、手机扫码点歌、后台曲库管理的完整一套，MV 支持本地目录和网盘/网络路径（含 STRM）两种来源，播放端自带原唱/伴唱切换、HLS 硬件转码加速。

镜像地址：[`ma303973022/junyao-ktv`](https://hub.docker.com/r/ma303973022/junyao-ktv)

## 功能特性

- **三端合一**：TV 播放端（电视/投影仪全屏播放）、手机扫码点歌端（无需安装 App）、Web 曲库管理后台，三者通过同一个容器、同一个端口提供。
- **原唱/伴唱切换**：源文件有真实双音轨时走 HLS 多音轨切换；只有单音轨立体声源时自动降级为 Web Audio 声道复制兜底，两种模式对用户都是无感的一键切换。
- **硬件转码加速**：默认支持核显 VAAPI 硬件编解码，检测不到硬件时自动回退纯软件编码；也可选启用 NVIDIA NVENC。
- **本地曲库 + 网盘/STRM 曲库**：本地 MV 文件和网盘挂载目录（fnOS 网盘挂载、rclone、alist 等）、`.strm` 指针文件都能作为曲库来源混用，网络路径播放前会先缓存到本地，避免慢速网盘拖垮探测/播放，缓存策略（空间上限、保留天数、并发数）后台可调。
- **自定义文件名解析**：曲库管理后台支持按自己曲库真实的命名习惯自定义解析模板，一键从文件名批量提取歌手/歌名/语种/风格，支持"歌手&歌手"这类多歌手写法。
- **歌手头像**：按歌手名放对应图片即可在 TV 端「歌星」列表显示真人头像，没有配图自动用姓名首字兜底。
- **点歌队列 / 历史 / 收藏**：手机端点歌、置顶、删除，播放历史和收藏记录持久化保存。

## 快速开始

```yaml
services:
  junyao-ktv:
    image: ma303973022/junyao-ktv:1.2.0
    container_name: junyao-ktv
    restart: unless-stopped
    ports:
      - "8083:8080"          # 访问端口：http://局域网IP:8083
    environment:
      - TZ=Asia/Shanghai
      - PORT=8080
      - DATA_DIR=/data
      - ADMIN_PASSWORD=admin888          # 管理后台("/admin")登录密码，建议改掉
      - VAAPI_DEVICE=/dev/dri/renderD128 # 核显硬件转码用，没有核显就删掉这行
      - HLS_CACHE_MAX_AGE_DAYS=3         # 转码缓存超过几天没人点就自动清理
      # 用 NVIDIA 显卡转码(NVENC)就取消下面两行注释，同时取消最下面 runtime: nvidia 的注释
      # - NVIDIA_VISIBLE_DEVICES=all
      # - NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
    volumes:
      - /path/to/your/data:/data                 # 应用数据(数据库、封面等)，必须挂载

      # 曲库挂载：按需增删，本地曲库挂到 /mv/<自定义名>，网盘曲库挂到 /mv-net/<自定义名>
      - /path/to/local/library1:/mv/library1
      - /path/to/local/library2:/mv/library2
      - /path/to/netdisk/library:/mv-net/netdisk1
      - /path/to/singer/avatars:/singer           # 歌手头像目录，图片名对应歌手名，如 周杰伦.jpg
      # 挂载完成后，还需要去后台「曲库管理→曲库来源」里把新目录逐个启用，才会真正参与扫描
    devices:
      - /dev/dri:/dev/dri     # 核显硬件转码用，没有核显就删掉这行
    # runtime: nvidia         # 用 NVIDIA 显卡转码时取消注释(同时打开上面两行 NVIDIA 环境变量)
```

启动后访问 `http://宿主机IP:8083` 即为导航页，包含 TV 播放端、曲库管理后台、手机点歌二维码入口。曲库管理后台首次打开会提示设置管理员密码，之后每次登录都需要输入。

## 目录挂载说明

| 容器内路径 | 用途 | 必须挂载 |
| --- | --- | --- |
| `/data` | 数据库、封面等应用数据持久化 | 是 |
| `/mv` | 本地曲库文件，把 MV 直接拷贝进来 | 否（不用本地曲库可不放内容） |
| `/mv-net` | 网络/网盘曲库来源目录，可以是网盘挂载点、rclone/alist 挂载点，或直接放 `.strm` 指针文件 | 否（不用网盘曲库可不放内容） |
| `/singer` | 歌手头像图片，文件名（不含后缀）与歌手名完全一致即可自动命中 | 否（可选功能） |

`/mv`、`/mv-net` 挂进去之后，具体启用哪些子文件夹作为曲库来源、网络路径是否走本地缓存，都在「曲库管理」后台的「曲库来源」面板里配置，保存后立即生效，不需要重启或重建容器。

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PORT` | `8080` | 容器内监听端口，一般不需要改，改端口用 `ports` 映射即可 |
| `DATA_DIR` | `/data` | 数据库/封面存储目录 |
| `SINGER_DIR` | `/singer` | 歌手头像图片目录 |
| `VAAPI_DEVICE` | `/dev/dri/renderD128` | 核显硬件转码用的渲染节点路径 |
| `HLS_CACHE_MAX_AGE_DAYS` | `3` | 转码缓存多少天未被重新点唱后自动清理（可在后台「缓存清理」面板覆盖） |
| `SOURCE_CACHE_MAX_MB` | `51200`（50GB） | 网络曲库本地缓存空间上限（可在后台「曲库来源」面板覆盖） |
| `SOURCE_CACHE_MAX_AGE_DAYS` | `14` | 网络曲库本地缓存保留天数（可在后台覆盖） |
| `SOURCE_CACHE_CONCURRENCY` | `2` | 网络曲库并发缓存拷贝数（可在后台覆盖） |

## GPU 硬件转码

- **核显 VAAPI**：宿主机有核显时，保留 `devices: - /dev/dri:/dev/dri` 即可自动启用；没有核显/独显的机器，把这两行删掉，会自动回退纯软件编码（libx264 + aac）。
- **NVIDIA NVENC**（可选）：先在宿主机完成 `nvidia-container-toolkit` 安装，并执行 `nvidia-ctk runtime configure --runtime=docker` 重启 Docker 服务，确认 `docker info` 能看到 `nvidia` runtime；然后在 compose 文件里加上：

  ```yaml
      runtime: nvidia
      environment:
        - NVIDIA_VISIBLE_DEVICES=all
        - NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
  ```

## 版本

当前镜像版本：`1.1.2`

## 使用边界与维护建议

网络依赖：手机点歌与 电视播放必须在同一局域网，跨网段或公网访问需额外配置反向代理与认证
双音轨优先级：推荐使用原生双音轨MV文件以获得最佳切换体验；单音轨双声道文件虽兼容，但切换时可能有轻微音量跳变
歌手头像匹配：/singer目录下图片文件名需与歌曲元数据中的歌手名精确匹配（大小写敏感），否则不显示头像
缓存清理时机：自动清理在每日固定时间触发，非实时；若磁盘紧张，可临时调低HLS_CACHE_MAX_AGE_DAYS或手动删除/data/hls_cache子目录
密码重置：首次设置密码后无找回机制，遗忘需删除/data/config.db重启重新设置（会丢失曲库编辑记录）
性能瓶颈：软编模式下4K@60fps转码可能卡顿，建议此类素材预处理为1080p或启用硬件加速
需注意：这个应用不是流媒体平台，不提供在线曲库，所有内容依赖本地准备。首次部署建议先用少量测试视频验证转码链路，再批量导入曲库，避免大规模转码阻塞初始体验。
