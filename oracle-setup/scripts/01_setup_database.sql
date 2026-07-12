-- Connect as SYSDBA
CONNECT sys/confluent123 AS SYSDBA

-- Enable GoldenGate replication (required for XStream)
ALTER SYSTEM SET enable_goldengate_replication=TRUE SCOPE=BOTH;

-- Show current redo logs
SET LINES 200
COLUMN MEMBER FORMAT A50
COLUMN MEMBERS FORMAT 999
SELECT a.group#, b.member, a.members, a.bytes/1024/1024 AS MB, a.status
FROM v$log a, v$logfile b
WHERE a.group# = b.group#;

-- Add larger redo log groups (2GB each for better CDC performance)
ALTER DATABASE ADD LOGFILE GROUP 4 '/opt/oracle/oradata/XE/redo04.log' SIZE 2G;
ALTER DATABASE ADD LOGFILE GROUP 5 '/opt/oracle/oradata/XE/redo05.log' SIZE 2G;
ALTER DATABASE ADD LOGFILE GROUP 6 '/opt/oracle/oradata/XE/redo06.log' SIZE 2G;

-- Switch to new log groups
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE;

-- Archive old log groups
ALTER SYSTEM ARCHIVE LOG GROUP 1;
ALTER SYSTEM ARCHIVE LOG GROUP 2;
ALTER SYSTEM ARCHIVE LOG GROUP 3;

-- Wait for archiving to complete
EXECUTE sys.dbms_lock.sleep(60);

-- Drop old smaller log groups
ALTER DATABASE DROP LOGFILE GROUP 1;
ALTER DATABASE DROP LOGFILE GROUP 2;
ALTER DATABASE DROP LOGFILE GROUP 3;

-- Verify new redo logs
SET LINES 200
COLUMN MEMBER FORMAT A50
COLUMN MEMBERS FORMAT 999
SELECT a.group#, b.member, a.members, a.bytes/1024/1024 AS MB, a.status
FROM v$log a, v$logfile b
WHERE a.group# = b.group#;

-- Enable ARCHIVELOG mode
SHUTDOWN IMMEDIATE
STARTUP MOUNT
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;

-- Enable supplemental logging at CDB level
ALTER SESSION SET CONTAINER=cdb$root;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- Enable supplemental logging at PDB level
ALTER SESSION SET CONTAINER=XEPDB1;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- Make logging asynchronous for better performance
ALTER SYSTEM SET commit_logging = 'BATCH' CONTAINER=ALL;
ALTER SYSTEM SET commit_wait = 'NOWAIT' CONTAINER=ALL;

-- Verify settings
SELECT LOG_MODE FROM V$DATABASE;
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_ALL FROM V$DATABASE;

EXIT;
