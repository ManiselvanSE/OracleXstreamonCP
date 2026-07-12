#!/bin/bash

echo "========================================"
echo "Oracle CDC Setup - Starting"
echo "========================================"

export ORACLE_SID=XE

echo "Step 1: Enable archive log and supplemental logging..."
sqlplus /nolog @/opt/oracle/scripts/setup/01_setup_database.sql

echo "Step 2: Create application user (ordermgmt)..."
sqlplus sys/confluent123@XEPDB1 as sysdba @/opt/oracle/scripts/setup/02_create_user.sql

echo "Step 3: Create schema and data model..."
sqlplus ordermgmt/kafka@XEPDB1 @/opt/oracle/scripts/setup/03_create_schema_datamodel.sql

echo "Step 4: Load sample data..."
sqlplus ordermgmt/kafka@XEPDB1 @/opt/oracle/scripts/setup/04_load_data.sql

echo "Step 5: Create XStream CDC user (c##xstrmadmin)..."
sqlplus sys/confluent123@XE as sysdba @/opt/oracle/scripts/setup/05_create_xstream_user.sql

echo "Step 6: Grant XStream privileges in PDB..."
sqlplus sys/confluent123@XEPDB1 as sysdba @/opt/oracle/scripts/setup/06_xstream_privs.sql

echo "Step 7: Create XStream outbound server..."
sqlplus sys/confluent123@XE as sysdba @/opt/oracle/scripts/setup/07_create_xstream_outbound.sql

echo "========================================"
echo "Oracle CDC Setup - Completed Successfully"
echo "========================================"
