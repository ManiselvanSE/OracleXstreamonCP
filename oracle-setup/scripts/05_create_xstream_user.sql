-- Create XStream admin common user
ALTER SESSION SET CONTAINER = CDB$ROOT;

CREATE USER c##xstrmadmin IDENTIFIED BY xstrmadmin123
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users
  CONTAINER=ALL;

-- Grant basic privileges
GRANT CREATE SESSION, SET CONTAINER TO c##xstrmadmin CONTAINER=ALL;
GRANT DBA TO c##xstrmadmin CONTAINER=ALL;

-- Grant XStream CAPTURE privilege
BEGIN
   DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
      grantee                 => 'c##xstrmadmin',
      privilege_type          => 'CAPTURE',
      grant_select_privileges => TRUE,
      container               => 'ALL'
   );
END;
/

-- Verify user creation
SELECT USERNAME, COMMON, ORACLE_MAINTAINED
FROM DBA_USERS
WHERE USERNAME = 'C##XSTRMADMIN';

EXIT;
