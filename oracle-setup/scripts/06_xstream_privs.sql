-- Grant additional privileges to XStream admin in PDB
GRANT SELECT_CATALOG_ROLE TO c##xstrmadmin;
GRANT FLASHBACK ANY TABLE TO c##xstrmadmin;
GRANT SELECT ANY TABLE TO c##xstrmadmin;
GRANT LOCK ANY TABLE TO c##xstrmadmin;

-- Grant explicit SELECT on application tables
GRANT SELECT ON ordermgmt.CUSTOMERS TO c##xstrmadmin;
GRANT SELECT ON ordermgmt.ORDERS TO c##xstrmadmin;
GRANT SELECT ON ordermgmt.ORDER_ITEMS TO c##xstrmadmin;

-- Verify grants
SELECT GRANTEE, PRIVILEGE
FROM DBA_SYS_PRIVS
WHERE GRANTEE = 'C##XSTRMADMIN'
ORDER BY PRIVILEGE;

EXIT;
