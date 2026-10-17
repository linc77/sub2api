# 77code 运维脚本

脚本从自身目录加载配置，可在任意工作目录运行。需要 `sh`、Docker CLI 和 curl，命令默认从 `PATH` 查找，支持 Linux 和 macOS。

## 查看运行状态

```sh
sh /opt/sub2api/ops/status-77code.sh
sh /opt/sub2api/ops/healthcheck-77code.sh
```

两条命令只读：检查应用、PostgreSQL、Redis 容器以及本地和公网 `/health`。任何检查失败时返回非零退出码，不会启动或重启服务、修改配置或重新加载隧道。健康检查使用 GET 请求，避免只检查首页或 HEAD 响应。

如果需要定时监控，可由现有监控系统读取退出码和标准输出；脚本本身不安装定时任务。

## 启动已有容器

```sh
sh /opt/sub2api/ops/start-77code.sh
```

这条命令会改变停止容器的运行状态，适合人工恢复服务。它先确认三个容器均存在，再依次启动 PostgreSQL、Redis、应用，并等待健康检查通过。已经运行的容器不会重启，启动依赖失败时不会继续启动应用。

脚本只使用 `docker start`，沿用已有镜像、网络和数据挂载，不执行 Compose、拉取镜像或创建容器。容器缺失时会报错，首次部署请参阅 [VPS 重建文档](../deploy/VPS_REBUILD_CN.md)。

当前服务器的应用属于 `deploy` Compose 项目，数据库和 Redis 属于 `sub2api` 项目；应用数据挂载在 `/opt/sub2api/deploy/data`，数据库和 Redis 分别挂载在 `/opt/sub2api/postgres_data` 和 `/opt/sub2api/redis_data`。不要仅按某一个 Compose 项目的默认目录重建整套服务。

## 可选配置

通过调用时的环境变量覆盖默认值，不需要读取或修改生产 `.env`：

| 变量 | 默认值 |
| --- | --- |
| `DOCKER` / `CURL` | `docker` / `curl` |
| `APP_CONTAINER` | `sub2api` |
| `POSTGRES_CONTAINER` | `sub2api-postgres` |
| `REDIS_CONTAINER` | `sub2api-redis` |
| `LOCAL_HEALTH_URL` | `http://127.0.0.1:8081/health` |
| `PUBLIC_HEALTH_URL` | `https://77code.cc/health` |
| `HEALTH_TIMEOUT` | `10` 秒，每次 HTTP 请求的超时 |
| `START_WAIT_SECONDS` | `60` 秒，每个容器的健康等待时间 |

## 验证脚本

```sh
python3 /opt/sub2api/ops/test-ops.py
```

测试使用临时目录和模拟命令，不会操作真实 Docker 容器或访问公网。
