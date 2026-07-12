-- Create XStream outbound server
ALTER SESSION SET CONTAINER = CDB$ROOT;

-- Create outbound server
BEGIN
  DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
    server_name => 'xout',
    table_names => NULL,
    source_database => 'XEPDB1'
  );
END;
/

-- Configure connect user
BEGIN
  DBMS_XSTREAM_ADM.ALTER_OUTBOUND(
    server_name => 'xout',
    connect_user => 'c##xstrmadmin'
  );
END;
/

-- Add schema rules for ORDERMGMT schema (CRITICAL for CDC to work)
DECLARE
  v_capture_name VARCHAR2(30);
  v_queue_name VARCHAR2(61);
BEGIN
  -- Get capture and queue names
  SELECT CAPTURE_NAME, QUEUE_NAME
  INTO v_capture_name, v_queue_name
  FROM DBA_XSTREAM_OUTBOUND
  WHERE SERVER_NAME = 'XOUT';

  -- Add schema rules
  DBMS_STREAMS_ADM.ADD_SCHEMA_RULES(
    schema_name     => 'ORDERMGMT',
    streams_type    => 'capture',
    streams_name    => v_capture_name,
    queue_name      => v_queue_name,
    include_dml     => TRUE,
    include_ddl     => FALSE,
    include_tagged_lcr => FALSE,
    source_database => 'XEPDB1'
  );
END;
/

-- Start the capture process
BEGIN
  DBMS_CAPTURE_ADM.START_CAPTURE(
    capture_name => (SELECT CAPTURE_NAME FROM DBA_XSTREAM_OUTBOUND WHERE SERVER_NAME = 'XOUT')
  );
END;
/

-- Verify XStream outbound server
SET LINESIZE 200
COLUMN SERVER_NAME FORMAT A15
COLUMN CAPTURE_NAME FORMAT A20
COLUMN QUEUE_NAME FORMAT A20
COLUMN CONNECT_USER FORMAT A15
COLUMN SOURCE_DATABASE FORMAT A15

SELECT SERVER_NAME, CAPTURE_NAME, QUEUE_NAME, CONNECT_USER, SOURCE_DATABASE
FROM DBA_XSTREAM_OUTBOUND
WHERE SERVER_NAME = 'XOUT';

-- Verify capture process
COLUMN CAPTURE_NAME FORMAT A20
COLUMN STATUS FORMAT A10
COLUMN STATE FORMAT A25

SELECT CAPTURE_NAME, STATUS, STATE
FROM DBA_CAPTURE
WHERE CAPTURE_NAME = (SELECT CAPTURE_NAME FROM DBA_XSTREAM_OUTBOUND WHERE SERVER_NAME = 'XOUT');

-- Verify schema rules
SELECT SCHEMA_NAME, STREAMS_NAME, STREAMS_TYPE, RULE_TYPE
FROM DBA_STREAMS_SCHEMA_RULES
WHERE SCHEMA_NAME = 'ORDERMGMT';

EXIT;
