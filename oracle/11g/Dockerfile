# syntax=docker/dockerfile:1
# Oracle Database 11g EE 优化镜像(基于社区镜像二次构建)
#
# 在原镜像基础上新增:
#   1. 自定义 entrypoint:自动探测 ORACLE_HOME/SID,启动数据库并等待 OPEN,
#      输出 "Database ready to use. Enjoy ;)" 便于判断启动成功;
#   2. 预置业务用户 oracle1(密码 oracle1,拥有 DBA 全权限),与 system 分离,开箱即用。
#
# 构建(amd64 与 arm64 通用,arm64 通过 qemu/Rosetta 模拟运行 x86 二进制):
#   ./build.sh                      # 本机构建
#   PUSH=1 ./build.sh user/repo:tag # 双架构构建并推送到镜像仓库
#
# 注意:
#   - Oracle 11g 官方只发布 x86-64 二进制,arm64 镜像在模拟层下运行,仅供开发/测试。
#   - 镜像体积约 7.35GB(base 即如此),构建/推送请预留足够磁盘与时间。

FROM --platform=linux/amd64 yycx/oracle11:11.2.0.4

# EE 镜像的 ORACLE_HOME/SID 不做硬编码,由 entrypoint.sh 在运行时自动探测。

# 启动包装脚本:启动数据库 → 等待 OPEN → 执行初始化 → 打印 ready
COPY entrypoint.sh /usr/sbin/oracle-entrypoint.sh

# 数据库状态探测脚本(entrypoint 内部使用)
COPY check-db.sql /usr/local/share/oracle-init/check-db.sql

# 每次启动都会执行的初始化 SQL(幂等):
#   - 放开密码过期与登录锁定策略(开发环境)
#   - 创建业务用户 ORACLE1/oracle1 并授予 DBA
COPY initdb/ /docker-entrypoint-initdb.d/

RUN chmod +x /usr/sbin/oracle-entrypoint.sh \
    && chmod 644 /usr/local/share/oracle-init/check-db.sql /docker-entrypoint-initdb.d/*.sql

EXPOSE 1521

ENTRYPOINT ["/usr/sbin/oracle-entrypoint.sh"]
