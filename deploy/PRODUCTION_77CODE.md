# 77code 生产部署

当前发布使用上游正式版 **v0.2.18** 的官方镜像，源码标签对应提交 `ac1b8f1271be0d674fa6f074403c1410f30a3a81`。Compose 文件固定了镜像摘要，发布不依赖可变的 `latest` 标签。

- 生产分支：`linc/upstream-v0.2.18-20261027-081020`。
- 定制代码保留在 `my-changes` 和 `linc/custom-before-upstream-20261027-081020`；后者已经推送 GitHub。
- `main` 同步上游开发分支，生产分支以正式发布标签为基线。
- 当前生产分支只增加部署配置和数据排除规则，不合入聊天、图片工作台等定制功能。

## 服务及数据

公网由 Nginx 代理至 `127.0.0.1:8081`，应用容器内部监听 `8080`。前端内嵌在 Go 程序中。

| 服务 | 容器 | Compose 项目 | 数据目录 |
| --- | --- | --- | --- |
| 应用 | `sub2api` | `deploy` | `/opt/sub2api/deploy/data` |
| PostgreSQL | `sub2api-postgres` | `sub2api` | `/opt/sub2api/postgres_data` |
| Redis | `sub2api-redis` | `sub2api` | `/opt/sub2api/redis_data` |

应用显式连接已有的 `deploy_sub2api-network` 与 `sub2api_sub2api-network`，通过后者访问 `postgres` 和 `redis`。生产 Compose 文件仅管理应用，依赖服务保持原有容器及挂载。

## 更新应用

从 `/opt/sub2api` 执行：

```sh
docker compose -p deploy -f deploy/compose.production.yml config --quiet
docker compose -p deploy -f deploy/compose.production.yml up -d --no-deps sub2api
curl --fail --silent --show-error http://127.0.0.1:8081/health
docker exec sub2api /app/sub2api -version
```

`.env.production.runtime` 保留升级前应用的环境配置，文件权限为 `0600`，不进入 Git。Compose 的 `format: raw` 用于原样保留凭据中的美元符号、引号等字符，需要 Docker Compose 2.30 或更新版本。该服务器已安装兼容版本。

后续升级先更新生产分支的上游基线及镜像版本、摘要，再执行迁移兼容检查、数据备份和应用切换。这里不使用后台的“立即更新”替换容器内二进制，以保持程序与镜像一致。

## 本次备份与恢复

备份目录：`/opt/sub2api-backups/20261027-081020`，只允许服务器管理员读取。包括 PostgreSQL 自定义格式备份、角色、应用与 Redis 数据归档、原部署配置、容器元数据和文件校验和。

旧应用镜像保留为 `sub2api-rollback:20261027-081020`。应用旧版本为 `0.2.4`。

仅切回镜像不会撤销新版本已经执行的数据库迁移。需要数据库恢复时，应先停止应用写入，再使用上述数据库备份恢复并核对数据；不要在仍有写入时覆盖生产数据库。
