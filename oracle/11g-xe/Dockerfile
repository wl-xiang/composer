# syntax=docker/dockerfile:1
# Oracle Database 11g XE 优化镜像(基于社区镜像二次构建)
#
# 在原镜像基础上新增:
#   1. 修复 sqlplus/expdp 等客户端工具不在 PATH 的问题(docker exec 可直接使用);
#   2. 自定义 entrypoint:等待数据库 OPEN 后执行初始化脚本,并输出
#      "Database ready to use. Enjoy ;)" 便于判断启动成功;
#   3. 预置业务用户 oracle1(密码 oracle1,拥有 DBA 全权限),与 system 分离,开箱即用。
#
# 构建(amd64 与 arm64 通用,arm64 通过 qemu/Rosetta 模拟运行 x86 二进制):
#   ./build.sh                      # 本机构建
#   PUSH=1 ./build.sh user/repo:tag # 双架构构建并推送到镜像仓库
#
# 注意:Oracle 11g 官方只发布 x86-64 二进制,arm64 镜像是在模拟层下运行,仅供开发/测试。

FROM --platform=linux/amd64 oracleinanutshell/oracle-xe-11g:latest

ENV ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe \
    ORACLE_SID=XE \
    LD_LIBRARY_PATH=/u01/app/oracle/product/11.2.0/xe/lib \
    PATH=/u01/app/oracle/product/11.2.0/xe/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 启动包装脚本:启动数据库 → 等待 OPEN → 执行初始化 → 打印 ready
COPY entrypoint.sh /usr/sbin/oracle-entrypoint.sh

# 数据库状态探测脚本(entrypoint 内部使用)
COPY check-db.sql /usr/local/share/oracle-init/check-db.sql

# 首次启动/每次启动都会执行的初始化 SQL(幂等):
#   - 放开密码过期与登录锁定策略(开发环境)
#   - 创建业务用户 ORACLE1/oracle1 并授予 DBA
COPY initdb/ /docker-entrypoint-initdb.d/

RUN chmod +x /usr/sbin/oracle-entrypoint.sh \
    && chmod 644 /usr/local/share/oracle-init/check-db.sql /docker-entrypoint-initdb.d/*.sql

EXPOSE 1521 8080

ENTRYPOINT ["/usr/sbin/oracle-entrypoint.sh"]
