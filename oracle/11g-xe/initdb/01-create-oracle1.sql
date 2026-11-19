-- 预置业务用户初始化(幂等,每次启动都会执行,已存在则跳过)
--
-- 用户:  oracle1 (存储为大写 ORACLE1,登录时用小写即可)
-- 密码:  oracle1
-- 权限:  CONNECT + RESOURCE + DBA(增删改查、建表、建表空间等全权限)
-- Schema: 独立于 system/sys,业务表全部建在 ORACLE1 schema 下,互不干扰。
SET ECHO ON FEEDBACK ON

-- 开发环境:密码永不过期、登录失败不锁定
ALTER PROFILE DEFAULT LIMIT PASSWORD_LIFE_TIME UNLIMITED;
ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS UNLIMITED;

DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM dba_users WHERE username = 'ORACLE1';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE
      'CREATE USER ORACLE1 IDENTIFIED BY "oracle1" ' ||
      'DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP ' ||
      'QUOTA UNLIMITED ON USERS ACCOUNT UNLOCK';
    DBMS_OUTPUT.PUT_LINE('User ORACLE1 created.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('User ORACLE1 already exists, skipped.');
  END IF;
END;
/

GRANT CONNECT, RESOURCE, DBA TO ORACLE1;

EXIT
