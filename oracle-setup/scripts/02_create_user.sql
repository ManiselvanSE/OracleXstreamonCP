-- Create application user in PDB
CREATE USER ordermgmt IDENTIFIED BY kafka
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users;

-- Grant necessary privileges
GRANT CREATE SESSION TO ordermgmt;
GRANT CREATE TABLE TO ordermgmt;
GRANT CREATE SEQUENCE TO ordermgmt;
GRANT CREATE VIEW TO ordermgmt;
GRANT CREATE PROCEDURE TO ordermgmt;
GRANT CREATE TRIGGER TO ordermgmt;
GRANT UNLIMITED TABLESPACE TO ordermgmt;

EXIT;
