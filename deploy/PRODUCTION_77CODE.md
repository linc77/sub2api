# 77code 生产部署

当前发布基于上游正式版 **v0.2.18**，恢复了 77code 的蓝色主题（`#339CFF`）和原来的品牌首页。后端业务代码与该正式版一致，上游标签对应提交 `ac1b8f1271be0d674fa6f074403c1410f30a3a81`。前端内嵌在重新构建的 Go 程序中，运行环境沿用固定摘要的官方镜像。

- 生产分支：`linc/77code-style-v0.2.18-20261027-082508`。
- 当前镜像：`sub2api-77code:0.2.18-49782d906fc6`，构建源码提交 `49782d906fc63df3d037e33b8d0cb4fe7781ee98`；该提交之后的生产配置提交记录镜像选择。
- 定制代码保留在 `my-changes` 和 `linc/custom-before-upstream-20261027-081020`；后者已经推送 GitHub。
- `main` 同步上游开发分支，生产分支以正式发布标签为基线。
- 聊天、图片工作台等定制功能仍保留在原定制分支，没有随主题上线。
- 纯官方版本及部署配置保留在 `linc/upstream-v0.2.18-20261027-081020`，可用于同版本应用回退。

## 服务及数据

公网由 Nginx 代理至 `127.0.0.1:8081`，应用容器内部监听 `8080`。前端内嵌在 Go 程序中。

| 服务 | 容器 | Compose 项目 | 数据目录 |
| --- | --- | --- | --- |
| 应用 | `sub2api` | `deploy` | `/opt/sub2api/deploy/data` |
| PostgreSQL | `sub2api-postgres` | `sub2api` | `/opt/sub2api/postgres_data` |
| Redis | `sub2api-redis` | `sub2api` | `/opt/sub2api/redis_data` |

应用显式连接已有的 `deploy_sub2api-network` 与 `sub2api_sub2api-network`，通过后者访问 `postgres` 和 `redis`。生产 Compose 文件仅管理应用，依赖服务保持原有容器及挂载。

## 构建与更新应用

服务器需要 Docker、Go 1.27.3 和可用的 Go 模块镜像。以下脚本使用 Node 24 容器及锁文件安装前端依赖，依赖缓存与生产数据分开保存。它限制编译并发，并对生成的 Ent 包关闭函数内联以降低编译内存占用，适应这台 2GB 服务器；首次 Go 编译会较慢。前端类型检查不与打包同时运行，修改代码后应另行执行相关检查。

```sh
bash deploy/build-77code-theme.sh
```

脚本输出的镜像标签包含构建源码提交，并写入构建目录下的 `image-tag.txt`。构建成功后，将 `compose.production.yml` 的 `image` 更新为该标签。这里使用本地构建镜像和 `pull_policy: never`，不会从仓库拉取同名标签。

从 `/opt/sub2api` 执行：

```sh
docker compose -p deploy -f deploy/compose.production.yml config --quiet
docker compose -p deploy -f deploy/compose.production.yml up -d --no-deps --pull never sub2api
curl --fail --silent --show-error http://127.0.0.1:8081/health
docker exec sub2api /app/sub2api -version
```

`.env.production.runtime` 保留升级前应用的环境配置，文件权限为 `0600`，不进入 Git。Compose 的 `format: raw` 用于原样保留凭据中的美元符号、引号等字符，需要 Docker Compose 2.30 或更新版本。该服务器已安装兼容版本。

后续升级先更新生产分支的上游基线及构建脚本中的版本、运行时镜像摘要，重新构建主题镜像，再执行迁移兼容检查、数据备份和应用切换。构建使用 `BuildType=source`，避免后台直接下载官方二进制覆盖内嵌的定制前端。主题更新仍会短暂重建应用容器，数据库与 Redis 不重启。

这次主题构建及切换记录保存在 `/opt/sub2api-builds/77code-theme-20261027-082508`。恢复纯官方 v0.2.18 时，可将生产 Compose 的镜像改回 `weishaw/sub2api:0.2.18@sha256:468a0b0e541e4becc05f1cf57826159235ea27a49a09f3dc2da6a43fcc05a22d` 后重建应用容器；主题切换没有额外的数据库结构变化。

## 本次备份与恢复

备份目录：`/opt/sub2api-backups/20261027-081020`，只允许服务器管理员读取。包括 PostgreSQL 自定义格式备份、角色、应用与 Redis 数据归档、原部署配置、容器元数据和文件校验和。

旧应用镜像保留为 `sub2api-rollback:20261027-081020`。应用旧版本为 `0.2.4`。

仅切回镜像不会撤销新版本已经执行的数据库迁移。需要数据库恢复时，应先停止应用写入，再使用上述数据库备份恢复并核对数据；不要在仍有写入时覆盖生产数据库。
