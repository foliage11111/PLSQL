select name, log_mode from v$database;
-- Create model FoliageSsq
--
CREATE TABLE "FOLIAGE_SSQ" ("NUM" DOUBLE PRECISION NOT NULL PRIMARY KEY, "R1" DOUBLE PRECISION NULL, "R2" DOUBLE PRECISION NULL, "R3" DOUBLE PRECISION NULL, "R4" DOUBLE PRECISION NULL, "R5" DOUBLE PRECISION NULL, "R6" DOUBLE PRECISION NULL, "B1" DOUBLE PRECISION NULL, "SUM1" DOUBLE PRECISION NULL, "SUM2" DOUBLE PRECISION NULL);
--
-- Create model TSsqShishibiao
--
CREATE TABLE "T_SSQ_SHISHIBIAO" ("NUM" DOUBLE PRECISION NOT NULL PRIMARY KEY, "WAIJIAN" DOUBLE PRECISION NULL, "TAOSHU" DOUBLE PRECISION NULL, "R1" DOUBLE PRECISION NULL, "R2" DOUBLE PRECISION NULL, "R3" DOUBLE PRECISION NULL, "R4" DOUBLE PRECISION NULL, "R5" DOUBLE PRECISION NULL, "R6" DOUBLE PRECISION NULL, "B1" DOUBLE PRECISION NULL, "SUM1" DOUBLE PRECISION NULL, "SUM2" DOUBLE PRECISION NULL, "TIME" DATE NULL);



select *from T_SSQ_SHISHIBIAO tss ;

select * from FOLIAGE_SSQ fs

insert into T_SSQ_SHISHIBIAO (num,r1,r2,r3,r4,r5,r6,b1,sum1,sum2) values(2003001,1,2,3,4,5,6,16,21,37);
commit;

-- USER SQL
CREATE USER foliage IDENTIFIED BY yzrfoliage ;
alter user foliage identified by foliage;
CREATE USER foliage IDENTIFIED BY foliage ;
alter user ssq identified by foliage;

select * from USER_TABLES; --登录数据库的当前用户拥有的所有表 --ALL_TABLES  --DBA_TABLES 

select * from SYS.DBA_USERS du where  du.USERNAME='FOLIAGE'

  SELECT * FROM foliage_ssq;
SELECT * FROM T_SSQ_SHISHIBIAO  ;  ---ctrl + shift +r 格式优化
--------------------------------------------------------------------------------
---处理dblink

create public database link ssqlink connect to foliage IDENTIFIED by foliage using '  (DESCRIPTION =
    (ADDRESS_LIST =
      (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.1.106)(PORT = 1521))
    )
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = orcl)
    )
)'
---直接用tns的方法会差不出数据，真是操蛋
select owner, db_link from dba_db_links;
SELECT DISTINCT PRIVILEGE AS "Database Link Privileges"
        FROM ROLE_SYS_PRIVS
        WHERE PRIVILEGE IN ( 'CREATE SESSION','CREATE DATABASE LINK',
                             'CREATE PUBLIC DATABASE LINK'); 
                              

drop PUBLIC database link SSQLINK;
commit;
--------------------------------------------------------------------------------


---处理两个基础表
insert into foliage_ssq select *   from foliage_ssq@ssqlink
select count(*) from foliage_ssq

insert into T_SSQ_SHISHIBIAO (num,waijian,taoshu,r1,r2,r3,r4,r5,r6,b1,sum1,sum2,time) select num,waijian,taoshu,r1,r2,r3,r4,r5,r6,b1,sum1,sum2,to_date(time,'yyyymmdd') from T_SSQ_SHISHIBIAO@ssqlink



select * from T_SSQ_SHISHIBIAO

delete  from t_ssq_shishikawei
--------------------------------------------------------------------------------
---处理卡位表
create table t_ssq_shishikawei as select *from t_ssq_shishikawei@ssqlink

insert into t_ssq_shishikawei select *   from t_ssq_shishikawei@ssqlink

select count(*) from t_ssq_shishikawei
delete  from t_ssq_shishikawei
---
create table t_ssq_basickawei as select *from t_ssq_basickawei@ssqlink

select count(*) from t_ssq_basickawei-----基本表不全？只有100多万，这不对
delete  from t_ssq_basickawei

insert into t_ssq_basickawei select *   from t_ssq_basickawei@ssqlink

--------------------------------------------------------------------------------
--查看指定概要文件(如default)的密码有效期设置：
SELECT * FROM dba_profiles s WHERE s.profile='DEFAULT' AND resource_name='PASSWORD_LIFE_TIME';

-- 将密码有效期由默认的180天修改成“无限制”：
ALTER PROFILE DEFAULT LIMIT PASSWORD_LIFE_TIME UNLIMITED;

-- QUOTAS

-- ROLES
GRANT "RESOURCE" TO foliage;
GRANT "CONNECT" TO foliage ;

-- SYSTEM PRIVILEGES
grant create public database link,create database link to foliage;
GRANT ALTER TABLESPACE TO foliage ;
GRANT DROP ANY TRIGGER TO foliage ;
GRANT CREATE USER TO foliage ;
GRANT CREATE ANY OUTLINE TO foliage ;
GRANT FLASHBACK ANY TABLE TO foliage ;
GRANT ALTER ANY SEQUENCE TO foliage ;
GRANT ALTER ANY LIBRARY TO foliage ;
GRANT ADMINISTER SQL MANAGEMENT OBJECT TO foliage ;
GRANT CREATE MINING MODEL TO foliage ;
GRANT UPDATE ANY TABLE TO foliage ;
GRANT UPDATE ANY CUBE TO foliage ;
GRANT CREATE TRIGGER TO foliage ;
GRANT DROP ANY EVALUATION CONTEXT TO foliage ;
GRANT DROP PROFILE TO foliage ;
GRANT CREATE TABLESPACE TO foliage ;
GRANT DEBUG CONNECT SESSION TO foliage ;
GRANT DROP ANY DIRECTORY TO foliage ;
GRANT CREATE ASSEMBLY TO foliage ;
GRANT SELECT ANY CUBE TO foliage ;
GRANT CREATE SEQUENCE TO foliage ;
GRANT ON COMMIT REFRESH TO foliage ;
GRANT SELECT ANY SEQUENCE TO foliage ;
GRANT CREATE ANY SQL PROFILE TO foliage ;
GRANT DROP ANY SQL PROFILE TO foliage ;
GRANT ADMINISTER ANY SQL TUNING SET TO foliage ;
GRANT ADVISOR TO foliage ;
GRANT ALTER ANY MINING MODEL TO foliage ;
GRANT EXECUTE ANY OPERATOR TO foliage ;
GRANT ALTER PROFILE TO foliage ;
GRANT EXECUTE ANY TYPE TO foliage ;
GRANT CREATE ANY DIRECTORY TO foliage ;
GRANT CREATE TABLE TO foliage ;
GRANT CREATE ANY INDEX TO foliage ;
--GRANT ADMINISTER RESOURCE MANAGER TO foliage ;
GRANT BECOME USER TO foliage ;
GRANT MANAGE TABLESPACE TO foliage ;
GRANT DROP ANY MINING MODEL TO foliage ;
GRANT EXECUTE ASSEMBLY TO foliage ;
GRANT SELECT ANY TABLE TO foliage ;
GRANT DROP ROLLBACK SEGMENT TO foliage ;
GRANT CREATE OPERATOR TO foliage ;
GRANT ALTER ANY CUBE TO foliage ;
GRANT ALTER PUBLIC DATABASE LINK TO foliage ;
GRANT CREATE ANY PROCEDURE TO foliage ;
GRANT CREATE ANY CUBE TO foliage ;
GRANT DROP ANY INDEXTYPE TO foliage ;
GRANT SELECT ANY MINING MODEL TO foliage ;
GRANT EXECUTE ANY CLASS TO foliage ;
GRANT CREATE ANY MATERIALIZED VIEW TO foliage ;
GRANT SELECT ANY TRANSACTION TO foliage ;
GRANT ANALYZE ANY DICTIONARY TO foliage ;
GRANT CREATE EXTERNAL JOB TO foliage ;
GRANT INSERT ANY TABLE TO foliage ;
GRANT CREATE LIBRARY TO foliage ;
GRANT GRANT ANY OBJECT PRIVILEGE TO foliage ;
GRANT CREATE JOB TO foliage ;
GRANT CREATE ANY OPERATOR TO foliage ;
GRANT ALTER ANY RULE TO foliage ;
GRANT CREATE ANY LIBRARY TO foliage ;
GRANT CREATE ANY SEQUENCE TO foliage ;
GRANT DROP PUBLIC SYNONYM TO foliage ;
GRANT CREATE CLUSTER TO foliage ;
GRANT FORCE ANY TRANSACTION TO foliage ;
GRANT UPDATE ANY CUBE DIMENSION TO foliage ;
GRANT CREATE EVALUATION CONTEXT TO foliage ;
GRANT CREATE ANY CUBE BUILD PROCESS TO foliage ;
GRANT DROP ANY OPERATOR TO foliage ;
GRANT DROP USER TO foliage ;
GRANT EXECUTE ANY INDEXTYPE TO foliage ;
GRANT ALTER ANY EDITION TO foliage ;
GRANT LOCK ANY TABLE TO foliage ;
GRANT DROP ANY TYPE TO foliage ;
GRANT CHANGE NOTIFICATION TO foliage ;
GRANT CREATE ANY DIMENSION TO foliage ;
GRANT DROP ANY DIMENSION TO foliage ;
GRANT READ ANY FILE GROUP TO foliage ;
GRANT CREATE ANY RULE TO foliage ;
GRANT ALTER ANY ASSEMBLY TO foliage ;
GRANT EXEMPT IDENTITY POLICY TO foliage ;
GRANT ALTER ROLLBACK SEGMENT TO foliage ;
GRANT CREATE RULE TO foliage ;
GRANT CREATE ANY VIEW TO foliage ;
GRANT SYSOPER TO foliage ;
GRANT CREATE PROCEDURE TO foliage ;
GRANT INSERT ANY MEASURE FOLDER TO foliage ;
GRANT SYSDBA TO foliage ;
GRANT ANALYZE ANY TO foliage ;
GRANT ALTER ANY TYPE TO foliage ;
GRANT DROP ANY EDITION TO foliage ;
GRANT CREATE ANY TRIGGER TO foliage ;
GRANT MANAGE ANY FILE GROUP TO foliage ;
GRANT DROP ANY RULE TO foliage ;
GRANT CREATE DIMENSION TO foliage ;
GRANT CREATE ROLLBACK SEGMENT TO foliage ;
GRANT FLASHBACK ARCHIVE ADMINISTER TO foliage ;
GRANT ALTER ANY RULE SET TO foliage ;
GRANT DROP ANY SEQUENCE TO foliage ;
GRANT DROP ANY TABLE TO foliage ;
GRANT CREATE CUBE DIMENSION TO foliage ;
GRANT EXECUTE ANY RULE TO foliage ;
GRANT DROP ANY LIBRARY TO foliage ;
GRANT EXECUTE ANY PROCEDURE TO foliage ;
GRANT DROP ANY VIEW TO foliage ;
GRANT DROP ANY CONTEXT TO foliage ;
GRANT FORCE TRANSACTION TO foliage ;
GRANT CREATE ANY JOB TO foliage ;
GRANT DROP ANY ROLE TO foliage ;
GRANT DELETE ANY CUBE DIMENSION TO foliage ;
GRANT DROP ANY CLUSTER TO foliage ;
GRANT UPDATE ANY CUBE BUILD PROCESS TO foliage ;
GRANT CREATE ANY INDEXTYPE TO foliage ;
GRANT ADMINISTER SQL TUNING SET TO foliage ;
GRANT EXECUTE ANY PROGRAM TO foliage ;
GRANT DROP ANY ASSEMBLY TO foliage ;
GRANT ALTER DATABASE LINK TO foliage ;
GRANT GRANT ANY PRIVILEGE TO foliage ;
GRANT ALTER ANY PROCEDURE TO foliage ;
GRANT MERGE ANY VIEW TO foliage ;
GRANT CREATE ANY EVALUATION CONTEXT TO foliage ;
GRANT ALTER ANY OPERATOR TO foliage ;
GRANT ALTER ANY CUBE DIMENSION TO foliage ;
GRANT COMMENT ANY MINING MODEL TO foliage ;
GRANT ALTER ANY ROLE TO foliage ;
GRANT EXECUTE ANY ASSEMBLY TO foliage ;
GRANT CREATE CUBE BUILD PROCESS TO foliage ;
GRANT EXECUTE ANY RULE SET TO foliage ;
GRANT ALTER ANY TRIGGER TO foliage ;
GRANT UNDER ANY TABLE TO foliage ;
GRANT BACKUP ANY TABLE TO foliage ;
GRANT CREATE SYNONYM TO foliage ;
GRANT DROP ANY CUBE BUILD PROCESS TO foliage ;
GRANT DROP ANY CUBE TO foliage ;
GRANT ALTER DATABASE TO foliage ;
GRANT ALTER ANY TABLE TO foliage ;
GRANT CREATE VIEW TO foliage ;
GRANT EXECUTE ANY LIBRARY TO foliage ;
GRANT CREATE RULE SET TO foliage ;
GRANT EXEMPT ACCESS POLICY TO foliage ;
GRANT CREATE ANY CLUSTER TO foliage ;
GRANT DROP ANY INDEX TO foliage ;
GRANT CREATE TYPE TO foliage ;
GRANT EXECUTE ANY EVALUATION CONTEXT TO foliage ;
GRANT ALTER RESOURCE COST TO foliage ;
GRANT ALTER ANY CLUSTER TO foliage ;
GRANT ALTER ANY INDEX TO foliage ;
GRANT CREATE PUBLIC SYNONYM TO foliage ;
GRANT CREATE ANY MINING MODEL TO foliage ;
GRANT GLOBAL QUERY REWRITE TO foliage ;
GRANT CREATE ANY RULE SET TO foliage ;
GRANT CREATE MEASURE FOLDER TO foliage ;
GRANT DROP ANY CUBE DIMENSION TO foliage ;
GRANT CREATE ROLE TO foliage ;
GRANT RESTRICTED SESSION TO foliage ;
GRANT DROP ANY PROCEDURE TO foliage ;
GRANT ALTER USER TO foliage ;
GRANT CREATE ANY CONTEXT TO foliage ;
GRANT CREATE ANY SYNONYM TO foliage ;
GRANT CREATE ANY CUBE DIMENSION TO foliage ;
GRANT ALTER ANY OUTLINE TO foliage ;
GRANT ENQUEUE ANY QUEUE TO foliage ;
GRANT CREATE ANY TABLE TO foliage ;
GRANT SELECT ANY CUBE DIMENSION TO foliage ;
GRANT ALTER ANY EVALUATION CONTEXT TO foliage ;
GRANT CREATE SESSION TO foliage ;
GRANT DEQUEUE ANY QUEUE TO foliage ;
GRANT QUERY REWRITE TO foliage ;
GRANT EXPORT FULL DATABASE TO foliage ;
GRANT CREATE PUBLIC DATABASE LINK TO foliage ;
GRANT RESUMABLE TO foliage ;
GRANT UNLIMITED TABLESPACE TO foliage ;
GRANT UNDER ANY VIEW TO foliage ;
GRANT DROP ANY OUTLINE TO foliage ;
GRANT CREATE ANY EDITION TO foliage ;
GRANT CREATE ANY ASSEMBLY TO foliage ;
GRANT ALTER ANY INDEXTYPE TO foliage ;
GRANT DROP ANY MATERIALIZED VIEW TO foliage ;
GRANT CREATE INDEXTYPE TO foliage ;
GRANT ALTER ANY SQL PROFILE TO foliage ;
GRANT ALTER SYSTEM TO foliage ;
GRANT DROP ANY SYNONYM TO foliage ;
GRANT GRANT ANY ROLE TO foliage ;
GRANT CREATE MATERIALIZED VIEW TO foliage ;
GRANT DROP ANY RULE SET TO foliage ;
GRANT MANAGE SCHEDULER TO foliage ;
GRANT DROP TABLESPACE TO foliage ;
GRANT SELECT ANY DICTIONARY TO foliage ;
GRANT IMPORT FULL DATABASE TO foliage ;
GRANT DELETE ANY MEASURE FOLDER TO foliage ;
GRANT DELETE ANY TABLE TO foliage ;
GRANT AUDIT SYSTEM TO foliage ;
GRANT ALTER ANY MATERIALIZED VIEW TO foliage ;
GRANT DEBUG ANY PROCEDURE TO foliage ;
GRANT CREATE PROFILE TO foliage ;
GRANT CREATE ANY MEASURE FOLDER TO foliage ;
GRANT UNDER ANY TYPE TO foliage ;
GRANT COMMENT ANY TABLE TO foliage ;
GRANT ALTER ANY DIMENSION TO foliage ;
GRANT CREATE ANY TYPE TO foliage ;
GRANT DROP ANY MEASURE FOLDER TO foliage ;
GRANT DROP PUBLIC DATABASE LINK TO foliage ;
GRANT CREATE CUBE TO foliage ;
GRANT CREATE DATABASE LINK TO foliage ;
GRANT INSERT ANY CUBE DIMENSION TO foliage ;
GRANT ALTER SESSION TO foliage ;
GRANT MANAGE ANY QUEUE TO foliage ;
GRANT ADMINISTER DATABASE TRIGGER TO foliage ;
GRANT AUDIT ANY TO foliage ;
GRANT MANAGE FILE GROUP TO foliage ;

