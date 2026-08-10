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
    image: ma303973022/junyao-ktv:1.1.2
    container_name: junyao-ktv
    restart: unless-stopped
    ports:
      - "8083:8080"
    environment:
      - TZ=Asia/Shanghai
      - PORT=8080
      - DATA_DIR=/data
      - SINGER_DIR=/singer
      - VAAPI_DEVICE=/dev/dri/renderD128
      - HLS_CACHE_MAX_AGE_DAYS=3
    volumes:
      - /path/to/junyao-ktv/data:/data
      - /path/to/junyao-ktv/mv:/mv
      - /path/to/junyao-ktv/mv-net:/mv-net
      - /path/to/junyao-ktv/singer:/singer
    devices:
      - /dev/dri:/dev/dri   # 没有核显/独显就把这两行删掉
```

```bash
mkdir -p /path/to/junyao-ktv/{data,mv,mv-net,singer}
docker compose up -d
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
