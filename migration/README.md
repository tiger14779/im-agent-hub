# IM Agent Hub 多站合并迁移

把分散在 10~13 台旧服务器的 IM 站点，合并到 1 台新服务器（搬瓦工 JPOS_1 CN2 GIA-E 6C8G）。

## 架构

```
新服务器 (单台)
  Nginx :80/:443
   ├─ site01.com  → 127.0.0.1:8081 ── im-hub@01 ── imhub_01 (PG)
   ├─ site02.com  → 127.0.0.1:8082 ── im-hub@02 ── imhub_02 (PG)
   └─ ...                                                       
  PostgreSQL 16 (共享 1 实例，13 个独立 database)
  /opt/im-hub/sites/{01..13}/  (各自的 config.yaml + uploads/)
```

- 每站独立进程、独立数据库、独立 uploads
- 每站独立 JWT（用户登录态隔离）
- **voice_relay.secret 必须 13 站完全相同**（音频中转 HMAC 鉴权）
- 各站自己中转语音（relay_ws_url 留空）

## 文件清单

| 脚本 | 在哪里跑 | 跑几次 | 干什么 |
|---|---|---|---|
| `1-audit-old.sh` | 旧服务器（每台） | 每台 1 次 | 输出 manifest + secret，确认 13 台 voice_relay.secret 一致 |
| `2-setup-new.sh` | 新服务器 | 1 次 | 装 Go/PG/Nginx，编译二进制，配 systemd 模板 |
| `3-init-site.sh` | 新服务器 | 每站 1 次 | 建 PG database + config.yaml + nginx + SSL + 启动 |
| `4-export-old.sh` | 旧服务器（每台） | 每台 1 次 | dump DB + tar uploads + sha256 + manifest |
| `5-restore-new.sh` | 新服务器 | 每站 1 次 | 校验 manifest + 还原 DB + uploads + 启动验证 |
| `6-verify.sh` | 新服务器 | 1 次 | 全站轮询，确认域名→端口→DB 映射没错 |
| `sites.csv` | 你本地编辑 | — | **唯一真相源**，所有脚本都从这里读 site 配置 |

## 完整流程（按时间顺序）

### 阶段 A：准备 (不停业务，可提前 1 天做)

```bash
# 1. 在每台旧服务器跑审计 (产出 /tmp/im-hub-audit/site_XX.manifest 和 .secrets)
ssh old-server-01 'bash -s' < 1-audit-old.sh
ssh old-server-02 'bash -s' < 1-audit-old.sh
# ... 13 台

# 2. 把 manifest 和 secrets 都拉回本地核对
mkdir -p audit/
scp old-server-01:/tmp/im-hub-audit/* audit/
# ...

# 3. 关键：人工核对所有 *.manifest 里的 voice_relay_secret_sha256
#    必须 13 台完全相同！如果不同，跨站语音中转会废掉
grep voice_relay_secret_sha256 audit/*.manifest

# 4. 编辑 sites.csv (一行一个站)
cp sites.csv.example sites.csv
nano sites.csv

# 5. 新服务器初始化 (一次性)
scp 2-setup-new.sh new-server:/root/
ssh new-server 'bash /root/2-setup-new.sh'

# 6. 把 sites.csv + 所有 secrets 上传到新服务器
scp sites.csv new-server:/opt/im-hub/
scp audit/*.secrets new-server:/opt/im-hub/secrets/

# 7. 为每个 site 初始化基础设施 (建库 + 配置 + nginx + SSL)
ssh new-server
cd /opt/im-hub
for SITE in 01 02 03 ... 13; do
  bash 3-init-site.sh $SITE
done
# 注意：此时各站还是空数据，没流量
```

### 阶段 B：迁移数据 (每站 5~20 分钟，可并行)

```bash
# 对每个 site (例如 site03) 顺序执行:

# 1. [旧服务器 03] 导出数据 (此时旧服务器还在跑，业务无感)
ssh old-server-03 'bash -s' < 4-export-old.sh

# 2. [本地→新服务器] rsync 传输
ssh old-server-03 'tar cf - /tmp/im-hub-export/' \
  | ssh new-server 'tar xf - -C /tmp/'

# 3. [新服务器] 还原 (★ 这步会停 site03 几分钟)
ssh new-server 'bash /opt/im-hub/5-restore-new.sh --site-id 03 --source-domain site03.com'

# 4. [旧服务器 03] 停服务 (★ 真正的业务停机点)
ssh old-server-03 'systemctl stop im-agent-hub'

# 5. [DNS] 把 site03.com A 记录指向新服务器 IP
#    建议提前 24 小时把 TTL 改成 60s

# 6. 等 5~10 分钟 DNS 生效，curl 验证
curl https://site03.com/api/whoami   # 看是否解析到新 IP

# 7. 旧服务器保留 14 天 (★ 绝对不要关机/删盘)
```

### 阶段 C：全站验证

```bash
ssh new-server 'bash /opt/im-hub/6-verify.sh'
# 输出每个站的 端口/HTTP 状态/PID/DB 行数/uploads 大小
```

## 防呆机制（核心安全设计）

| 风险 | 防御 |
|---|---|
| dump 文件张冠李戴（A 数据导进 B 库）| `5-restore-new.sh` 必传 `--site-id` 和 `--source-domain`，从 manifest 校验匹配，不匹配拒绝执行 |
| 覆盖了已有数据 | restore 前检查目标 DB 行数=0，非空必须 `--force-overwrite` 才能继续 |
| dump 不完整 | export 后立刻 `pg_restore --list` 自检 + 算 sha256 |
| uploads 没传全 | tar 后算 sha256，新服务器校验 |
| voice_relay.secret 不一致 | audit 输出 secret 的 sha256，肉眼比对 13 台是否相同 |
| 域名绑到错的站 | verify 脚本对每个域名走完整链路，输出端口/DB/进程 |

## 失败回滚

任何一站迁移失败，回滚步骤：

1. DNS A 记录改回旧服务器 IP
2. 新服务器执行 `systemctl stop im-hub@XX`
3. 新服务器执行 `sudo -u postgres dropdb imhub_XX && sudo -u postgres createdb imhub_XX -O imhub_XX`
4. 重新跑 `4-export-old.sh` + `5-restore-new.sh`

**前提：旧服务器在 14 天观察期内绝对不要动**。这是兜底保险。

## 资源管理

新服务器装好后会自动配置：

- `journald` 限制为 2GB（防 13 个服务日志爆盘）
- PG `shared_buffers` 1GB（8GB 机器的合理值）
- PG `autovacuum` 开启
- 每日凌晨 4 点自动 `pg_dump` 所有 13 个库到 `/opt/im-hub/backups/`（保留 7 天）

## 已知问题

1. **uploads 不会自动清理**：当前代码 `CleanupOldMessages` 只清 DB 消息，不清磁盘上的图片文件。如果你的业务图片量大，磁盘会持续增长。建议：
   - 短期：cron 加一行 `find /opt/im-hub/sites/*/data/uploads -mtime +30 -delete`
   - 长期：修代码让 cleanup 真的清 uploads

2. **JWT 必须沿用旧服务器的**：不然迁移完所有用户重新登录。audit 脚本会自动保存旧的 jwt_secret，init-site 时自动写入。
