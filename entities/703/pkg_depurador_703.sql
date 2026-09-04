CREATE OR REPLACE PACKAGE BODY SOPORTEDBA.PKG_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_703 AS 

PROCEDURE PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1(acc_ejec IN VARCHAR2)
-- PARAMETROS DE ENTRADA:
--  acc_ejec: Se indica la acción a ejecutar: 'COPY' Solo copia de datos al historico, 'DELETE' Solo borrado en PROD ó 'ALL' Copia de datos al historico y borrado en PROD
--
--  STORED PROCEDURE QUE TOMA LA FECHA QUE SE LE INDICA PARA HACER LA COPIA / DEPURACION
--
--  EJEMPLO para la ejecución: CALL SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1('COPY') --> Solo copia los datos de la entidad ENTIDAD703 a ENTIDAD701 de las tablas que conforman el proceso PRC_WFGADQ_ENTITY_DATA_CLEANING_1
--                             CALL SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1('DELETE') --> Solo borra los datos de la entidad ENTIDAD703 de las tablas que conforman el proceso PRC_WFGADQ_ENTITY_DATA_CLEANING_1
--                             CALL SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1('ALL') --> Copia los datos de la entidad ENTIDAD703 a ENTIDAD701 y luego los borra de ENTIDAD703 de las tablas que conforman el proceso PRC_WFGADQ_ENTITY_DATA_CLEANING_1
--  NOTA: OJO cuando se actualice el código, estar atentos a realizar bien los cambios dentro de los ciclos IF dependiendo de la acción ('COPY','DELETE',ó 'ALL') que se requiera modificar.
IS
BEGIN

        EXECUTE IMMEDIATE 'alter session set current_schema = SOPORTEDBA';
        EXECUTE IMMEDIATE 'alter session set nls_Date_format=''DD/MM/YYYY''';
        EXECUTE IMMEDIATE 'alter session set nls_timestamp_format=''DD/MM/YYYY''';
        
    DECLARE
        v_code   	    NUMBER;                                             -- CODIGO DE ERROR
        v_errm   	    VARCHAR2 (300);                                     -- MENSAJE DE ERROR
        v_time1         TIMESTAMP;                                          -- TIEMPO DE EJECUCION 1 INICIAL DEL PROCESO DE DEPURACION
        v_time2         TIMESTAMP;                                          -- TIEMPO DE EJECUCION 2 INICIAL DEL SUBPROCESO
        v_time3         TIMESTAMP;                                          -- TIEMPO DE EJECUCION 3 FINAL DEL SUBPROCESO
        v_time4         TIMESTAMP;                                          -- TIEMPO DE EJECUCION 4 FINAL DEL PROCESO DE DEPURACION
        v_time5         TIMESTAMP;                                          -- TIEMPO DE EJECUCION 5 INICIAL DEL PROCESO
        v_time6         TIMESTAMP;                                          -- TIEMPO DE EJECUCION 6 FINAL DEL PROCESO
        v_time_tot1     VARCHAR2 (10);                                      -- TIEMPO TOTAL DE EJECUCION DEL PROCESO DE DEPURACION
        v_time_tot2     VARCHAR2 (10);                                      -- TIEMPO TOTAL DE EJECUCION DEL SUB PROCESO DE DEPURACION
     DORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'COMERCIOS_LIQ_DETALLES: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';
		
-- IMPORT DE LAS TABLAS COMERCIOS_LIQ_CONCEPTOS, COMERCIOS_LIQ_IMPUESTOS, COMERCIOS_LIQ_PLAZOS:

        FOR r IN (SELECT owner, table_name FROM DBA_TABLES WHERE owner = v_sche_dest
              AND table_name IN ('COMERCIOS_LIQ_CONCEPTOS','COMERCIOS_LIQ_IMPUESTOS','COMERCIOS_LIQ_PLAZOS'))
        LOOP
        
            v_time2 := systimestamp;
            
            EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || r.owner || '.' || r.table_name || ' SELECT /*+ PARALLEL (4) */ D.* FROM ' || r.table_name || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' D join COMERCIOS_LIQ_CABECERA' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' C ON D.NRO_LIQUIDACION = C.NRO_LIQUIDACION AND D.ID_COMERCIO_CENTRAL=C.ID_COMERCIO_CENTRAL AND TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= ' || v_date_dep;
		
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
            
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || r.owner || '.' || r.table_name || ': ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
		
            EXECUTE IMMEDIATE 'COMMIT';
		
        END LOOP;

-- IMPORT DE LA TABLA COMERCIOS_LIQ_CABECERA:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.COMERCIOS_LIQ_CABECERA SELECT /*+ PARALLEL (4) */ C.* FROM COMERCIOS_LIQ_CABECERA' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) ||  ' C WHERE TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= ' || v_date_dep;
                            
        v_num_row := SQL%rowcount;
                            
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'COMERCIOS_LIQ_CABECERA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
        
        EXECUTE IMMEDIATE 'COMMIT';
		
-- IMPORT DE LA TABLA AUTORIZ_INTENTOS_REVERSOS:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZ_INTENTOS_REVERSOS SELECT /*+ PARALLEL (4) */ I.* FROM AUTORIZ_INTENTOS_REVERSOS' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) ||  '  I JOIN AUTORIZACION_REVERSOS_COLA' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) ||  ' R ON I.ID_AUTORIZACION_REVERSO = R.ID_AUTORIZACION_REVERSO AND TRUNC (R.FECHA_ALTA) <= ' || v_date_dep;

        v_num_row := SQL%rowcount;
                            
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZ_INTENTOS_REVERSOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA AUTORIZACION_REVERSOS_COLA:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION_REVERSOS_COLA SELECT /*+ PARALLEL (4) */ * FROM AUTORIZACION_REVERSOS_COLA' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) ||  ' WHERE TRUNC (FECHA_ALTA) <= ' || v_date_dep;
                           
        v_num_row := SQL%rowcount;
                           
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZACION_REVERSOS_COLA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA CONSUMOS:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.CONSUMOS SELECT /*+ PARALLEL (4) */ C.* FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) ||  ' C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep;
                            
        v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'CONSUMOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA TC33A:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_desS_LIQ_DETALLES SELECT /*+ PARALLEL (4) */ D.* FROM COMERCIOS_LIQ_DETALLES'|| TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' D 
						   WHERE D.ID_CONSUMO IN (SELECT /*+ PARALLEL (4) */ S.ID_CONSUMO FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' S WHERE TRUNC (S.FECHA_OPER) <= ' || v_date_dep || ')';
		  
		v_num_row := SQL%rowcount;
			
		v_time3 := systimestamp;
               
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'COMERCIOS_LIQ_DETALLES: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';
		
-- IMPORT DE LAS TABLAS COMERCIOS_LIQ_CONCEPTOS, COMERCIOS_LIQ_IMPUESTOS, COMERCIOS_LIQ_PLAZOS:

        FOR r IN (SELECT owner, table_name FROM DBA_TABLES WHERE owner = v_sche_dest
              AND table_name IN ('COMERCIOS_LIQ_CONCEPTOS','COMERCIOS_LIQ_IMPUESTOS','COMERCIOS_LIQ_PLAZOS'))
        LOOP
        
            v_time2 := systimestamp;
            
            EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || r.owner || '.' || r.table_name || ' SELECT /*+ PARALLEL (4) */ D.* FROM ' || r.table_name || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' D join COMERCIOS_LIQ_CABECERA' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' C ON D.NRO_LIQUIDACION = C.NRO_LIQUIDACION AND D.ID_COMERCIO_CENTRAL=C.ID_COMERCIO_CENTRAL AND TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= ' || v_date_dep;
		
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
            
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || r.owner || '.' || r.table_name || ': ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
		
            EXECUTE IMMEDIATE 'COMMIT';
		
        END LOOP;

-- IMPORT DE LA TABLA COMERCIOS_LIQ_CABECERA:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.COMERCIOS_LIQ_CABECERA SELECT /*+ PARALLEL (4) */ C.* FROM COMERCIOS_LIQ_CABECERA' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) ||  ' C WHERE TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= ' || v_date_dep;
                            
        v_num_row := SQL%rowcount;
                            
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'COMERCIOS_LIQ_CABECERA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
        
        EXECUTE IMMEDIATE 'COMMIT';
		
-- IMPORT DE LA TABLA AUTORIZ_INTENTOS_REVERSOS:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZ_INTENTOS_REVERSOS SELECT /*+ PARALLEL (4) */ I.* FROM AUTORIZ_INTENTOS_REVERSOS' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) ||  '  I JOIN AUTORIZACION_REVERSOS_COLA' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) ||  ' R ON I.ID_AUTORIZACION_REVERSO = R.ID_AUTORIZACION_REVERSO AND TRUNC (R.FECHA_ALTA) <= ' || v_date_dep;

        v_num_row := SQL%rowcount;
                            
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZ_INTENTOS_REVERSOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA AUTORIZACION_REVERSOS_COLA:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION_REVERSOS_COLA SELECT /*+ PARALLEL (4) */ * FROM AUTORIZACION_REVERSOS_COLA' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) ||  ' WHERE TRUNC (FECHA_ALTA) <= ' || v_date_dep;
                           
        v_num_row := SQL%rowcount;
                           
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZACION_REVERSOS_COLA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA CONSUMOS:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.CONSUMOS SELECT /*+ PARALLEL (4) */ C.* FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) ||  ' C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep;
                            
        v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'CONSUMOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA TC33A:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.TC33A SELECT /*+ PARALLEL (4) */ I.* FROM TC33A' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' I WHERE EXISTS (SELECT 1 FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' C WHERE C.ID_TC33A = I.ID_TC33A AND C.ID_COD_MOVIMIENTO IN (1,2) AND TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ')';
                            
        v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'TC33A: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        	
-- IMPORT DE LA TABLA AUTORIZACION:

        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION SELECT /*+ PARALLEL (4) */ * FROM AUTORIZACION' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' WHERE TRUNC(FECHA_AUTORIZACION) <= ' || v_date_dep ||
						  ' AND ID_AUTORIZACION NOT IN (SELECT /*+ PARALLEL (4) */ ID_AUTORIZACION_ORIGINAL FROM AUTORIZACION_ADQUIRENTE_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' WHERE TRUNC(FECHA_TRANSACCION_INI) BETWEEN ' || v_date_ini3 || ' AND ' || v_date_dep6 || ' AND ID_AUTORIZACION_ORIGINAL IS NOT NULL)';
                            
        v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZACION: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA AUTORIZACION_CONSULTA:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION_CONSULTA SELECT /*+ PARALLEL (4) */ C.* FROM AUTORIZACION_CONSULTA' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) ||  ' C WHERE TRUNC(C.FECHA_CONSULTA) <= ' || v_date_dep;
                            
        v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZACION_CONSULTA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';  
        
-- IMPORT DE LA TABLA AUTORIZACION_ADQUIRENTE_LOG:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION_ADQUIRENTE_LOG SELECT /*+ PARALLEL (4) */ * FROM AUTORIZACION_ADQUIRENTE_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' WHERE TRUNC(FECHA_TRANSACCION_INI) <= ' || v_date_dep;
        
        v_num_row := SQL%rowcount;
         
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZACION_ADQUIRENTE_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);

        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA RESPUESTA_MC_LOG:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.RESPUESTA_MC_LOG SELECT /*+ PARALLEL (4) */ * FROM RESPUESTA_MC_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' WHERE TRUNC (FECHA_TRANSACCION_INI) <= ' || v_date_dep;
        
        v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'RESPUESTA_MC_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';

-------------------------------------------------------------
-----   SE HABILITAN LOS CONSTRAINTS EN LA BD DESTINO   -----
-------------------------------------------------------------
        
BEGIN

    EXECUTE IMMEDIATE 'alter session set current_schema = SOPORTEDBA';

	FOR r IN (SELECT owner, table_name, constraint_name FROM DBA_CONSTRAINTS WHERE owner = v_sche_dest
              AND table_name IN ('AUTORIZACION',
                                 'AUTORIZACION_ADQUIRENTE_LOG',
								 'AUTORIZ_INTENTOS_REVERSOS',
								 'AUTORIZACION_REVERSOS_COLA',
                                 'COMERCIOS_LIQ_CABECERA',
                                 'COMERCIOS_LIQ_CONCEPTOS',
                                 'COMERCIOS_LIQ_DETALLES',
                                 'COMERCIOS_LIQ_IMPUESTOS',
                                 'COMERCIOS_LIQ_PLAZOS',
                                 'IN_T464',
                                 'CONSUMOS',
                                 'CONSUMOS_CUOTAS',
                                 'CONSUMOS_DATOS_ADICIONALES',
								 'CONSUMOS_CARGOS_ADICIONALES',
                                 'CTF_FILE_VISA',
                                 'CTF_VISA',
                                 'IPM',
                                 'IPM_FILE',
                                 'PRESENTACIONES',
                                 'PROMOCION_LOG',
                                 'RESPUESTA_MC_LOG',
                                 'RETENCIONES_CONSUMOS',
                                 'TQR4_ADQUIRENCIA',
                                 'TC33A',
                                 'AUTORIZACION_CONSULTA'
								 )
                       AND constraint_type = 'R'
              ORDER BY table_name ASC)
    LOOP
    
        v_time2 := systimestamp;
    
        EXECUTE IMMEDIATE   'ALTER TABLE ' || r.owner|| '.' || r.table_name || ' ENABLE NOVALIDATE CONSTRAINT ' || r.constraint_name;
    
        v_time3 := systimestamp;
        
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
        
        -- INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,'Se habilito el constraint: ' || r.table_name || '.' || r.constraint_name, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
        
    END LOOP;
END;
		
		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_dest,'Se habilitan los constraints en la bd historica ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
			
sys.dbms_session.sleep(2);

v_time6 := systimestamp;

v_time_tot3:= substr(TO_CHAR(v_time6-v_time5,'SSSS.FF'),9,8);
		
		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,v_time_tot3,v_fecha_dep,v_sche_dest,'Fin del proceso de copia de datos a la BD Historica ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);

sys.dbms_session.sleep(2);

v_time5 := systimestamp;
		
		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_ori,'Inicia el proceso de depuracion de datos en las tablas de: ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
        
-------------------------------------------------------------
-------- PROCESO DE UPDATE Y DELETE EN PRODUCCION -----------
-------------------------------------------------------------
        
        SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_CLEANING_1@TO_PROD_ENTIDAD703(v_sche_ori, v_fecha_dep, v_proc_id);
        
------------------------------------------------------------------------------------------------------------------------------------
-------- SE ELIMINAN REGISTROS EN EL HISTORICO QUE NO SE BORRARON EN PROD (POR FILTRO DEL DELETE) PARA EVITAR DUPLICIDAD -----------
------------------------------------------------------------------------------------------------------------------------------------
        
BEGIN

    FOR r IN (SELECT owner, table_name, constraint_name FROM DBA_CONSTRAINTS WHERE owner = v_sche_dest
              AND table_name IN ('AUTORIZACION',
                                 'AUTORIZACION_ADQUIRENTE_LOG',
								 'AUTORIZ_INTENTOS_REVERSOS',
								 'AUTORIZACION_REVERSOS_COLA',
                                 'COMERCIOS_LIQ_CABECERA',
                                 'COMERCIOS_LIQ_CONCEPTOS',
                                 'COMERCIOS_LIQ_DETALLES',
                                 'COMERCIOS_LIQ_IMPUESTOS',
                                 'COMERCIOS_LIQ_PLAZOS',
                                 'IN_T464',
                                 'CONSUMOS',
                                 'CONSUMOS_CUOTAS',
                                 'CONSUMOS_DATOS_ADICIONALES',
								 'CONSUMOS_CARGOS_ADICIONALES',
                                 'CTF_FILE_VISA',
                                 'CTF_VISA',
                                 'IPM',
                                 'IPM_FILE',
                                 'PRESENTACIONES',
                                 'PROMOCION_LOG',
                                 'RESPUESTA_MC_LOG',
                                 'RETENCIONES_CONSUMOS',
                                 'TQR4_ADQUIRENCIA',
                                 'TC33A',
                                 'AUTORIZACION_CONSULTA'
								 )
                       AND constraint_type = 'R'
              ORDER BY table_name ASC)
    LOOP
                
        EXECUTE IMMEDIATE   'ALTER TABLE ' || r.owner|| '.' || r.table_name || ' DISABLE CONSTRAINT ' || r.constraint_name;
        
    END LOOP;
END;
        
-- SE ELIMINAN REGISTROS DE LA TABLA AUTORIZACION_ADQUIRENTE_LOG:

       v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_dest || '.AUTORIZACION_ADQUIRENTE_LOG
                           WHERE ID_AUTORIZACION_ADQUIRENTE IN (SELECT /*+ PARALLEL (4) */ ID_AUTORIZACION_ADQUIRENTE FROM ' || v_sche_dest || '.AUTORIZACION_ADQUIRENTE_LOG WHERE TRUNC(FECHA_TRANSACCION_INI) BETWEEN ' || v_date_inim || ' AND ' || v_date_dep || '
                                                                INTERSECT
                                                                SELECT /*+ PARALLEL (4) */ ID_AUTORIZACION_ADQUIRENTE FROM AUTORIZACION_ADQUIRENTE_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' WHERE TRUNC(FECHA_TRANSACCION_INI) <= ' || v_date_dep ||')';
                                                                
       v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Para evitar duplicidad, con fecha entre ' || v_fecha_inim || ' y ' || v_fecha_dep || ' numero de registros eliminados en ' || v_sche_dest || '.' || 'AUTORIZACION_ADQUIRENTE_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
                                             
-- SE ELIMINAN REGISTROS DE LA TABLA RESPUESTA_MC_LOG:

       v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_dest || '.RESPUESTA_MC_LOG
                           WHERE ID_RESPUESTA_MC IN (SELECT /*+ PARALLEL (4) */ ID_RESPUESTA_MC FROM ' || v_sche_dest || '.RESPUESTA_MC_LOG WHERE TRUNC(FECHA_TRANSACCION_INI) BETWEEN ' || v_date_inim || ' AND ' || v_date_dep || '
                                                     INTERSECT
                                                     SELECT /*+ PARALLEL (4) */ ID_RESPUESTA_MC FROM RESPUESTA_MC_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' WHERE TRUNC(FECHA_TRANSACCION_INI) <= ' || v_date_dep ||')';
                                                     
        v_num_row := SQL%rowcount;
         
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Para evitar duplicidad, con fecha entre ' || v_fecha_inim || ' y ' || v_fecha_dep || ' numero de registros eliminados en ' || v_sche_dest || '.' || 'RESPUESTA_MC_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);

        EXECUTE IMMEDIATE 'COMMIT';
        
BEGIN

    EXECUTE IMMEDIATE 'alter session set current_schema = SOPORTEDBA';

	FOR r IN (SELECT owner, table_name, constraint_name FROM DBA_CONSTRAINTS WHERE owner = v_sche_dest
              AND table_name IN ('AUTORIZACION',
                                 'AUTORIZACION_ADQUIRENTE_LOG',
								 'AUTORIZ_INTENTOS_REVERSOS',
								 'AUTORIZACION_REVERSOS_COLA',
                                 'COMERCIOS_LIQ_CABECERA',
                                 'COMERCIOS_LIQ_CONCEPTOS',
                                 'COMERCIOS_LIQ_DETALLES',
                                 'COMERCIOS_LIQ_IMPUESTOS',
                                 'COMERCIOS_LIQ_PLAZOS',
                                 'IN_T464',
                                 'CONSUMOS',
                                 'CONSUMOS_CUOTAS',
                                 'CONSUMOS_DATOS_ADICIONALES',
								 'CONSUMOS_CARGOS_ADICIONALES',
                                 'CTF_FILE_VISA',
                                 'CTF_VISA',
                                 'IPM',
                                 'IPM_FILE',
                                 'PRESENTACIONES',
                                 'PROMOCION_LOG',
                                 'RESPUESTA_MC_LOG',
                                 'RETENCIONES_CONSUMOS',
                                 'TQR4_ADQUIRENCIA',
                                 'TC33A',
                                 'AUTORIZACION_CONSULTA'
								 )
                       AND constraint_type = 'R'
              ORDER BY table_name ASC)
    LOOP
    
        EXECUTE IMMEDIATE   'ALTER TABLE ' || r.owner|| '.' || r.table_name || ' ENABLE NOVALIDATE CONSTRAINT ' || r.constraint_name;
    
    END LOOP;
END;
        
v_time6 := systimestamp;

v_time_tot3:= substr(TO_CHAR(v_time6-v_time5,'SSSS.FF'),9,8);

sys.dbms_session.sleep(1);
		
		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,v_time_tot3,v_fecha_dep,v_sche_ori,'Fin del proceso de depuracion de datos en las tablas de: ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
        
sys.dbms_session.sleep(1);

v_time4 := systimestamp;

        v_time_tot1:= substr(TO_CHAR(v_time4-v_time1,'SSSS.FF'),9,8);
		
		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,v_time_tot1,v_fecha_dep,v_sche_dest,'Fin del proceso de copia de registros a la BD Historica ' || v_sche_dest || ' y depuración en ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
       
        
ELSE
		
		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_dest,'ERROR: Seleccione una opción: COPY, solo copia de registros a histórico, DELETE, solo borrado de registros en PROD ó ALL, copia de registros a histórico y borrado en PROD ó validar que la fecha de depuración sea menor a la fecha de copia. Ultima fecha de copia en ' || v_sche_dest || ' es ' || v_ult_proc, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
        
END IF;

------------------------------------------------------------------
-- LOGUEO DE ERRORES EN LA TABLA SOPORTEDBA.LOG_DEPURADORES --
------------------------------------------------------------------

    EXCEPTION
        WHEN OTHERS
        THEN
            PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,NULL,NULL,SQLERRM, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1', SQLCODE, dbms_utility.format_error_backtrace, dbms_utility.format_error_stack);
    END;

END;

END PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1;

PROCEDURE PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2
-- PARAMETROS DE ENTRADA:
--
--  STORED PROCEDURE QUE TOMA LA FECHA QUE SE LE INDICA PARA HACER LA DEPURACION
--
--  EJEMPLO para la ejecución: CALL SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2 --> Solo borra los datos de la entidad ENTIDAD703 de las tablas que conforman el proceso PRC_WFGADQ_ENTITY_DATA_CLEANING_2

--  NOTA: OJO cuando se actualice el código, estar atentos a realizar bien los cambios dentro de los ciclos IF dependiendo de la acción ('COPY','DELETE',ó 'ALL') que se requiera modificar.
IS
BEGIN

        EXECUTE IMMEDIATE 'alter session set current_schema = SOPORTEDBA';
        EXECUTE IMMEDIATE 'alter session set nls_Date_format=''DD/MM/YYYY''';
        EXECUTE IMMEDIATE 'alter session set nls_timestamp_format=''DD/MM/YYYY''';
        
    DECLARE
        v_code   	    NUMBER;                                             -- CODIGO DE ERROR
        v_errm   	    VARCHAR2 (300);                                     -- MENSAJE DE ERROR
        v_time1         TIMESTAMP;                                          -- TIEMPO DE EJECUCION 1 INICIAL DEL PROCESO DE DEPURACION
        v_time2         TIMESTAMP;                                          -- TIEMPO DE EJECUCION 2 INICIAL DEL SUBPROCESO
        v_time3         TIMESTAMP;                                          -- TIEMPO DE EJECUCION 3 FINAL DEL SUBPROCESO
        v_time4         TIMESTAMP;                                          -- TIEMPO DE EJECUCION 4 FINAL DEL PROCESO DE DEPURACION
        v_time5         TIMESTAMP;                                          -- TIEMPO DE EJECUCION 5 FINAL DEL PROCESO
        v_time6         TIMESTAMP;                                          -- TIEMPO DE EJECUCION 6 FINAL DEL PROCESO
        v_time_tot1     VARCHAR2 (10);                                      -- TIEMPO TOTAL DE EJECUCION DEL PROCESO DE DEPURACION
        v_time_tot2     VARCHAR2 (10);                                      -- TIEMPO TOTAL DE EJECUCION DEL SUB PROCESO DE DEPURACION
        v_time_tot3     VARCHAR2 (10);                                      -- TIEMPO TOTAL DE EJECUCION DEL SUB PROCESO DE DEPURACION
        v_num_row 	    NUMBER;                                             -- NUMERO DE REGISTROS AFECTADOS EN LA SENTENCIA
		v_sche_ori 	    VARCHAR2 (20) := 'ENTIDAD703';                      -- ESQUEMA A ORIGEN
		--v_sche_dest 	VARCHAR2 (10):= SUBSTR(v_sche_ori,6,15);            -- ESQUEMA DESTINO (USADO EN PROD_ENTIDAD7XX)
		v_sche_dest 	VARCHAR2 (10):= v_sche_ori;                         -- ESQUEMA DESTINO
		--v_acc_ejec 		VARCHAR2 (10):= acc_ejec;                           -- ACCION A EJECUTAR
		v_fecha_dep     DATE;           					                -- FECHA DE DEPURACION
		v_fecha_dep1    DATE:='01/01/2023';                                 -- FECHA DEFINIDA PARA HACER EL UPDATE DE LOS ARN DE LAS TABLAS IPM Y CTF_VISA EN CONSUMOS
		v_date_dep1     VARCHAR2(15):= '''' || v_fecha_dep1 || '''';        -- FECHA DE DEPURACION EN FORMATO 'DD/MM/YYYY'
		v_fecha_dep3    DATE;                                               -- FECHA DE DEPURACION + 3 MESES
		v_date_dep3     VARCHAR2(15);                                       -- FECHA DE DEPURACION + 3 MESES EN FORMATO 'DD/MM/YYYY'
		v_fecha_limit   DATE;
		v_fecha_ini3    DATE;
		v_date_ini3     VARCHAR2(15);
		v_fecha_dep6    DATE;                                               -- FECHA DE DEPURACION + 6 MESES
		v_date_dep6     VARCHAR2(15);
		v_date_dep      VARCHAR2(15);     								    -- FECHA DE DEPURACION EN FORMATO 'DD/MM/YYYY'
		v_seq_id        NUMBER:=SEQ_LOG_DEPURADORES.NEXTVAL;                -- OBTIENE EL VALOR DE LA SECUENCIA PARA EL ID DEL PROCESO
		v_proc_id       NUMBER:=SEQ_LOG_DEPURADORES.CURRVAL;                -- DEFINE EL ID DEL PROCESO


    BEGIN
    
       -- SE DEFINE LA FECHA DE LA DATA QUE VA A QUEDAR EN LINEA (6 MESES):
        EXECUTE IMMEDIATE 'SELECT ADD_MONTHS(TRUNC(SYSDATE),-6) FROM DUAL' INTO v_fecha_dep;
		v_date_dep:= '''' || v_fecha_dep || '''';
		v_fecha_ini3:= v_fecha_dep +1;
		v_date_ini3:= '''' || v_fecha_ini3 || '''';
        -- SE CALCULA LA FECHA DE DEPURACION +6 MESES:
        EXECUTE IMMEDIATE 'SELECT ADD_MONTHS(TO_DATE(''' || v_fecha_dep || ''',''DD/MM/YYYY''),+6) FROM DUAL' INTO v_fecha_dep6;
        v_date_dep6:= '''' || v_fecha_dep6 || '''';                         -- FECHA DE DEPURACION + 6 MESES EN FORMATO 'DD/MM/YYYY'
        -- SE CALCULA LA FECHA FINAL +3 MESES:
        EXECUTE IMMEDIATE 'SELECT ADD_MONTHS(TO_DATE(''' || v_fecha_dep || ''',''DD/MM/YYYY''),+3) FROM DUAL' INTO v_fecha_dep3;
        v_date_dep3:= '''' || v_fecha_dep3 || '''';   

--------------------------------------------------------------------
----- SE VALIDA SI ESTÁ DENTRO DEL RANGO HORARIO DE EJECUCIÓN  -----
--------------------------------------------------------------------

DECLARE
    v_hora_actual VARCHAR2(5);
BEGIN
    v_hora_actual := TO_CHAR(
        SYSTIMESTAMP AT TIME ZONE 'America/Argentina/Buenos_Aires', 'HH24:MI'
    );

    IF v_hora_actual < '00:29' OR v_hora_actual >= '00:40' THEN
        SOPORTEDBA.PRC_WRITE_ERROR_LOG_DATA_CLEANING(
            NULL,
            SYSDATE,
            NULL,
            NULL,
            NULL,
            'Proceso no ejecutado por estar fuera de ventana horaria. Hora actual Argentina: ' || v_hora_actual,
            'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',
            NULL,
            NULL,
            NULL
        );

        RETURN;
    END IF;
        
--IF v_acc_ejec='COPY' THEN
--        
---------------------------------------------------------------
------- SE DESHABILITAN LOS CONSTRAINTS EN LA BD DESTINO  -----
---------------------------------------------------------------
--			
--			PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_dest,'Inicio del proceso de copia de registros a la BD Historica ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--
--sys.dbms_session.sleep(2);
--
--v_time1 := systimestamp;
--            
--BEGIN
--
--	FOR r IN (SELECT owner, table_name, constraint_name FROM DBA_CONSTRAINTS WHERE owner = v_sche_dest
--              AND table_name IN ('AUTORIZACION',
--                                 'AUTORIZACION_ADQUIRENTE_LOG',
--								 'AUTORIZ_INTENTOS_REVERSOS',
--								 'AUTORIZACION_REVERSOS_COLA',
--                                 'COMERCIOS_LIQ_CABECERA',
--                                 'COMERCIOS_LIQ_CONCEPTOS',
--                                 'COMERCIOS_LIQ_DETALLES',
--                                 'COMERCIOS_LIQ_IMPUESTOS',
--                                 'COMERCIOS_LIQ_PLAZOS',
--                                 'IN_T464',
--                                 'CONSUMOS',
--                                 'CONSUMOS_CUOTAS',
--                                 'CONSUMOS_DATOS_ADICIONALES',
--								 'CONSUMOS_CARGOS_ADICIONALES',
--                                 'CTF_FILE_VISA',
--                                 'CTF_VISA',
--                                 'IPM',
--                                 'IPM_FILE',
--                                 'PRESENTACIONES',
--                                 'PROMOCION_LOG',
--                                 'RESPUESTA_MC_LOG',
--                                 'RETENCIONES_CONSUMOS',
--                                 'TQR4_ADQUIRENCIA'
--								 )
--                       AND constraint_type = 'R'
--              ORDER BY table_name ASC)
--    LOOP
--        v_time2 := systimestamp;
--        
--        EXECUTE IMMEDIATE   'ALTER TABLE ' || r.owner|| '.' || r.table_name || ' DISABLE CONSTRAINT ' || r.constraint_name;
--        
--        v_time3 := systimestamp;
--        
--        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--        
--        -- INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,'Se deshabilito el constraint: ' || r.table_name || '.' || r.constraint_name, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--        
--    END LOOP;
--END;
--
--sys.dbms_session.sleep(1);
--			
--			PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_dest,'Se deshabilitan los constraints en la BD ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--
---------------------------------------------------------------
------- INICIA EL BLOQUE DE COPIADO DE DATOS AL HISTORICO -----
---------------------------------------------------------------
--
---- IMPORT DE LA TABLA TQR4_ADQUIRENCIA:
--
--        v_time2 := systimestamp;
--            
--			EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.TQR4_ADQUIRENCIA SELECT /*+ PARALLEL (4) */ I.* FROM TQR4_ADQUIRENCIA' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' I join CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' C on I.ID_CONSUMO = C.ID_CONSUMO AND TRUNC(C.FECHA_OPER) <= ' || v_date_dep;
--		
--            v_num_row := SQL%rowcount;
--            
--            v_time3 := systimestamp;
--            
--            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--		
--            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'TQR4_ADQUIRENCIA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--		
--            EXECUTE IMMEDIATE 'COMMIT';
--
---- IMPORT DE LA TABLA IPM:
--
--        v_time2 := systimestamp;
--
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.IPM SELECT /*+ PARALLEL (4) */ D.* FROM IPM' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' D WHERE D.ID_IPM_FILE IN (SELECT /*+ PARALLEL (4) */ I.ID_IPM_FILE FROM IPM_FILE' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' I WHERE TRUNC(I.FECHA_CARGA) <= ' || v_date_dep || ' OR I.FECHA_CARGA IS NULL)
--                            OR D.ID_CONSUMO IN (SELECT /*+ PARALLEL (4) */ C.ID_CONSUMO FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ')';
--                            
--        v_num_row := SQL%rowcount;
--            
--        v_time3 := systimestamp;
--        
--        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--		
--        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ', numero de registros insertados en ' || v_sche_dest || '.' || 'IPM: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--		
--        EXECUTE IMMEDIATE 'COMMIT';
--        
---- IMPORT DE LA TABLA IPM_FILE:
--
--        v_time2 := systimestamp;
--
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.IPM_FILE SELECT /*+ PARALLEL (4) */ * FROM IPM_FILE'|| TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' WHERE TRUNC(FECHA_CARGA) <= ' || v_date_dep || ' OR TRUNC(FECHA_CARGA) IS NULL';
--		  
--		v_num_row := SQL%rowcount;
--			
--		v_time3 := systimestamp;
--		
--		v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--		
--		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ', numero de registros insertados en ' || v_sche_dest || '.' || 'IPM_FILE: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--		
--		EXECUTE IMMEDIATE 'COMMIT';
--		
---- IMPORT DE LA TABLA CTF_VISA:
--
--        v_time2 := systimestamp;
--
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.CTF_VISA SELECT /*+ PARALLEL (4) */ D.* FROM CTF_VISA'|| TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' D WHERE D.ID_CTF_FILE IN (SELECT /*+ PARALLEL (4) */ I.ID_CTF_FILE FROM CTF_FILE_VISA'|| TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' I WHERE TRUNC(I.FECHA_CARGA) <= ' || v_date_dep || ' OR I.FECHA_CARGA IS NULL)
--                           OR D.ID_CONSUMO IN (SELECT /*+ PARALLEL (4) */ C.ID_CONSUMO FROM CONSUMOS'|| TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ')';
--                           
--        v_num_row := SQL%rowcount;
--			
--		v_time3 := systimestamp;
--		
--		v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--		
--		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ', numero de registros insertados en ' || v_sche_dest || '.' || 'CTF_VISA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--		
--		EXECUTE IMMEDIATE 'COMMIT';
--		
---- IMPORT DE LA TABLA CTF_FILE_VISA:
--
--        v_time2 := systimestamp;
--
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.CTF_FILE_VISA WHERE TRUNC(FECHA_CARGA) <= ' || v_date_dep || ' OR TRUNC(FECHA_CARGA) IS NULL';
--		  
--			v_num_row := SQL%rowcount;
--			
--		v_time3 := systimestamp;
--		
--		v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--		
--		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ', numero de registros insertados en ' || v_sche_dest || '.' || 'CTF_FILE_VISA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--		
--		EXECUTE IMMEDIATE 'COMMIT';
--
---- IMPORT DE LA TABLA IN_T464:
--
--        v_time2 := systimestamp;
--
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.IN_T464 SELECT /*+ PARALLEL (4) */ * FROM IN_T464'|| TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || 'I WHERE TRUNC(I.ORIGINAL_SETTLEMENT_DATE) <= ' || v_date_dep || '
--                           OR I.ID_CONSUMO IN (SELECT /*+ PARALLEL (4) */ ID_CONSUMO FROM CONSUMOS'|| TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' WHERE TRUNC(FECHA_OPER) <= ' || v_date_dep || ')';
--		  
--		v_num_row := SQL%rowcount;
--			
--		v_time3 := systimestamp;
--		
--		v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--		
--		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ', numero de registros insertados en ' || v_sche_dest || '.' || 'IN_T464: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--		
--		EXECUTE IMMEDIATE 'COMMIT';
--		
---------------------------------------------------------------
-------   SE HABILITAN LOS CONSTRAINTS EN LA BD DESTINO   -----
---------------------------------------------------------------
--        
--BEGIN
--
--    EXECUTE IMMEDIATE 'alter session set current_schema = SOPORTEDBA';
--
--	FOR r IN (SELECT owner, table_name, constraint_name FROM DBA_CONSTRAINTS WHERE owner = v_sche_dest
--              AND table_name IN ('AUTORIZACION',
--                                 'AUTORIZACION_ADQUIRENTE_LOG',
--								 'AUTORIZ_INTENTOS_REVERSOS',
--								 'AUTORIZACION_REVERSOS_COLA',
--                                 'COMERCIOS_LIQ_CABECERA',
--                                 'COMERCIOS_LIQ_CONCEPTOS',
--                                 'COMERCIOS_LIQ_DETALLES',
--                                 'COMERCIOS_LIQ_IMPUESTOS',
--                                 'COMERCIOS_LIQ_PLAZOS',
--                                 'IN_T464',
--                                 'CONSUMOS',
--                                 'CONSUMOS_CUOTAS',
--                                 'CONSUMOS_DATOS_ADICIONALES',
--								 'CONSUMOS_CARGOS_ADICIONALES',
--                                 'CTF_FILE_VISA',
--                                 'CTF_VISA',
--                                 'IPM',
--                                 'IPM_FILE',
--                                 'PRESENTACIONES',
--                                 'PROMOCION_LOG',
--                                 'RESPUESTA_MC_LOG',
--                                 'RETENCIONES_CONSUMOS',
--                                 'TQR4_ADQUIRENCIA'
--								 )
--                       AND constraint_type = 'R'
--              ORDER BY table_name ASC)
--    LOOP
--    
--        v_time2 := systimestamp;
--    
--        EXECUTE IMMEDIATE   'ALTER TABLE ' || r.owner|| '.' || r.table_name || ' ENABLE NOVALIDATE CONSTRAINT ' || r.constraint_name;
--    
--        v_time3 := systimestamp;
--        
--        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--        
--        -- INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,'Se habilito el constraint: ' || r.table_name || '.' || r.constraint_name, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--        
--    END LOOP;
--END;
--		
--		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_dest,'Se habilitan los constraints en la bd historica ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--			
--sys.dbms_session.sleep(2);
--
--v_time4 := systimestamp;
--
--    v_time_tot1:= substr(TO_CHAR(v_time4-v_time1,'SSSS.FF'),9,8);
--		
--		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,v_time_tot1,v_fecha_dep,v_sche_dest,'Fin del proceso de copia de datos a la BD Historica ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--
--ELSIF v_acc_ejec='DELETE' THEN

v_time1 := systimestamp;
		
		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_ori,'Inicia el proceso de depuracion de datos en las tablas de: ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
        
-------------------------------------------------------------
-------- PROCESO DE UPDATE Y DELETE EN PRODUCCION -----------
-------------------------------------------------------------
        
        SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_CLEANING_2@TO_PROD_ENTIDAD703(v_sche_ori, v_fecha_dep, v_proc_id);
       
        v_time4 := systimestamp;

        v_time_tot1:= substr(TO_CHAR(v_time4-v_time1,'SSSS.FF'),9,8);
		
		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,v_time_tot1,v_fecha_dep,v_sche_ori,'Fin del proceso de depuracion de datos en las tablas de: ' || v_sche_ori,'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);


--ELSIF v_acc_ejec='ALL' THEN 
--
---------------------------------------------------------------
------- SE DESHABILITAN LOS CONSTRAINTS EN LA BD DESTINO  -----
---------------------------------------------------------------
--			
--			PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_dest,'Inicio del proceso de copia de registros a la BD Historica ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--
--sys.dbms_session.sleep(2);
--
--v_time1 := systimestamp;
--
--v_time5 := systimestamp;
--            
--BEGIN
--
--	FOR r IN (SELECT owner, table_name, constraint_name FROM DBA_CONSTRAINTS WHERE owner = v_sche_dest
--              AND table_name IN ('AUTORIZACION',
--                                 'AUTORIZACION_ADQUIRENTE_LOG',
--								 'AUTORIZ_INTENTOS_REVERSOS',
--								 'AUTORIZACION_REVERSOS_COLA',
--                                 'COMERCIOS_LIQ_CABECERA',
--                                 'COMERCIOS_LIQ_CONCEPTOS',
--                                 'COMERCIOS_LIQ_DETALLES',
--                                 'COMERCIOS_LIQ_IMPUESTOS',
--                                 'COMERCIOS_LIQ_PLAZOS',
--                                 'IN_T464',
--                                 'CONSUMOS',
--                                 'CONSUMOS_CUOTAS',
--                                 'CONSUMOS_DATOS_ADICIONALES',
--								 'CONSUMOS_CARGOS_ADICIONALES',
--                                 'CTF_FILE_VISA',
--                                 'CTF_VISA',
--                                 'IPM',
--                                 'IPM_FILE',
--                                 'PRESENTACIONES',
--                                 'PROMOCION_LOG',
--                                 'RESPUESTA_MC_LOG',
--                                 'RETENCIONES_CONSUMOS',
--                                 'TQR4_ADQUIRENCIA'
--								 )
--                       AND constraint_type = 'R'
--              ORDER BY table_name ASC)
--    LOOP
--        v_time2 := systimestamp;
--        
--        EXECUTE IMMEDIATE   'ALTER TABLE ' || r.owner|| '.' || r.table_name || ' DISABLE CONSTRAINT ' || r.constraint_name;
--        
--        v_time3 := systimestamp;
--        
--        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--        
--        -- INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,'Se deshabilito el constraint: ' || r.table_name || '.' || r.constraint_name, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--        
--    END LOOP;
--END;
--
--sys.dbms_session.sleep(1);
--			
--			PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_dest,'Se deshabilitan los constraints en la BD ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--
---------------------------------------------------------------
------- INICIA EL BLOQUE DE COPIADO DE DATOS AL HISTORICO -----
---------------------------------------------------------------
--
---- IMPORT DE LA TABLA TQR4_ADQUIRENCIA:
--
--        v_time2 := systimestamp;
--            
--			EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.TQR4_ADQUIRENCIA SELECT /*+ PARALLEL (4) */ I.* FROM TQR4_ADQUIRENCIA' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' I join CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' C on I.ID_CONSUMO = C.ID_CONSUMO AND TRUNC(C.FECHA_OPER) <= ' || v_date_dep;
--		
--            v_num_row := SQL%rowcount;
--            
--            v_time3 := systimestamp;
--            
--            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--		
--            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'TQR4_ADQUIRENCIA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--		
--            EXECUTE IMMEDIATE 'COMMIT';
--
---- IMPORT DE LA TABLA IPM:
--
--        v_time2 := systimestamp;
--
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.IPM SELECT /*+ PARALLEL (4) */ D.* FROM IPM' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' D WHERE D.ID_IPM_FILE IN (SELECT /*+ PARALLEL (4) */ I.ID_IPM_FILE FROM IPM_FILE' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' I WHERE TRUNC(I.FECHA_CARGA) <= ' || v_date_dep || ' OR I.FECHA_CARGA IS NULL)
--                            OR D.ID_CONSUMO IN (SELECT /*+ PARALLEL (4) */ C.ID_CONSUMO FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ')';
--                            
--        v_num_row := SQL%rowcount;
--            
--        v_time3 := systimestamp;
--        
--        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--		
--        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ', numero de registros insertados en ' || v_sche_dest || '.' || 'IPM: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--		
--        EXECUTE IMMEDIATE 'COMMIT';
--        
---- IMPORT DE LA TABLA IPM_FILE:
--
--        v_time2 := systimestamp;
--
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.IPM_FILE SELECT /*+ PARALLEL (4) */ * FROM IPM_FILE'|| TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' WHERE TRUNC(FECHA_CARGA) <= ' || v_date_dep || ' OR TRUNC(FECHA_CARGA) IS NULL';
--		  
--		v_num_row := SQL%rowcount;
--			
--		v_time3 := systimestamp;
--		
--		v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--		
--		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ', numero de registros insertados en ' || v_sche_dest || '.' || 'IPM_FILE: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--		
--		EXECUTE IMMEDIATE 'COMMIT';
--		
---- IMPORT DE LA TABLA CTF_VISA:
--
--        v_time2 := systimestamp;
--
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.CTF_VISA SELECT /*+ PARALLEL (4) */ D.* FROM CTF_VISA'|| TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' D WHERE D.ID_CTF_FILE IN (SELECT /*+ PARALLEL (4) */ I.ID_CTF_FILE FROM CTF_FILE_VISA'|| TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' I WHERE TRUNC(I.FECHA_CARGA) <= ' || v_date_dep || ' OR I.FECHA_CARGA IS NULL)
--                           OR D.ID_CONSUMO IN (SELECT /*+ PARALLEL (4) */ C.ID_CONSUMO FROM CONSUMOS'|| TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ')';
--                           
--        v_num_row := SQL%rowcount;
--			
--		v_time3 := systimestamp;
--		
--		v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--		
--		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ', numero de registros insertados en ' || v_sche_dest || '.' || 'CTF_VISA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--		
--		EXECUTE IMMEDIATE 'COMMIT';
--		
---- IMPORT DE LA TABLA CTF_FILE_VISA:
--
--        v_time2 := systimestamp;
--
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.CTF_FILE_VISA WHERE TRUNC(FECHA_CARGA) <= ' || v_date_dep || ' OR TRUNC(FECHA_CARGA) IS NULL';
--		  
--			v_num_row := SQL%rowcount;
--			
--		v_time3 := systimestamp;
--		
--		v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--		
--		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ', numero de registros insertados en ' || v_sche_dest || '.' || 'CTF_FILE_VISA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--		
--		EXECUTE IMMEDIATE 'COMMIT';
--
---- IMPORT DE LA TABLA IN_T464:
--
--        v_time2 := systimestamp;
--
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.IN_T464 SELECT /*+ PARALLEL (4) */ * FROM IN_T464'|| TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || 'I WHERE TRUNC(I.ORIGINAL_SETTLEMENT_DATE) <= ' || v_date_dep || '
--                           OR I.ID_CONSUMO IN (SELECT /*+ PARALLEL (4) */ ID_CONSUMO FROM CONSUMOS'|| TO_NUMBER(SUBSTR(v_sche_ori,8,3)) || ' WHERE TRUNC(FECHA_OPER) <= ' || v_date_dep || ')';
--		  
--		v_num_row := SQL%rowcount;
--			
--		v_time3 := systimestamp;
--		
--		v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--		
--		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ', numero de registros insertados en ' || v_sche_dest || '.' || 'IN_T464: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--		
--		EXECUTE IMMEDIATE 'COMMIT';
--		
---------------------------------------------------------------
-------   SE HABILITAN LOS CONSTRAINTS EN LA BD DESTINO   -----
---------------------------------------------------------------
--        
--BEGIN
--
--    EXECUTE IMMEDIATE 'alter session set current_schema = SOPORTEDBA';
--
--	FOR r IN (SELECT owner, table_name, constraint_name FROM DBA_CONSTRAINTS WHERE owner = v_sche_dest
--              AND table_name IN ('AUTORIZACION',
--                                 'AUTORIZACION_ADQUIRENTE_LOG',
--								 'AUTORIZ_INTENTOS_REVERSOS',
--								 'AUTORIZACION_REVERSOS_COLA',
--                                 'COMERCIOS_LIQ_CABECERA',
--                                 'COMERCIOS_LIQ_CONCEPTOS',
--                                 'COMERCIOS_LIQ_DETALLES',
--                                 'COMERCIOS_LIQ_IMPUESTOS',
--                                 'COMERCIOS_LIQ_PLAZOS',
--                                 'IN_T464',
--                                 'CONSUMOS',
--                                 'CONSUMOS_CUOTAS',
--                                 'CONSUMOS_DATOS_ADICIONALES',
--								 'CONSUMOS_CARGOS_ADICIONALES',
--                                 'CTF_FILE_VISA',
--                                 'CTF_VISA',
--                                 'IPM',
--                                 'IPM_FILE',
--                                 'PRESENTACIONES',
--                                 'PROMOCION_LOG',
--                                 'RESPUESTA_MC_LOG',
--                                 'RETENCIONES_CONSUMOS',
--                                 'TQR4_ADQUIRENCIA'
--								 )
--                       AND constraint_type = 'R'
--              ORDER BY table_name ASC)
--    LOOP
--    
--        v_time2 := systimestamp;
--    
--        EXECUTE IMMEDIATE   'ALTER TABLE ' || r.owner|| '.' || r.table_name || ' ENABLE NOVALIDATE CONSTRAINT ' || r.constraint_name;
--    
--        v_time3 := systimestamp;
--        
--        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
--        
--        -- INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,'Se habilito el constraint: ' || r.table_name || '.' || r.constraint_name, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--        
--    END LOOP;
--END;
--		
--		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_dest,'Se habilitan los constraints en la bd historica ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--			
--sys.dbms_session.sleep(2);
--
--v_time6 := systimestamp;
--
--v_time_tot3:= substr(TO_CHAR(v_time6-v_time5,'SSSS.FF'),9,8);
--		
--		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,v_time_tot3,v_fecha_dep,v_sche_dest,'Fin del proceso de copia de datos a la BD Historica ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--
--sys.dbms_session.sleep(2);
--
--v_time5 := systimestamp;
--		
--		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_ori,'Inicia el proceso de depuracion de datos en las tablas de: ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--        
---------------------------------------------------------------
---------- PROCESO DE UPDATE Y DELETE EN PRODUCCION -----------
---------------------------------------------------------------
--        
--        SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_CLEANING_2@TO_PROD_ENTIDAD700(v_sche_ori, v_fecha_dep, v_proc_id);
--
--v_time6 := systimestamp;
--
--v_time_tot3:= substr(TO_CHAR(v_time6-v_time5,'SSSS.FF'),9,8);
--		
--		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,v_time_tot3,v_fecha_dep,v_sche_ori,'Fin del proceso de depuracion de datos en las tablas de: ' || v_sche_ori,'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--        
--sys.dbms_session.sleep(2);
--
--v_time4 := systimestamp;
--
--        v_time_tot1:= substr(TO_CHAR(v_time4-v_time1,'SSSS.FF'),9,8);
--		
--		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,v_time_tot1,v_fecha_dep,v_sche_dest,'Fin del proceso de copia de registros a la BD Historica ' || v_sche_dest || ' y depuración en ' || v_sche_ori,'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--       
--        
--ELSE
--		
--		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_dest,'ERROR: Seleccione una opción: COPY, solo copia de registros a histórico, DELETE, solo borrado de registros en PROD ó ALL, copia de registros a histórico y borrado en PROD ó validar la fecha de depuración usada','PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2',NULL,NULL,NULL);
--        
--END IF;

------------------------------------------------------------------
-- LOGUEO DE ERRORES EN LA TABLA SOPORTEDBA.LOG_DEPURADORES --
------------------------------------------------------------------

    EXCEPTION
        WHEN OTHERS
        THEN
            PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,NULL,NULL,SQLERRM, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2', SQLCODE, dbms_utility.format_error_backtrace, dbms_utility.format_error_stack);
    END;
	
END;
    
END PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2;

END PKG_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_703;
/

