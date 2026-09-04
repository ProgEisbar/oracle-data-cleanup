CREATE OR REPLACE PROCEDURE SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_CLEANING_2 (sche_ori IN VARCHAR2, fecha_depuracion IN VARCHAR2, proc_id IN NUMBER)
-- STORED PROCEDURE USADO PARA REALIZAR EL PROCESO DE DEPURACIÓN DE DATOS EN LAS BD DE WOLFGANG ADQUIRENCIA
-- TABLAS: CTF_FILE_VISA, CTF_VISA, IN_T464, IPM, IPM_FILE, TQR4_ADQUIRENCIA
-- TOMA LA FECHA  DE DEPURACION QUE SE LE INDICA, DEJANDO EN LINEA 6 MESES
-- PARAMETROS DE ENTRADA:
--  sche_ori: esquema origen (PROD_ENTIDAD700, PROD_ENTIDAD701 y PROD_ENTIDAD702)
--  fecha_depuracion: fecha de depuración en formato DD/MM/YYYY
--  proc_id:id del proceso (cuando se ejecuta de manera automatica)
--  EJEMPLO para la ejecución: EXEC SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_CLEANING_2('PROD_ENTIDAD702','31/12/2021');
IS
BEGIN
        EXECUTE IMMEDIATE 'alter session set current_schema = SOPORTEDBA';
        EXECUTE IMMEDIATE 'alter session set nls_Date_format=''DD/MM/RRRR''';
        EXECUTE IMMEDIATE 'alter session set nls_timestamp_format=''DD/MM/RRRR''';
DECLARE
		v_max_retries  	CONSTANT NUMBER := 3;								  -- CANTIDAD DE REINTENTOS EN CASO DE FALLAS AL DESHABILITAR / HABILITAR UNA FK
		v_retry_count 	NUMBER;												  -- NUMERO DE INTENTO
		v_success     	BOOLEAN;											  -- VARIABLE PARA VALIDAR SI FUE EXITOSO O NO EL DESHABILITAR / HABILITAR UNA FK
        v_code          NUMBER;                                               -- CODIGO DE ERROR
        v_errm          VARCHAR2 (300);                                       -- MENSAJE DE ERROR
        v_time1         TIMESTAMP;                                            -- TIEMPO DE EJECUCION 1 INICIAL DEL PROCESO DE DEPURACION
        v_time2         TIMESTAMP;                                            -- TIEMPO DE EJECUCION 2 INICIAL DEL SUBPROCESO
        v_time3         TIMESTAMP;                                            -- TIEMPO DE EJECUCION 3 FINAL DEL SUBPROCESO
        v_time4         TIMESTAMP;                                            -- TIEMPO DE EJECUCION 4 FINAL DEL PROCESO DE DEPURACION
        v_time_tot1     VARCHAR2 (10);                                        -- TIEMPO TOTAL DE EJECUCION DEL PROCESO DE DEPURACION
        v_time_tot2     VARCHAR2 (10);                                        -- TIEMPO TOTAL DE EJECUCION DEL SUB PROCESO DE DEPURACION
        v_sche_ori      VARCHAR2 (20) := sche_ori;                            -- ESQUEMA A DEPURAR
        v_fecha_limit   DATE;                                                 -- FECHA QUE DEFINE LA FECHA DE LOS DATOS QUE VAN A QUEDAR EN LINEA
		v_fecha_dep     DATE:= fecha_depuracion;                              -- FECHA DE DEPURACION
		v_fecha_dep1    DATE:='01/01/2023';                                   -- FECHA DEFINIDA PARA HACER EL UPDATE DE LOS ARN DE LAS TABLAS IPM Y CTF_VISA EN CONSUMOS
		v_fecha_dep3    DATE;                                                 -- FECHA DE DEPURACION + 3 MESES
		v_date_dep3     VARCHAR2(15);                                         -- FECHA DE DEPURACION + 3 MESES EN FORMATO 'DD/MM/YYYY'
		v_date_dep      VARCHAR2(15):= '''' || v_fecha_dep || '''';           -- FECHA DE DEPURACION EN FORMATO 'DD/MM/YYYY'
		v_date_dep1     VARCHAR2(15):= '''' || v_fecha_dep1 || '''';          -- FECHA DE DEPURACION EN FORMATO 'DD/MM/YYYY'
        v_num_row 	    NUMBER;                                               -- NUMERO DE REGISTROS AFECTADOS EN LA SENTENCIA
        v_proc_id       NUMBER:= proc_id;                                     -- ID DEL PROCESO

    BEGIN
    
		-- SE DEFINE LA FECHA DE LA DATA QUE VA A QUEDAR EN LINEA (6 MESES):
        EXECUTE IMMEDIATE 'SELECT ADD_MONTHS(TRUNC(SYSDATE),-6) FROM DUAL' INTO v_fecha_limit;
        -- SE CALCULA LA FECHA FINAL +3 MESES:
        EXECUTE IMMEDIATE 'SELECT ADD_MONTHS(TO_DATE(''' || v_fecha_dep || ''',''DD/MM/RRRR''),+3) FROM DUAL' INTO v_fecha_dep3;
        v_date_dep3:= '''' || v_fecha_dep3 || '''';          

IF v_fecha_dep <= v_fecha_limit THEN

-------------------------------------------------------------
------- SE DESHABILITAN LOS CONSTRAINTS EN LA BD PROD  ------
-------------------------------------------------------------

           PRC_WRITE_ERROR_LOG_DATA_CLEANING(v_proc_id,sysdate,NULL,v_fecha_dep,NULL,'Se inicia el proceso de actualizacion y depuracion de datos en la BD: ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);

sys.dbms_session.sleep(2);

v_time1 := systimestamp;

BEGIN

    FOR r IN (SELECT owner, table_name, constraint_name FROM DBA_CONSTRAINTS WHERE owner = v_sche_ori
                AND table_name IN (
                                          'CTF_FILE_VISA',
                                          'CTF_VISA',
                                          'IN_T464',
                                          'IPM',
                                          'IPM_FILE',
                                          --'PROMOCION_LOG',
										  'TQR4_ADQUIRENCIA',
										  'GESTION_IPM',
                                          'GESTION_CONTRACARGO',
                                          'CLEARING',
                                          'QUEUE_PRESENTATION_INCOMING'
                                          )
                       AND constraint_type = 'R'
              ORDER BY table_name ASC)
    LOOP
		v_retry_count := 0;
        v_success := FALSE;

        WHILE v_retry_count < v_max_retries AND NOT v_success LOOP
    BEGIN
    
        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE   'ALTER TABLE ' || r.owner|| '.' || r.table_name || ' DISABLE CONSTRAINT ' || r.constraint_name;
        
        v_time3 := systimestamp;
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		v_success := TRUE; -- Si llega aquí, fue exitoso
        
        --INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Se deshabilito el constraint: ' || r.table_name || '.' || r.constraint_name, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);

		-- SE AGREGA PARA ESCRIBIR EN EL LOG CUANDO FALLE AL BAJAR UNA FK

    EXCEPTION
        WHEN OTHERS THEN
			v_retry_count := v_retry_count + 1;
			v_time3 := SYSTIMESTAMP;
			v_time_tot2 := SUBSTR(TO_CHAR(v_time3 - v_time2, 'SSSS.FF'), 9, 8);
                
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY, MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id, (SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'ERROR al deshabilitar constraint: ' || r.table_name || '.' || r.constraint_name || ', INTENTO: ' || v_retry_count || ' de 3','PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);
        
        EXECUTE IMMEDIATE 'COMMIT';
		
		IF v_retry_count < v_max_retries THEN
           -- Pausa de 2 segundos antes del siguiente reintento
           sys.dbms_session.sleep(2); 
        ELSE

		-- DETIENE LA EJECUCIÓN PARA EVITAR DEMORAS EN EL BORRADO SI NO DESHABILITA ALGUNA FK:
		
		RAISE_APPLICATION_ERROR(-20001, 'Error crítico procesando FK en tabla ' || r.table_name || ': ' || SQLERRM);
        
		END IF;
    END;
    END LOOP;
 END LOOP;    
          
END;

sys.dbms_session.sleep(1);

        PRC_WRITE_ERROR_LOG_DATA_CLEANING(v_proc_id,sysdate,NULL,v_fecha_dep,NULL,'Se deshabilitaron los constraints en BD: ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);

----------------------------------------------------------------------
--- INICIA EL BLOQUE DE UPDATE Y DEPURACION DE DATOS DE PRODUCCIÓN ---
----------------------------------------------------------------------

sys.dbms_session.sleep(1);
        
-- UPDATE DE CONSUMOS (ARN) DE LA TABLA IPM:

        --v_time2 := systimestamp;
		--
        --EXECUTE IMMEDIATE 'UPDATE ' || v_sche_ori || '.CONSUMOS C SET ARN = (SELECT  DATOS_REFERENCIA_ADQUIRIENTE FROM ' || v_sche_ori || '.IPM I WHERE I.ID_CONSUMO = C.ID_CONSUMO AND ID_ESTADO = 0 AND ROWNUM = 1)
        --                   WHERE ID_CONSUMO IN (SELECT  ID_CONSUMO FROM ' || v_sche_ori || '.IPM WHERE ID_IPM_FILE IN (SELECT  ID_IPM_FILE FROM ' || v_sche_ori || '.IPM_FILE
        --                   WHERE TRUNC(FECHA_CARGA) <= ' || v_date_dep || ' AND TRUNC(FECHA_CARGA) > '|| v_date_dep1 || ') AND ID_CONSUMO IS NOT NULL AND ID_ESTADO = 0)';
		--  
		--	v_num_row := SQL%rowcount;
		--
        --v_time3 := systimestamp;
        --
        --v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		--
		--INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros actualizados en CONSUMOS de IPM: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);
		--
		--EXECUTE IMMEDIATE 'COMMIT';
		
-- UPDATE DE CONSUMOS (ARN) DE LA TABLA CTF_VISA:

        --v_time2 := systimestamp;
		--
        --EXECUTE IMMEDIATE 'UPDATE ' || v_sche_ori || '.CONSUMOS C SET ARN = (SELECT  DATOS_REFERENCIA_ADQUIRENTE FROM ' || v_sche_ori || '.CTF_VISA I WHERE I.ID_CONSUMO = C.ID_CONSUMO AND TCR = 0 AND ROWNUM = 1)
        --                  WHERE ID_CONSUMO IN (SELECT  ID_CONSUMO FROM ' || v_sche_ori || '.CTF_VISA WHERE ID_CTF_FILE IN (SELECT  ID_CTF_FILE FROM ' || v_sche_ori || '.CTF_FILE_VISA
        --                  WHERE TRUNC(FECHA_CARGA) <= ' || v_date_dep || ' AND TRUNC(FECHA_CARGA) > '|| v_date_dep1 || ') AND ID_CONSUMO IS NOT NULL)';
		--  
		--	v_num_row := SQL%rowcount;
		--	
		--v_time3 := systimestamp;
		--
		--v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		--
		--INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a '  || v_fecha_dep ||  ' numero de registros actualizados en CONSUMOS de CTF_VISA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);
		--
		--EXECUTE IMMEDIATE 'COMMIT';

-- DELETE DE LA TABLA TQR4_ADQUIRENCIA 

	v_time2 := systimestamp;
		
BEGIN

    declare
    
         CURSOR CUR_ID_CONSUMOS 
         is
         SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM CONSUMOS C WHERE TRUNC(C.FECHA_OPER) <= v_fecha_dep;
         
         TYPE lv_tbl IS TABLE OF number;
              registros lv_tbl;
         
        begin
         
        open CUR_ID_CONSUMOS;

            fetch CUR_ID_CONSUMOS BULK COLLECT INTO registros;

            FORALL i IN registros.FIRST .. registros.LAST
            
            DELETE FROM TQR4_ADQUIRENCIA WHERE ID_CONSUMO = registros(i);
                
            v_num_row := SQL%rowcount;
            
    v_time3 := systimestamp;
            
    v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en TQR4_ADQUIRENCIA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
        
        close CUR_ID_CONSUMOS;
    END;
END;  

-- DELETE DE LA TABLA IPM:

    v_time2 := systimestamp;

    -- CODIGO ORIGINAL
    -- BEGIN
    --
    --     declare
    --
    --          CURSOR CUR_DEL_IPM
    --          is
    --          SELECT /*+ PARALLEL (2) */ D.ID_IPM_FILE FROM IPM D WHERE D.ID_IPM_FILE IN (SELECT /*+ PARALLEL (2) */ I.ID_IPM_FILE FROM IPM_file I WHERE TRUNC(I.FECHA_CARGA) <= v_fecha_dep OR I.FECHA_CARGA IS NULL)
    --                                                            OR D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM CONSUMOS C WHERE TRUNC(C.FECHA_OPER) <= v_fecha_dep);
    --
    --          TYPE lv_tbl IS TABLE OF number;
    --               registros lv_tbl;
    --
    --         begin
    --
    --         open CUR_DEL_IPM;
    --
    --             fetch CUR_DEL_IPM BULK COLLECT INTO registros;
    --
    --             FORALL i IN registros.FIRST .. registros.LAST
    --
    --             DELETE FROM IPM WHERE ID_IPM_FILE=registros(i);
    --
    --             v_num_row := SQL%rowcount;
    --
    --         close CUR_DEL_IPM;
    --     END;
    -- END;

    -- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
    -- El borrado general excluye los grupos 11 y 12; sus cuotas se depuran en el bloque especifico posterior.
    EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.IPM D WHERE D.ID_IPM_FILE IN (SELECT /*+ PARALLEL (2) */ I.ID_IPM_FILE FROM ' || v_sche_ori || '.IPM_FILE I WHERE TRUNC(I.FECHA_CARGA) <= ' || v_date_dep || ' OR I.FECHA_CARGA IS NULL)
                                                              OR D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM ' || v_sche_ori || '.CONSUMOS C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ' AND C.ID_GRUPO_TRANSACCION NOT IN (11,12))';

    v_num_row := SQL%rowcount;

    v_time3 := systimestamp;

    v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

    INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a '  || v_fecha_dep ||  ' numero de registros eliminados en IPM: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);

    EXECUTE IMMEDIATE 'COMMIT';

-- UPDATE DE LA TABLA IPM - ID_IPM_ORIGEN:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'UPDATE ' || v_sche_ori || '.IPM SET ID_IPM_ORIGEN = NULL WHERE ID_IPM_ORIGEN IS NOT NULL AND ID_IPM_FILE IN (SELECT ID_IPM_FILE FROM ' || v_sche_ori || '.IPM_FILE WHERE TRUNC(FECHA_CARGA) BETWEEN ' || v_date_dep || ' AND ' || v_date_dep3 || ')';
        
            v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
        
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
        
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep ||  ' numero de registros ID_IPM_ORIGEN actualizados en IPM: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';
		
-- DELETE DE LA TABLA IPM_FILE:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.IPM_FILE WHERE TRUNC(FECHA_CARGA) <= ' || v_date_dep || ' OR TRUNC(FECHA_CARGA) IS NULL';
		  
			v_num_row := SQL%rowcount;
			
		v_time3 := systimestamp;
		
		v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a '  || v_fecha_dep ||  ' numero de registros eliminados en IPM_FILE: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';

-- DELETE DE LA TABLA CTF_VISA:

    v_time2 := systimestamp;

    -- CODIGO ORIGINAL
    -- BEGIN
    --
    --     declare
    --
    --          CURSOR CUR_DEL_CTF_VISA
    --          is
    --          SELECT /*+ PARALLEL (2) */ D.ID_CTF_FILE FROM CTF_VISA D WHERE D.ID_CTF_FILE IN (SELECT /*+ PARALLEL (2) */ I.ID_CTF_FILE FROM CTF_FILE_VISA I WHERE TRUNC(I.FECHA_CARGA) <= v_fecha_dep OR I.FECHA_CARGA IS NULL)
    --                                                                 OR D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM CONSUMOS C WHERE TRUNC(C.FECHA_OPER) <= v_fecha_dep);
    --
    --          TYPE lv_tbl IS TABLE OF number;
    --               registros lv_tbl;
    --
    --         begin
    --
    --         open CUR_DEL_CTF_VISA;
    --
    --             fetch CUR_DEL_CTF_VISA BULK COLLECT INTO registros;
    --
    --             FORALL i IN registros.FIRST .. registros.LAST
    --
    --             DELETE FROM CTF_VISA WHERE ID_CTF_FILE=registros(i);
    --
    --             v_num_row := SQL%rowcount;
    --
    --         close CUR_DEL_CTF_VISA;
    --     END;
    -- END;

    -- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
    -- El borrado general excluye los grupos 11 y 12; sus cuotas se depuran en el bloque especifico posterior.
    EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.CTF_VISA D WHERE D.ID_CTF_FILE IN (SELECT /*+ PARALLEL (2) */ I.ID_CTF_FILE FROM ' || v_sche_ori || '.CTF_FILE_VISA I WHERE TRUNC(I.FECHA_CARGA) <= ' || v_date_dep || ' OR I.FECHA_CARGA IS NULL
                                                             OR D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM ' || v_sche_ori || '.CONSUMOS C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ' AND C.ID_GRUPO_TRANSACCION NOT IN (11,12))';

    v_num_row := SQL%rowcount;

    v_time3 := systimestamp;

    v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

    INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a '  || v_fecha_dep ||  ' numero de registros eliminados en CTF_VISA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);

    EXECUTE IMMEDIATE 'COMMIT';

-- DELETE DE LA TABLA CTF_FILE_VISA:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.CTF_FILE_VISA WHERE TRUNC(FECHA_CARGA) <= ' || v_date_dep || ' OR TRUNC(FECHA_CARGA) IS NULL';
		  
			v_num_row := SQL%rowcount;
			
		v_time3 := systimestamp;
		
		v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a '  || v_fecha_dep ||  ' numero de registros eliminados en CTF_FILE_VISA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';

-- DELETE DE LA TABLA IN_T464:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.IN_T464 WHERE ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ ID_CONSUMO FROM ' || v_sche_ori || '.IN_T464 WHERE TRUNC(ORIGINAL_SETTLEMENT_DATE) <= ' || v_date_dep || ' )
                           OR ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ ID_CONSUMO FROM ' || v_sche_ori || '.CONSUMOS WHERE TRUNC(FECHA_OPER) <= ' || v_date_dep || ')';
		  
			v_num_row := SQL%rowcount;
			
		v_time3 := systimestamp;
		
		v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a '  || v_fecha_dep ||  ' numero de registros eliminados en IN_T464: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';
		
-- UPDATE DE LA TABLA PROMOCION_LOG - ID_IPM:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'UPDATE ' || v_sche_ori || '.PROMOCION_LOG SET ID_IPM = NULL WHERE ID_IPM IS NOT NULL AND ID_IPM NOT IN (SELECT /*+ PARALLEL (2) */ ID_IPM FROM ' || v_sche_ori || '.IPM)';
		  
			v_num_row := SQL%rowcount;
			
		v_time3 := systimestamp;
		
		v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a '  || v_fecha_dep ||  ' numero de registros ID_IPM actualizados en PROMOCION_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';

-- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
-- AGREGADO POR CUOTA A CUOTA: REGISTROS QUE YA CUMPLIERON SU CICLO.

-- DELETE DE LA TABLA IPM CUOTA_A_CUOTA:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.IPM D WHERE D.ID_IPM_FILE IN (SELECT /*+ PARALLEL (2) */ I.ID_IPM_FILE FROM ' || v_sche_ori || '.IPM_FILE I WHERE TRUNC(I.FECHA_CARGA) <= ' || v_date_dep || ' OR I.FECHA_CARGA IS NULL
                                                                  OR D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM ' || v_sche_ori || '.CONSUMOS C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ' AND C.ID_GRUPO_TRANSACCION IN (11,12) AND C.NRO_CUOTA = C.CUOTAS AND C.FECHA_PRESENT < ' || v_date_dep || ' ))';

        v_num_row := SQL%rowcount;

        v_time3 := systimestamp;

        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados por cuota cuota en IPM: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);

        EXECUTE IMMEDIATE 'COMMIT';

-- DELETE DE LA TABLA CTF_VISA CUOTA_A_CUOTA:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.CTF_VISA D WHERE D.ID_CTF_FILE IN (SELECT /*+ PARALLEL (2) */ I.ID_CTF_FILE FROM ' || v_sche_ori || '.CTF_FILE_VISA I WHERE TRUNC(I.FECHA_CARGA) <= ' || v_date_dep || ' OR I.FECHA_CARGA IS NULL
                                                                OR D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM ' || v_sche_ori || '.CONSUMOS C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ' AND C.ID_GRUPO_TRANSACCION IN (11,12) AND C.NRO_CUOTA = C.CUOTAS AND C.FECHA_PRESENT < ' || v_date_dep || ' ))';

        v_num_row := SQL%rowcount;

        v_time3 := systimestamp;

        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados por cuota cuota en CTF_VISA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);

        EXECUTE IMMEDIATE 'COMMIT';

sys.dbms_session.sleep(1);

--AGREGADO DEPURACION DE LA TABLA CLEARING		
-- DELETE DE LA TABLA CLEARING:

sys.dbms_session.sleep(1);

v_time2 := systimestamp;

	BEGIN

    declare
            
         CURSOR CUR_DEL_CLEARING 
         is
        SELECT /*+ PARALLEL (2) */ ID_CLEARING FROM CLEARING WHERE FECHA_SETTLEMENT <= v_fecha_dep;


         TYPE lv_tbl IS TABLE OF number;
              registros lv_tbl;
         
        begin
         
        open CUR_DEL_CLEARING;

            fetch CUR_DEL_CLEARING BULK COLLECT INTO registros;
            
            FORALL i IN registros.FIRST .. registros.LAST
            
            DELETE FROM CLEARING WHERE ID_CLEARING=registros(i);
                
            v_num_row := SQL%rowcount;
     
    v_time3 := systimestamp;
    
    v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a '  || v_fecha_dep ||  ' numero de registros eliminados en CLEARING: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
        
        close CUR_DEL_CLEARING;
    END;
END;  

sys.dbms_session.sleep(1);
 
--DELETE DE LA TABLA QUEUE_PRESENTATION_INCOMING (Por Fecha), Tabla agregada despues de un analisis a la cantidad de registros que tenia y una charla con los analistas funcionales

        v_time2 := systimestamp;
        

        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.QUEUE_PRESENTATION_INCOMING 
                            WHERE TRUNC(FECHA_AUTORIZACION) <= ' || v_date_dep;

            v_num_row := SQL%rowcount;
            
        v_time3 := systimestamp;
        
        v_time_tot2 := substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a '  || v_fecha_dep ||  ' numero de registros eliminados en QUEUE_PRESENTATION_INCOMING: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);

        EXECUTE IMMEDIATE 'COMMIT';	
    
-------------------------------------------------------------
------- SE HABILITAN LOS CONSTRAINTS EN LA BD PROD  ---------
-------------------------------------------------------------

BEGIN

    FOR r IN (SELECT owner, table_name, constraint_name FROM DBA_CONSTRAINTS WHERE owner = v_sche_ori
                AND table_name IN (
                                   'CTF_FILE_VISA',
                                   'CTF_VISA',
                                   'IN_T464',
                                   'IPM',
                                   'IPM_FILE',
                                   --'PROMOCION_LOG',
								   'TQR4_ADQUIRENCIA',
								   'GESTION_IPM',
                                   'GESTION_CONTRACARGO',
                                   'CLEARING',
                                   'QUEUE_PRESENTATION_INCOMING'
                                    )
                       AND constraint_type = 'R'
              ORDER BY table_name ASC)
    LOOP
		v_retry_count := 0;
        v_success := FALSE;

        WHILE v_retry_count < v_max_retries AND NOT v_success LOOP    
    BEGIN
    
        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE   'ALTER TABLE ' || r.owner|| '.' || r.table_name || ' ENABLE NOVALIDATE CONSTRAINT ' || r.constraint_name;
        
        v_time3 := systimestamp;
        
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		v_success := TRUE; -- Si llega aquí, fue exitoso
        
        --INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Se habilito el constraint: ' || r.table_name || '.' || r.constraint_name, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);

 		-- SE AGREGA PARA ESCRIBIR EN EL LOG CUANDO FALLE AL LEVANTAR UNA FK

    EXCEPTION
        WHEN OTHERS THEN
        v_retry_count := v_retry_count + 1;
        v_time3 := SYSTIMESTAMP;
		v_time_tot2 := SUBSTR(TO_CHAR(v_time3 - v_time2, 'SSSS.FF'), 9, 8);
                
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id, (SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'ERROR al habilitar constraint: ' || r.table_name || '.' || r.constraint_name || ', INTENTO: ' || v_retry_count || ' de 3','PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);
        
        EXECUTE IMMEDIATE 'COMMIT';
 		
		IF v_retry_count < v_max_retries THEN
            sys.dbms_session.sleep(2);
        ELSE
            -- Si agotó los reintentos, lanzamos el error crítico
            RAISE_APPLICATION_ERROR(-20001, 'Error crítico tras ' || v_max_retries || ' intentos en tabla ' || r.table_name || ': ' || SQLERRM);
        END IF;
    END;
        END LOOP;
    END LOOP;
    
sys.dbms_session.sleep(2);
        
END;

sys.dbms_session.sleep(2);
        
        PRC_WRITE_ERROR_LOG_DATA_CLEANING(v_proc_id,sysdate,NULL,v_fecha_dep,NULL,'Se habilitaron los constraints en: ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);

sys.dbms_session.sleep(2);

v_time4 := systimestamp;

    v_time_tot1:= substr(TO_CHAR(v_time4-v_time1,'SSSS.FF'),9,8);
    
            PRC_WRITE_ERROR_LOG_DATA_CLEANING(v_proc_id,sysdate,v_time_tot1,v_fecha_dep,NULL,'Fin del proceso de actualizacion y depuracion de registros en la BD: ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);
    
    ELSE PRC_WRITE_ERROR_LOG_DATA_CLEANING(v_proc_id,sysdate,NULL,v_fecha_dep,NULL,'SE SUPERO LA FECHA LIMITE (' || v_fecha_limit || ') DE 6 MESES PARA MANTENER LOS DATOS EN PROD, INTENTE CON UN RANGO DE FECHAS MENOR A LA FECHA LIMITE INDICADA', 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2',NULL,NULL,NULL);
    
END IF; 

------------------------------------------------------------------
-- LOGUEO DE ERRORES EN LA TABLA SOPORTEDBA.LOG_DEPURADORES --
------------------------------------------------------------------

    EXCEPTION
        WHEN OTHERS
        THEN
           
            PRC_WRITE_ERROR_LOG_DATA_CLEANING(v_proc_id,sysdate,NULL,NULL,NULL,SQLERRM, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_2', SQLCODE, dbms_utility.format_error_backtrace, dbms_utility.format_error_stack);
    END;
            
END;
/


CREATE OR REPLACE PROCEDURE SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_CLEANING_1 (sche_ori IN VARCHAR2, fecha_depuracion IN VARCHAR2, proc_id IN NUMBER)
-- STORED PROCEDURE USADO PARA REALIZAR EL PROCESO DE DEPURACIÓN DE DATOS EN LAS BD DE WOLFGANG ADQUIRENCIA
-- IMPORTANTE: ESTE PROCESO DEPENDE DE LA PREVIA EJECUCION DEL SP PRC_WFGADQ_ENTITY_DATA_CLEANING_2 O DEBE SER EJECUTADO CON FECHA DE DEPURACION MENOR A LA USADA EN EL SP MENCIONADO
-- TOMA LA FECHA  DE DEPURACION QUE SE LE INDICA, DEJANDO EN LINEA 6 MESES
-- PARAMETROS DE ENTRADA:
--  sche_ori: esquema origen (PROD_ENTIDAD700, PROD_ENTIDAD701 y PROD_ENTIDAD702)
--  fecha_depuracion: fecha de depuración en formato DD/MM/YYYY
--  proc_id:id del proceso (cuando se ejecuta de manera automatica)
--  EJEMPLO para la ejecución: EXEC SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_CLEANING_1('PROD_ENTIDAD702','31/12/2021');
IS
BEGIN
        EXECUTE IMMEDIATE 'alter session set current_schema = SOPORTEDBA';
        EXECUTE IMMEDIATE 'alter session set nls_date_format=''DD/MM/RRRR''';
        EXECUTE IMMEDIATE 'alter session set nls_timestamp_format=''DD/MM/RRRR''';
DECLARE        
		v_max_retries  	CONSTANT NUMBER := 3;												-- CANTIDAD DE REINTENTOS EN CASO DE FALLAS AL DESHABILITAR / HABILITAR UNA FK
		v_retry_count 	NUMBER;																-- NUMERO DE INTENTO
		v_success     	BOOLEAN;															-- VARIABLE PARA VALIDAR SI FUE EXITOSO O NO EL DESHABILITAR / HABILITAR UNA FK
        v_code          NUMBER;                                                             -- CODIGO DE ERROR
        v_errm          VARCHAR2 (300);                                                     -- MENSAJE DE ERROR
        v_time1         TIMESTAMP;                                                          -- TIEMPO DE EJECUCION 1 INICIAL DEL PROCESO DE DEPURACION
        v_time2         TIMESTAMP;                                                          -- TIEMPO DE EJECUCION 2 INICIAL DEL SUBPROCESO
        v_time3         TIMESTAMP;                                                          -- TIEMPO DE EJECUCION 3 FINAL DEL SUBPROCESO
        v_time4         TIMESTAMP;                                                          -- TIEMPO DE EJECUCION 4 FINAL DEL PROCESO DE DEPURACION
        v_time_tot1     VARCHAR2 (10);                                                      -- TIEMPO TOTAL DE EJECUCION DEL PROCESO DE DEPURACION
        v_time_tot2     VARCHAR2 (10);                                                      -- TIEMPO TOTAL DE EJECUCION DEL SUB PROCESO DE DEPURACION
        v_sche_ori      VARCHAR2 (20) := sche_ori;                                          -- ESQUEMA A DEPURAR
        v_fecha_dep     DATE:= fecha_depuracion;                                            -- FECHA DE DEPURACION
        v_fecha_limit   DATE;                                                               -- FECHA QUE DEFINE LA FECHA DE LOS DATOS QUE VAN A QUEDAR EN LINEA
        v_fecha_ini3    DATE:= v_fecha_dep +1;              
        v_date_ini3     VARCHAR2(15):= '''' || v_fecha_ini3 || '''';                
        v_fecha_dep6    DATE;                                                               -- FECHA DE DEPURACION + 6 MESES
        v_date_dep6     VARCHAR2(15);               
		v_date_dep      VARCHAR2(15):= '''' || v_fecha_dep || '''';                         -- FECHA DE DEPURACION EN FORMATO 'DD/MM/YYYY'
        v_num_row 	    NUMBER;                                                             -- NUMERO DE REGISTROS AFECTADOS EN LA SENTENCIA
        v_ult_proc      DATE;                                                               -- FECHA DE LA ULTIMA EJECUCION DE PRC_WFGADQ_ENTITY_DATA_CLEANING_2
        v_proc_id       NUMBER:= proc_id;                                                   -- ID DEL PROCESO
        
    BEGIN
        
        -- SE DEFINE LA FECHA DE LA DATA QUE VA A QUEDAR EN LINEA (6 MESES):
        EXECUTE IMMEDIATE 'SELECT ADD_MONTHS(TRUNC(SYSDATE),-6) FROM DUAL' INTO v_fecha_limit;
        -- SE CALCULA LA FECHA DE DEPURACION +6 MESES:
        EXECUTE IMMEDIATE 'SELECT ADD_MONTHS(TO_DATE(''' || v_fecha_dep || ''',''DD/MM/RRRR''),+6) FROM DUAL' INTO v_fecha_dep6;
        v_date_dep6:= '''' || v_fecha_dep6 || '''';                         -- FECHA DE DEPURACION + 6 MESES EN FORMATO 'DD/MM/YYYY'
        -- SE OBTIENE LA FECHA DE LA ULTIMA EJECUCION DE PRC_WFGADQ_ENTITY_DATA_CLEANING_2:
        EXECUTE IMMEDIATE 'SELECT MAX(TO_DATE(CLEANING_DATE,''DD/MM/RRRR'')) FROM LOG_DEPURADORES WHERE SP_NAME=''PRC_WFGADQ_ENTITY_DATA_CLEANING_2'' AND CLEANING_DATE IS NOT NULL' INTO v_ult_proc;

IF v_fecha_dep <= v_fecha_limit AND v_fecha_dep <= v_ult_proc THEN

-------------------------------------------------------------
------- SE DESHABILITAN LOS CONSTRAINTS EN LA BD PROD  ------
-------------------------------------------------------------

           PRC_WRITE_ERROR_LOG_DATA_CLEANING(v_proc_id,sysdate,NULL,v_fecha_dep,NULL,'Se inicia el proceso de actualizacion y depuracion de registros en la BD: ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);

sys.dbms_session.sleep(2);

v_time1 := systimestamp;

BEGIN

    FOR r IN (SELECT owner, table_name, constraint_name FROM DBA_CONSTRAINTS WHERE owner = v_sche_ori
                AND table_name IN ('AUTORIZACION',
                                   'AUTORIZACION_ADQUIRENTE_LOG',
                                   'AUTORIZ_INTENTOS_REVERSOS',
                                   'AUTORIZACION_REVERSOS_COLA',
								   'AUTORIZACION_RT',
                                   'COMERCIOS_LIQ_CABECERA',
                                   'COMERCIOS_LIQ_CONCEPTOS',
                                   'COMERCIOS_LIQ_DETALLES',
                                   'COMERCIOS_LIQ_IMPUESTOS',
                                   'COMERCIOS_LIQ_PLAZOS',
                                   'IN_T464',
                                   'CONSUMOS',
                                   'CONSUMOS_CUOTAS',
                                   'CONSUMOS_DATOS_ADICIONALES',
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
                                   'CONSUMOS_CARGOS_ADICIONALES',
                                   'AJUSTES_COMERCIOS',
                                   'AJUSTES_SOCIOS',
                                   'AUTORIZACION_CONSULTA',
                                   'AUTORIZACION_EMISOR_LOG',
                                   'AUTORIZACION_PAYMENT',
                                   'NOVEDADES_SAFE',
                                   'PAGOS',
                                   -- CODIGO ADAPTADO A ENTIDAD 702 - CONSTRAINTS - 21/07/2026
                                   'CLEARING',
                                   'QUEUE_PRESENTATION_INCOMING')
                       AND constraint_type = 'R'
              ORDER BY table_name ASC)
    
    LOOP
		v_retry_count := 0;
        v_success := FALSE;

        WHILE v_retry_count < v_max_retries AND NOT v_success LOOP
	BEGIN
        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE   'ALTER TABLE ' || r.owner|| '.' || r.table_name || ' DISABLE CONSTRAINT ' || r.constraint_name;
        
        v_time3 := systimestamp;
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		v_success := TRUE; -- Si llega aquí, fue exitoso
        
        -- INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,v_fecha_dep,NULL,'Se deshabilito el constraint: ' || r.table_name || '.' || r.constraint_name, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
		
	-- SE AGREGA PARA ESCRIBIR EN EL LOG CUANDO FALLE AL BAJAR UNA FK

    EXCEPTION
        WHEN OTHERS THEN
			v_retry_count := v_retry_count + 1;
			v_time3 := SYSTIMESTAMP;
			v_time_tot2 := SUBSTR(TO_CHAR(v_time3 - v_time2, 'SSSS.FF'), 9, 8);
                
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY, MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id, (SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'ERROR al deshabilitar constraint: ' || r.table_name || '.' || r.constraint_name || ', INTENTO: ' || v_retry_count || ' de 3','PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
        
        EXECUTE IMMEDIATE 'COMMIT';
		
		IF v_retry_count < v_max_retries THEN
           -- Pausa de 2 segundos antes del siguiente reintento
           sys.dbms_session.sleep(2); 
        ELSE

		-- DETIENE LA EJECUCIÓN PARA EVITAR DEMORAS EN EL BORRADO SI NO DESHABILITA ALGUNA FK:
		
		RAISE_APPLICATION_ERROR(-20001, 'Error crítico procesando FK en tabla ' || r.table_name || ': ' || SQLERRM);
        
		END IF;
    END;
    END LOOP;
  END LOOP;
END;

sys.dbms_session.sleep(1);

        PRC_WRITE_ERROR_LOG_DATA_CLEANING(v_proc_id,sysdate, NULL, v_fecha_dep,NULL,'Se deshabilitan los constraints en BD PROD: ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);

-------------------------------------------------------------
--- INICIA EL BLOQUE DE DEPURACION DE DATOS DE PRODUCCIÓN ---
-------------------------------------------------------------

sys.dbms_session.sleep(2);

-- DELETE DE LAS TABLAS PROMOCION_LOG, CONSUMOS_DATOS_ADICIONALES, CONSUMOS_CARGOS_ADICIONALES, CONSUMOS_CUOTAS, RETENCIONES_CONSUMOS, PRESENTACIONES, TC33A:

BEGIN

    declare
    
         CURSOR CUR_ID_CONSUMOS 
         is
         -- CODIGO ORIGINAL
         -- SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM CONSUMOS C WHERE TRUNC(C.FECHA_OPER) <= v_fecha_dep;
         -- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
         SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM CONSUMOS C WHERE TRUNC(C.FECHA_OPER) <= v_fecha_dep AND C.ID_GRUPO_TRANSACCION NOT IN (11,12);
         
         TYPE lv_tbl IS TABLE OF number;
              registros lv_tbl;
         
        begin
         
        open CUR_ID_CONSUMOS;

            fetch CUR_ID_CONSUMOS BULK COLLECT INTO registros;
            
            v_time2 := systimestamp;
            
            FORALL i IN registros.FIRST .. registros.LAST
            
            -- DELETE DE PROMOCION_LOG
            DELETE FROM PROMOCION_LOG WHERE ID_CONSUMO = registros(i);
                
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
        
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en PROMOCION_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
            
            v_time2 := systimestamp;
            
            FORALL i IN registros.FIRST .. registros.LAST
            
            -- DELETE DE CONSUMOS_DATOS_ADICIONALES
            DELETE FROM CONSUMOS_DATOS_ADICIONALES WHERE ID_CONSUMO = registros(i);
                
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
        
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en CONSUMOS_DATOS_ADICIONALES: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
            
            v_time2 := systimestamp;
             
            FORALL i IN registros.FIRST .. registros.LAST
            
            -- DELETE DE CONSUMOS_CARGOS_ADICIONALES
            DELETE FROM CONSUMOS_CARGOS_ADICIONALES WHERE ID_CONSUMO = registros(i);
                
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
        
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en CONSUMOS_CARGOS_ADICIONALES: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
            
            v_time2 := systimestamp;
            FORALL i IN registros.FIRST .. registros.LAST
            
            -- DELETE DE CONSUMOS_CUOTAS
            DELETE FROM CONSUMOS_CUOTAS WHERE ID_CONSUMO = registros(i);
                
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
        
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en CONSUMOS_CUOTAS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
            
            v_time2 := systimestamp;
            
            FORALL i IN registros.FIRST .. registros.LAST
            
            -- DELETE DE RETENCIONES_CONSUMOS
            DELETE FROM RETENCIONES_CONSUMOS WHERE ID_CONSUMO = registros(i);
                
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
        
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en RETENCIONES_CONSUMOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
            
            v_time2 := systimestamp;
              
            FORALL i IN registros.FIRST .. registros.LAST
            
            -- DELETE DE PRESENTACIONES
            DELETE FROM PRESENTACIONES WHERE ID_CONSUMO = registros(i);
                
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
            
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en PRESENTACIONES: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
            
            v_time2 := systimestamp;
            
            FORALL i IN registros.FIRST .. registros.LAST
            
            -- DELETE DE TC33A
            DELETE FROM TC33A WHERE ID_CONSUMO = registros(i);
                
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
        
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en TC33A: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
                    
        close CUR_ID_CONSUMOS;
    END;
END;

-- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
-- LA AUTORIZACION SE ELIMINA ANTES QUE LOS CONSUMOS PARA CONSERVAR LA REFERENCIA NECESARIA.
-- DELETE DE AUTORIZACIONES ASOCIADAS A CUOTAS QUE YA COMPLETARON SU CICLO:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.AUTORIZACION D WHERE D.ID_AUTORIZACION IN (SELECT C.ID_AUTORIZACION FROM ' || v_sche_ori || '.CONSUMOS C WHERE C.ID_GRUPO_TRANSACCION IN (11,12) AND C.NRO_CUOTA = C.CUOTAS AND C.FECHA_PRESENT <= ' || v_date_dep || ')';

        v_num_row := SQL%rowcount;
        v_time3 := systimestamp;
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados por cuota cuota en AUTORIZACION: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);

        EXECUTE IMMEDIATE 'COMMIT';

-- DELETE DE CONSUMOS CUOTA A CUOTA QUE YA COMPLETARON SU CICLO Y DE SUS TABLAS DEPENDIENTES:

BEGIN

    declare

         CURSOR CUR_ID_CONSUMOS_CUOTA
         is
         SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM CONSUMOS C WHERE TRUNC(C.FECHA_OPER) <= v_fecha_dep AND C.ID_GRUPO_TRANSACCION IN (11,12) AND C.NRO_CUOTA = C.CUOTAS AND C.FECHA_PRESENT <= v_fecha_dep;

         TYPE lv_tbl_cuota IS TABLE OF number;
              registros_cuota lv_tbl_cuota;

    begin

        open CUR_ID_CONSUMOS_CUOTA;
        fetch CUR_ID_CONSUMOS_CUOTA BULK COLLECT INTO registros_cuota;

        -- EVITA EJECUTAR FORALL CON LIMITES NULOS CUANDO NO HAY CUOTAS FINALIZADAS.
        IF registros_cuota.COUNT > 0 THEN

            v_time2 := systimestamp;

            FORALL i IN registros_cuota.FIRST .. registros_cuota.LAST
            DELETE FROM PROMOCION_LOG WHERE ID_CONSUMO = registros_cuota(i);

            v_num_row := SQL%rowcount;
            v_time3 := systimestamp;
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados por cuota cuota en PROMOCION_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);

            EXECUTE IMMEDIATE 'COMMIT';

            v_time2 := systimestamp;

            FORALL i IN registros_cuota.FIRST .. registros_cuota.LAST
            DELETE FROM CONSUMOS_DATOS_ADICIONALES WHERE ID_CONSUMO = registros_cuota(i);

            v_num_row := SQL%rowcount;
            v_time3 := systimestamp;
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados por cuota cuota en CONSUMOS_DATOS_ADICIONALES: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);

            EXECUTE IMMEDIATE 'COMMIT';

            v_time2 := systimestamp;

            FORALL i IN registros_cuota.FIRST .. registros_cuota.LAST
            DELETE FROM CONSUMOS_CARGOS_ADICIONALES WHERE ID_CONSUMO = registros_cuota(i);

            v_num_row := SQL%rowcount;
            v_time3 := systimestamp;
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados por cuota cuota en CONSUMOS_CARGOS_ADICIONALES: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);

            EXECUTE IMMEDIATE 'COMMIT';

            v_time2 := systimestamp;

            FORALL i IN registros_cuota.FIRST .. registros_cuota.LAST
            DELETE FROM CONSUMOS_CUOTAS WHERE ID_CONSUMO = registros_cuota(i);

            v_num_row := SQL%rowcount;
            v_time3 := systimestamp;
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados por cuota cuota en CONSUMOS_CUOTAS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);

            EXECUTE IMMEDIATE 'COMMIT';

            v_time2 := systimestamp;

            FORALL i IN registros_cuota.FIRST .. registros_cuota.LAST
            DELETE FROM CONSUMOS WHERE ID_CONSUMO = registros_cuota(i);

            v_num_row := SQL%rowcount;
            v_time3 := systimestamp;
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados por cuota cuota en CONSUMOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);

            EXECUTE IMMEDIATE 'COMMIT';

        END IF;

        close CUR_ID_CONSUMOS_CUOTA;

    END;
END;

-- DELETE DE LA TABLA COMERCIOS_LIQ_DETALLES:

        v_time2 := systimestamp;
        
        -- CODIGO ORIGINAL
        -- EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.COMERCIOS_LIQ_DETALLES D WHERE D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ S.ID_CONSUMO FROM ' || v_sche_ori || '.CONSUMOS S WHERE TRUNC (S.FECHA_OPER) <= ' || v_date_dep || ')';
        -- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.COMERCIOS_LIQ_DETALLES D WHERE (D.NRO_LIQUIDACION, D.ID_COMERCIO_CENTRAL) IN (SELECT C.NRO_LIQUIDACION, C.ID_COMERCIO_CENTRAL FROM ' || v_sche_ori || '.COMERCIOS_LIQ_CABECERA C WHERE TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= ' || v_date_dep || ')';
		  
               v_num_row := SQL%rowcount;
               
               v_time3 := systimestamp;
               
               v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en COMERCIOS_LIQ_DETALLES: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';

-- DELETE DE LA TABLA COMERCIOS_LIQ_CONCEPTOS:

v_time2 := systimestamp;

BEGIN

    declare
            
         CURSOR CUR_DEL_COM_LIQ_X 
         is
         SELECT /*+ PARALLEL (2) */ D.NRO_LIQUIDACION, D.ID_COMERCIO_CENTRAL FROM COMERCIOS_LIQ_CONCEPTOS D WHERE exists(select 1 FROM COMERCIOS_LIQ_CABECERA C WHERE D.NRO_LIQUIDACION = C.NRO_LIQUIDACION AND D.ID_COMERCIO_CENTRAL=C.ID_COMERCIO_CENTRAL AND TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= v_fecha_dep);
         
         TYPE lv_tbl IS TABLE OF CUR_DEL_COM_LIQ_X%ROWTYPE;
              registros lv_tbl;
         
        begin
         
        open CUR_DEL_COM_LIQ_X;

            fetch CUR_DEL_COM_LIQ_X BULK COLLECT INTO registros;
            
            FORALL i IN registros.FIRST .. registros.LAST
            
            DELETE FROM COMERCIOS_LIQ_CONCEPTOS WHERE NRO_LIQUIDACION=(registros (i).NRO_LIQUIDACION) AND ID_COMERCIO_CENTRAL=(registros (i).ID_COMERCIO_CENTRAL);
                
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
            
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en COMERCIOS_LIQ_CONCEPTOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
        
        close CUR_DEL_COM_LIQ_X;
    END;
END;  

-- DELETE DE LA TABLA COMERCIOS_LIQ_IMPUESTOS:

v_time2 := systimestamp;

BEGIN

    declare
            
         CURSOR CUR_DEL_COM_LIQ_X 
         is
         SELECT /*+ PARALLEL (2) */ D.NRO_LIQUIDACION, D.ID_COMERCIO_CENTRAL FROM COMERCIOS_LIQ_IMPUESTOS D WHERE exists(select 1 FROM COMERCIOS_LIQ_CABECERA C WHERE D.NRO_LIQUIDACION = C.NRO_LIQUIDACION AND D.ID_COMERCIO_CENTRAL=C.ID_COMERCIO_CENTRAL AND TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= v_fecha_dep);
         
         TYPE lv_tbl IS TABLE OF CUR_DEL_COM_LIQ_X%ROWTYPE;
              registros lv_tbl;
         
        begin
         
        open CUR_DEL_COM_LIQ_X;

            fetch CUR_DEL_COM_LIQ_X BULK COLLECT INTO registros;
            
            FORALL i IN registros.FIRST .. registros.LAST
            
            DELETE FROM COMERCIOS_LIQ_IMPUESTOS WHERE NRO_LIQUIDACION=(registros (i).NRO_LIQUIDACION) AND ID_COMERCIO_CENTRAL=(registros (i).ID_COMERCIO_CENTRAL);
                
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
            
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en COMERCIOS_LIQ_IMPUESTOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
        
        close CUR_DEL_COM_LIQ_X;
    END;
END;  

-- DELETE DE LA TABLA COMERCIOS_LIQ_PLAZOS:

v_time2 := systimestamp;

BEGIN

    declare
            
         CURSOR CUR_DEL_COM_LIQ_X 
         is
         SELECT /*+ PARALLEL (2) */ D.NRO_LIQUIDACION, D.ID_COMERCIO_CENTRAL FROM COMERCIOS_LIQ_PLAZOS D WHERE exists(select 1 FROM COMERCIOS_LIQ_CABECERA C WHERE D.NRO_LIQUIDACION = C.NRO_LIQUIDACION AND D.ID_COMERCIO_CENTRAL=C.ID_COMERCIO_CENTRAL AND TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= v_fecha_dep);
         
        TYPE lv_tbl IS TABLE OF CUR_DEL_COM_LIQ_X%ROWTYPE;
              registros lv_tbl;
         
        begin
         
        open CUR_DEL_COM_LIQ_X;

            fetch CUR_DEL_COM_LIQ_X BULK COLLECT INTO registros;
            
            FORALL i IN registros.FIRST .. registros.LAST
            
            DELETE FROM COMERCIOS_LIQ_PLAZOS WHERE NRO_LIQUIDACION=(registros (i).NRO_LIQUIDACION) AND ID_COMERCIO_CENTRAL=(registros (i).ID_COMERCIO_CENTRAL);
                
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
            
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en COMERCIOS_LIQ_PLAZOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
        
        close CUR_DEL_COM_LIQ_X;
    END;
END; 

-- DELETE DE LA TABLA COMERCIOS_LIQ_CABECERA:

v_time2 := systimestamp;

BEGIN

    declare
            
         CURSOR CUR_DEL_X_TABLE 
         is
         SELECT /*+ PARALLEL (2) */ NRO_LIQUIDACION, ID_COMERCIO_CENTRAL, ID_MARCA FROM COMERCIOS_LIQ_CABECERA C WHERE TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= v_fecha_dep;
         
         TYPE lv_tbl IS TABLE OF CUR_DEL_X_TABLE%ROWTYPE;
              registros lv_tbl;
         
        begin
         
        open CUR_DEL_X_TABLE;

            fetch CUR_DEL_X_TABLE BULK COLLECT INTO registros;
            
            FORALL i IN registros.FIRST .. registros.LAST
            
            DELETE FROM COMERCIOS_LIQ_CABECERA WHERE NRO_LIQUIDACION=(registros (i).NRO_LIQUIDACION) AND ID_COMERCIO_CENTRAL=(registros (i).ID_COMERCIO_CENTRAL) AND ID_MARCA=(registros (i).ID_MARCA);
                
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
            
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en COMERCIOS_LIQ_CABECERA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
        
        close CUR_DEL_X_TABLE;
    END;
END;  
        
-- DELETE DE LA TABLA AUTORIZ_INTENTOS_REVERSOS y AUTORIZACION_REVERSOS_COLA:

v_time2 := systimestamp;

BEGIN

    declare
            
         CURSOR CUR_DEL_X_TABLE 
         is
         SELECT /*+ PARALLEL (2) */ ID_AUTORIZACION_REVERSO FROM AUTORIZACION_REVERSOS_COLA WHERE TRUNC(FECHA_ALTA) <= v_fecha_dep;
         
         TYPE lv_tbl IS TABLE OF number;
              registros lv_tbl;
         
        begin
         
        open CUR_DEL_X_TABLE;

            fetch CUR_DEL_X_TABLE BULK COLLECT INTO registros;
            
            FORALL i IN registros.FIRST .. registros.LAST
            
            -- DELETE AUTORIZ_INTENTOS_REVERSOS
            DELETE FROM AUTORIZ_INTENTOS_REVERSOS WHERE ID_AUTORIZACION_REVERSO=registros(i);
                
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
            
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en AUTORIZ_INTENTOS_REVERSOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
            
            EXECUTE IMMEDIATE 'COMMIT';
            
            v_time2 := systimestamp;
            
            FORALL i IN registros.FIRST .. registros.LAST
            
            -- DELETE AUTORIZACION_REVERSOS_COLA
            DELETE FROM AUTORIZACION_REVERSOS_COLA WHERE ID_AUTORIZACION_REVERSO=registros(i);
            
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
            
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en AUTORIZACION_REVERSOS_COLA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
            
            EXECUTE IMMEDIATE 'COMMIT';
        
        close CUR_DEL_X_TABLE;
    END;
END;   

-- DELETE DE LA TABLA CONSUMOS:

        v_time2 := systimestamp;
        
        -- CODIGO ORIGINAL
        -- EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.CONSUMOS D WHERE D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM ' || v_sche_ori || '.CONSUMOS C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ')';
        -- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.CONSUMOS D WHERE D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM ' || v_sche_ori || '.CONSUMOS C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ' AND C.ID_GRUPO_TRANSACCION NOT IN (11,12))';
		  
               v_num_row := SQL%rowcount;
               
               v_time3 := systimestamp;
               
               v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en CONSUMOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';

-- DELETE DE LA TABLA COMERCIOS_LIQ_DETALLES 2:

    --    v_time2 := systimestamp;
    --    
    --    EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.COMERCIOS_LIQ_DETALLES D WHERE D.ID_CONSUMO NOT IN (SELECT /*+ PARALLEL (2) */ S.ID_CONSUMO FROM ' || v_sche_ori || '.CONSUMOS S) AND TRUNC (D.FECHA_OPER) <= ' || v_date_dep;
	--	  
    --           v_num_row := SQL%rowcount;
    --           
    --           v_time3 := systimestamp;
    --           
    --           v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
	--	
	--	INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en COMERCIOS_LIQ_DETALLES 2: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
	--	
	--	EXECUTE IMMEDIATE 'COMMIT';

-- DELETE DE LA TABLA AUTORIZACION:

        v_time2 := systimestamp;
        
        -- CODIGO ORIGINAL
        -- EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.AUTORIZACION D WHERE D.ID_AUTORIZACION IN (SELECT /*+ PARALLEL (2) */ C.ID_AUTORIZACION FROM ' || v_sche_ori || '.AUTORIZACION C WHERE TRUNC(C.FECHA_AUTORIZACION) <= ' || v_date_dep || ')
        --                    AND D.ID_AUTORIZACION NOT IN (SELECT /*+ PARALLEL (2) */ L.ID_AUTORIZACION_ORIGINAL FROM ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG L WHERE TRUNC(L.FECHA_TRANSACCION_INI) BETWEEN ' || v_date_ini3 || ' AND ' || v_date_dep6 || ' AND L.ID_AUTORIZACION_ORIGINAL IS NOT NULL)';
        -- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.AUTORIZACION D WHERE D.ID_AUTORIZACION IN (SELECT /*+ PARALLEL (2) */ C.ID_AUTORIZACION FROM ' || v_sche_ori || '.AUTORIZACION C WHERE TRUNC(C.FECHA_AUTORIZACION) <= ' || v_date_dep || ' AND C.ID_GRUPO_TRANSACCION NOT IN (11,12))
                           AND D.ID_AUTORIZACION NOT IN (SELECT /*+ PARALLEL (2) */ L.ID_AUTORIZACION_ORIGINAL FROM ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG L WHERE TRUNC(L.FECHA_TRANSACCION_INI) BETWEEN ' || v_date_ini3 || ' AND ' || v_date_dep6 || ' AND L.ID_AUTORIZACION_ORIGINAL IS NOT NULL)';
		  
               v_num_row := SQL%rowcount;
               
               v_time3 := systimestamp;
               
               v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en AUTORIZACION: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';
		
-- DELETE DE LA TABLA AUTORIZACION_CONSULTA:

        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.AUTORIZACION_CONSULTA D WHERE D.ID_CONSULTA IN (SELECT /*+ PARALLEL (2) */ C.ID_CONSULTA FROM ' || v_sche_ori || '.AUTORIZACION_CONSULTA C WHERE TRUNC(C.FECHA_CONSULTA) <= ' || v_date_dep || ')';
		  
               v_num_row := SQL%rowcount;
               
               v_time3 := systimestamp;
               
               v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en AUTORIZACION_CONSULTA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';
        
-- DELETE DE LA TABLA AUTORIZACION_ADQUIRENTE_LOG:

        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG D WHERE D.ID_AUTORIZACION_ADQUIRENTE IN (SELECT /*+ PARALLEL (2) */ C.ID_AUTORIZACION_ADQUIRENTE FROM ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG C WHERE TRUNC(C.FECHA_TRANSACCION_INI) <= ' || v_date_dep || ')
                           AND D.ID_AUTORIZACION_ADQUIRENTE NOT IN (SELECT /*+ PARALLEL (2) */ A.ID_AUTORIZACION_ADQUIRENTE FROM ' || v_sche_ori || '.AUTORIZACION A WHERE TRUNC(A.FECHA_AUTORIZACION) <= ' || v_date_dep || ' AND A.ID_AUTORIZACION_ADQUIRENTE IS NOT NULL)
                           AND D.ID_AUTORIZACION_ADQUIRENTE NOT IN (SELECT /*+ PARALLEL (2) */ L.ID_AUTO_ADQ_ANULAR_REVERSAR FROM ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG L WHERE TRUNC(L.FECHA_TRANSACCION_INI) = ' || v_date_ini3 || ' AND L.ID_AUTO_ADQ_ANULAR_REVERSAR IS NOT NULL)';
          
               v_num_row := SQL%rowcount;
               
               v_time3 := systimestamp;
               
               v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en AUTORIZACION_ADQUIRENTE_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';
		
-- UPDATE DE LA TABLA AUTORIZACION_ADQUIRENTE_LOG:

        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE  'UPDATE ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG SET ID_AUTO_ADQ_ANULAR_REVERSAR = NULL WHERE TRUNC(FECHA_TRANSACCION_INI) <= ' || v_date_dep || ' AND ID_AUTO_ADQ_ANULAR_REVERSAR IS NOT NULL AND ID_AUTO_ADQ_ANULAR_REVERSAR
                            NOT IN (SELECT /*+ PARALLEL (2) */ ID_AUTORIZACION_ADQUIRENTE FROM ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG WHERE TRUNC(FECHA_TRANSACCION_INI) <= ' || v_date_dep || ')';  
        
               v_num_row := SQL%rowcount;
               
               v_time3 := systimestamp;
               
               v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros actualizados en AUTORIZACION_ADQUIRENTE_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';
		
-- DELETE DE LA TABLA RESPUESTA_MC_LOG:

        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.RESPUESTA_MC_LOG D WHERE D.ID_RESPUESTA_MC IN (SELECT /*+ PARALLEL (2) */ C.ID_RESPUESTA_MC FROM ' || v_sche_ori || '.RESPUESTA_MC_LOG C WHERE TRUNC(C.FECHA_TRANSACCION_INI) <= ' || v_date_dep || ')
                           AND D.ID_AUTORIZACION_ADQUIRENTE NOT IN (SELECT /*+ PARALLEL (2) */ L.ID_AUTORIZACION_ADQUIRENTE FROM ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG L WHERE TRUNC(L.FECHA_TRANSACCION_INI) <= ' || v_date_dep || ' AND L.ID_AUTORIZACION_ADQUIRENTE IS NOT NULL)';
          
               v_num_row := SQL%rowcount;
               
               v_time3 := systimestamp;
               
               v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en RESPUESTA_MC_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';
    
-------------------------------------------------------------
------- SE HABILITAN LOS CONSTRAINTS EN LA BD PROD  ---------
-------------------------------------------------------------

BEGIN

    FOR r IN (SELECT owner, table_name, constraint_name FROM DBA_CONSTRAINTS WHERE owner = v_sche_ori
                AND table_name IN ('AUTORIZACION',
                                          'AUTORIZACION_ADQUIRENTE_LOG',
                                          'AUTORIZ_INTENTOS_REVERSOS',
                                          'AUTORIZACION_REVERSOS_COLA',
										  'AUTORIZACION_RT',
                                          'COMERCIOS_LIQ_CABECERA',
                                          'COMERCIOS_LIQ_CONCEPTOS',
                                          'COMERCIOS_LIQ_DETALLES',
                                          'COMERCIOS_LIQ_IMPUESTOS',
                                          'COMERCIOS_LIQ_PLAZOS',
                                          'IN_T464',
                                          'CONSUMOS',
                                          'CONSUMOS_CUOTAS',
                                          'CONSUMOS_DATOS_ADICIONALES',
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
                                          'CONSUMOS_CARGOS_ADICIONALES',
                                          'AJUSTES_COMERCIOS',
                                          'AJUSTES_SOCIOS',
                                          'AUTORIZACION_CONSULTA',
                                          'AUTORIZACION_EMISOR_LOG',
                                          'AUTORIZACION_PAYMENT',
                                   'NOVEDADES_SAFE',
                                   'PAGOS',
                                   -- CODIGO ADAPTADO A ENTIDAD 702 - CONSTRAINTS - 21/07/2026
                                   'CLEARING',
                                   'QUEUE_PRESENTATION_INCOMING')
                       AND constraint_type = 'R'
              ORDER BY table_name ASC)
    LOOP
		v_retry_count := 0;
        v_success := FALSE;

        WHILE v_retry_count < v_max_retries AND NOT v_success LOOP
	BEGIN
    
        v_time2 := systimestamp;
    
        EXECUTE IMMEDIATE   'ALTER TABLE ' || r.owner|| '.' || r.table_name || ' ENABLE NOVALIDATE CONSTRAINT ' || r.constraint_name;
        
        v_time3 := systimestamp;
        
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		v_success := TRUE; -- Si llega aquí, fue exitoso
        
        -- INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Se habilito el constraint: ' || r.table_name || '.' || r.constraint_name, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
		
	-- SE AGREGA PARA ESCRIBIR EN EL LOG CUANDO FALLE AL HABILITAR UNA FK

    EXCEPTION
        WHEN OTHERS THEN
        v_retry_count := v_retry_count + 1;
        v_time3 := SYSTIMESTAMP;
		v_time_tot2 := SUBSTR(TO_CHAR(v_time3 - v_time2, 'SSSS.FF'), 9, 8);
                
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id, (SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'ERROR al habilitar constraint: ' || r.table_name || '.' || r.constraint_name || ', INTENTO: ' || v_retry_count || ' de 3','PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
        
        EXECUTE IMMEDIATE 'COMMIT';
		
		IF v_retry_count < v_max_retries THEN
            sys.dbms_session.sleep(2);
        ELSE
            -- Si agotó los reintentos, lanzamos el error crítico
            RAISE_APPLICATION_ERROR(-20001, 'Error crítico tras ' || v_max_retries || ' intentos en tabla ' || r.table_name || ': ' || SQLERRM);
        END IF;
    END;
        END LOOP;
    END LOOP;
END;

sys.dbms_session.sleep(2);
		
		PRC_WRITE_ERROR_LOG_DATA_CLEANING(v_proc_id,sysdate, NULL, v_fecha_dep,NULL,'Se habilitaron los constraints en: ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);

sys.dbms_session.sleep(2);

v_time4 := systimestamp;

    v_time_tot1:= substr(TO_CHAR(v_time4-v_time1,'SSSS.FF'),9,8);
    
            PRC_WRITE_ERROR_LOG_DATA_CLEANING(v_proc_id,sysdate,v_time_tot1,v_fecha_dep,NULL,'Fin del proceso de actualizacion y depuracion de registros en la BD: ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
	
	ELSE PRC_WRITE_ERROR_LOG_DATA_CLEANING(v_proc_id,sysdate,NULL,v_fecha_dep,NULL,'SE SUPERO LA FECHA LIMITE (' || v_fecha_limit || ') DE 6 MESES PARA MANTENER LOS DATOS EN PROD O SE SUPERO LA FECHA DE EJECUCION DE PRC_WFGADQ_ENTITY_DATA_CLEANING_2 (' || v_ult_proc || '), INTENTE CON UNA FECHA MENOR A LA INDICADA', 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
	
END IF; 

------------------------------------------------------------------
-- LOGUEO DE ERRORES EN LA TABLA SOPORTEDBA.LOG_DEPURADORES --
------------------------------------------------------------------

    EXCEPTION
        WHEN OTHERS
        THEN
           
            PRC_WRITE_ERROR_LOG_DATA_CLEANING(v_proc_id,sysdate, NULL, NULL, NULL, SQLERRM, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1', SQLCODE, dbms_utility.format_error_backtrace, dbms_utility.format_error_stack);
    END;
            
END;
/

CREATE OR REPLACE PACKAGE BODY SOPORTEDBA.PKG_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_702 AS 

PROCEDURE PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1(acc_ejec IN VARCHAR2)
-- PARAMETROS DE ENTRADA:
--  acc_ejec: Se indica la acción a ejecutar: 'COPY' Solo copia de datos al historico, 'DELETE' Solo borrado en PROD ó 'ALL' Copia de datos al historico y borrado en PROD
--
--  STORED PROCEDURE QUE TOMA LA FECHA QUE SE LE INDICA PARA HACER LA COPIA / DEPURACION
--
--  EJEMPLO para la ejecución: CALL SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1('COPY') --> Solo copia los datos de la entidad prod_entidad701 a ENTIDAD701 de las tablas que conforman el proceso PRC_WFGADQ_ENTITY_DATA_CLEANING_1
--                             CALL SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1('DELETE') --> Solo borra los datos de la entidad prod_entidad701 de las tablas que conforman el proceso PRC_WFGADQ_ENTITY_DATA_CLEANING_1
--                             CALL SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1('ALL') --> Copia los datos de la entidad prod_entidad701 a ENTIDAD701 y luego los borra de prod_entidad701 de las tablas que conforman el proceso PRC_WFGADQ_ENTITY_DATA_CLEANING_1
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
        v_time_tot3     VARCHAR2 (10);                                      -- TIEMPO TOTAL DE EJECUCION DEL SUB PROCESO DE DEPURACION
        v_num_row 	    NUMBER;                                             -- NUMERO DE REGISTROS AFECTADOS EN LA SENTENCIA
		v_sche_ori 	    VARCHAR2 (20) := 'PROD_ENTIDAD702';                 -- ESQUEMA A ORIGEN
		v_sche_dest 	VARCHAR2 (10):= SUBSTR(v_sche_ori,6,15);            -- ESQUEMA DESTINO
		v_acc_ejec 		VARCHAR2 (10):= acc_ejec;                           -- ACCION A EJECUTAR
		v_fecha_dep     DATE;               					            -- FECHA DE DEPURACION
		v_fecha_dep1    DATE:='01/01/2023';                                 -- FECHA DEFINIDA PARA HACER EL UPDATE DE LOS ARN DE LAS TABLAS IPM Y CTF_VISA EN CONSUMOS
		v_date_dep1     VARCHAR2(15):= '''' || v_fecha_dep1 || '''';        -- FECHA DE DEPURACION EN FORMATO 'DD/MM/YYYY'
		v_fecha_dep3    DATE;                                               -- FECHA DE DEPURACION + 3 MESES
		v_date_dep3     VARCHAR2(15);                                       -- FECHA DE DEPURACION + 3 MESES EN FORMATO 'DD/MM/YYYY'
		v_fecha_ini3    DATE;
		v_date_ini3     VARCHAR2(15);
		v_fecha_dep6    DATE;                                               -- FECHA DE DEPURACION + 6 MESES
		v_date_dep6     VARCHAR2(15);
		v_date_dep      VARCHAR2(15);								        -- FECHA DE DEPURACION EN FORMATO 'DD/MM/YYYY'
		v_fecha_inim    DATE;                                               -- FECHA INICIAL DE MES
		v_date_inim     VARCHAR2(15);                                       -- FECHA INICIAL DE MES EN FORMATO 'DD/MM/YYYY'
		v_ult_proc      DATE;                                               -- FECHA DE LA ULTIMA COPIA DE PRC_WFGADQ_ENTITY_DATA_CLEANING_1
		v_seq_id        NUMBER:=SEQ_LOG_DEPURADORES.NEXTVAL;                -- OBTIENE EL VALOR DE LA SECUENCIA PARA EL ID DEL PROCESO
		v_proc_id       NUMBER:=SEQ_LOG_DEPURADORES.CURRVAL;                -- DEFINE EL ID DEL PROCESO

    BEGIN
    
       -- SE DEFINE LA FECHA DE LA DATA QUE VA A QUEDAR EN LINEA (6 MESES):
        EXECUTE IMMEDIATE 'SELECT ADD_MONTHS(TRUNC(SYSDATE),-6) FROM DUAL' INTO v_fecha_dep;
		v_date_dep:= '''' || v_fecha_dep || '''';
        v_fecha_ini3:=v_fecha_dep +1;
        v_date_ini3:='''' || v_fecha_ini3 || '''';	
        -- SE CALCULA LA FECHA DE DEPURACION +6 MESES:
        EXECUTE IMMEDIATE 'SELECT ADD_MONTHS(TO_DATE(''' || v_fecha_dep || ''',''DD/MM/YYYY''),+6) FROM DUAL' INTO v_fecha_dep6;
        v_date_dep6:= '''' || v_fecha_dep6 || '''';                         -- FECHA DE DEPURACION + 6 MESES EN FORMATO 'DD/MM/YYYY'
        -- SE CALCULA LA FECHA FINAL +3 MESES:
        EXECUTE IMMEDIATE 'SELECT ADD_MONTHS(TO_DATE(''' || v_fecha_dep || ''',''DD/MM/YYYY''),+3) FROM DUAL' INTO v_fecha_dep3;
        v_date_dep3:= '''' || v_fecha_dep3 || '''';
        -- SE CALCULA LA FECHA INICIAL DE CADA MES:
        EXECUTE IMMEDIATE 'SELECT ADD_MONTHS(TRUNC(TO_DATE(''' || v_fecha_dep || '''),''MM''),-24) FROM DUAL' INTO v_fecha_inim;
        v_date_inim:= '''' || v_fecha_inim || '''';
        -- SE OBTIENE LA FECHA DE LA ULTIMA COPIA DE PRC_WFGADQ_ENTITY_DATA_CLEANING_1:
        EXECUTE IMMEDIATE 'SELECT MAX(TO_DATE(CLEANING_DATE,''DD/MM/RRRR'')) FROM LOG_DEPURADORES WHERE SP_NAME=''PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1'' AND ENTITY= ''' || v_sche_dest || ''' AND CLEANING_DATE IS NOT NULL' INTO v_ult_proc;

--------------------------------------------------------------------
----- SE VALIDA SI ESTÁ DENTRO DEL RANGO HORARIO DE EJECUCIÓN  -----
--------------------------------------------------------------------

DECLARE
    v_hora_actual VARCHAR2(5);
BEGIN
    v_hora_actual := TO_CHAR(
        SYSTIMESTAMP AT TIME ZONE 'America/Argentina/Buenos_Aires', 'HH24:MI'
    );

    IF v_hora_actual < '03:09' OR v_hora_actual >= '04:20' THEN
        SOPORTEDBA.PRC_WRITE_ERROR_LOG_DATA_CLEANING(
            NULL,
            SYSDATE,
            NULL,
            NULL,
            NULL,
            'Proceso no ejecutado por estar fuera de ventana horaria. Hora actual Argentina: ' || v_hora_actual,
            'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',
            NULL,
            NULL,
            NULL
        );

        RETURN;
    END IF;
        
IF v_acc_ejec='COPY' THEN
        
-------------------------------------------------------------
----- SE DESHABILITAN LOS CONSTRAINTS EN LA BD DESTINO  -----
-------------------------------------------------------------
			
			PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_dest,'Inicio del proceso de copia de registros a la BD Historica ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);

v_time1 := systimestamp;
            
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
                                 'AUTORIZACION_CONSULTA',
                                 -- CODIGO ADAPTADO A ENTIDAD 702 - CONSTRAINTS - 21/07/2026
                                 'CLEARING',
                                 'QUEUE_PRESENTATION_INCOMING'
								 )
                       AND constraint_type = 'R'
              ORDER BY table_name ASC)
    LOOP
        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE   'ALTER TABLE ' || r.owner|| '.' || r.table_name || ' DISABLE CONSTRAINT ' || r.constraint_name;
        
        v_time3 := systimestamp;
        
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
        
        -- INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,'Se deshabilito el constraint: ' || r.table_name || '.' || r.constraint_name, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
        
    END LOOP;
END;

sys.dbms_session.sleep(1);
			
			PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_dest,'Se deshabilitan los constraints en la BD ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);

-------------------------------------------------------------
----- INICIA EL BLOQUE DE COPIADO DE DATOS AL HISTORICO -----
-------------------------------------------------------------

-- IMPORT DE LAS TABLAS PROMOCION_LOG, CONSUMOS_DATOS_ADICIONALES, CONSUMOS_CARGOS_ADICIONALES, CONSUMOS_CUOTAS, RETENCIONES_CONSUMOS, PRESENTACIONES, TC33A:

        FOR r IN (SELECT owner, table_name FROM DBA_TABLES WHERE owner = v_sche_dest
              AND table_name IN ('PROMOCION_LOG','CONSUMOS_DATOS_ADICIONALES','CONSUMOS_CARGOS_ADICIONALES','CONSUMOS_CUOTAS','RETENCIONES_CONSUMOS','PRESENTACIONES','TC33A'))
        LOOP
            
            v_time2 := systimestamp;
            -- CODIGO ORIGINAL
            -- EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || r.owner || '.' || r.table_name || ' SELECT /*+ PARALLEL (2) */ I.* FROM ' || r.table_name || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' I join CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C on I.ID_CONSUMO = C.ID_CONSUMO AND TRUNC(C.FECHA_OPER) <= ' || v_date_dep;
            -- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
			EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || r.owner || '.' || r.table_name || ' SELECT /*+ PARALLEL (2) */ I.* FROM ' || r.table_name || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' I join CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C on I.ID_CONSUMO = C.ID_CONSUMO AND TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ' AND C.ID_GRUPO_TRANSACCION NOT IN (11,12)';
		
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
            
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || r.owner || '.' || r.table_name || ': ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
		
            EXECUTE IMMEDIATE 'COMMIT';
		
        END LOOP;
        
-- IMPORT DE LA TABLA COMERCIOS_LIQ_DETALLES:

        v_time2 := systimestamp;
	
        -- CODIGO ORIGINAL
        -- EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.COMERCIOS_LIQ_DETALLES SELECT  D.* FROM COMERCIOS_LIQ_DETALLES'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' D 
        --                    WHERE D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ S.ID_CONSUMO FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' S WHERE TRUNC (S.FECHA_OPER) <= ' || v_date_dep || ')';
        -- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.COMERCIOS_LIQ_DETALLES SELECT /*+ PARALLEL (2) */ D.* FROM COMERCIOS_LIQ_DETALLES'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' D 
                           WHERE (D.NRO_LIQUIDACION, D.ID_COMERCIO_CENTRAL) IN (SELECT C.NRO_LIQUIDACION, C.ID_COMERCIO_CENTRAL FROM COMERCIOS_LIQ_CABECERA'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C WHERE TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= ' || v_date_dep || ')';
		  
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
            
            EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || r.owner || '.' || r.table_name || ' SELECT /*+ PARALLEL (2) */ D.* FROM ' || r.table_name || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' D join COMERCIOS_LIQ_CABECERA' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C ON D.NRO_LIQUIDACION = C.NRO_LIQUIDACION AND D.ID_COMERCIO_CENTRAL=C.ID_COMERCIO_CENTRAL AND TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= ' || v_date_dep;
		
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
            
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || r.owner || '.' || r.table_name || ': ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
		
            EXECUTE IMMEDIATE 'COMMIT';
		
        END LOOP;

-- IMPORT DE LA TABLA COMERCIOS_LIQ_CABECERA:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.COMERCIOS_LIQ_CABECERA SELECT /*+ PARALLEL (2) */ C.* FROM COMERCIOS_LIQ_CABECERA' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) ||  ' C WHERE TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= ' || v_date_dep;
                            
        v_num_row := SQL%rowcount;
                            
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'COMERCIOS_LIQ_CABECERA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
        
        EXECUTE IMMEDIATE 'COMMIT';
		
-- IMPORT DE LA TABLA AUTORIZ_INTENTOS_REVERSOS:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZ_INTENTOS_REVERSOS SELECT /*+ PARALLEL (2) */ I.* FROM AUTORIZ_INTENTOS_REVERSOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) ||  '  I JOIN AUTORIZACION_REVERSOS_COLA' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) ||  ' R ON I.ID_AUTORIZACION_REVERSO = R.ID_AUTORIZACION_REVERSO AND TRUNC (R.FECHA_ALTA) <= ' || v_date_dep;

        v_num_row := SQL%rowcount;
                            
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZ_INTENTOS_REVERSOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA AUTORIZACION_REVERSOS_COLA:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION_REVERSOS_COLA SELECT /*+ PARALLEL (2) */ * FROM AUTORIZACION_REVERSOS_COLA' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) ||  ' WHERE TRUNC (FECHA_ALTA) <= ' || v_date_dep;
                           
        v_num_row := SQL%rowcount;
                           
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZACION_REVERSOS_COLA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA CONSUMOS:

        v_time2 := systimestamp;

        -- CODIGO ORIGINAL
        -- EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.CONSUMOS SELECT /*+ PARALLEL (2) */ C.* FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) ||  ' C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep;
        -- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.CONSUMOS SELECT /*+ PARALLEL (2) */ C.* FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) ||  ' C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ' AND C.ID_GRUPO_TRANSACCION NOT IN (11,12)';
                            
        v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'CONSUMOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA AUTORIZACION:

        v_time2 := systimestamp;
        
        -- CODIGO ORIGINAL
        -- EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION SELECT /*+ PARALLEL (2) */ * FROM AUTORIZACION' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_AUTORIZACION) <= ' || v_date_dep ||
        --                   ' AND ID_AUTORIZACION NOT IN (SELECT /*+ PARALLEL (2) */ ID_AUTORIZACION_ORIGINAL FROM AUTORIZACION_ADQUIRENTE_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_TRANSACCION_INI) BETWEEN ' || v_date_ini3 || ' AND ' || v_date_dep6 || ' AND ID_AUTORIZACION_ORIGINAL IS NOT NULL)';
        -- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION SELECT /*+ PARALLEL (2) */ * FROM AUTORIZACION' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_AUTORIZACION) <= ' || v_date_dep ||
                          ' AND ID_GRUPO_TRANSACCION NOT IN (11,12)' ||
                          ' AND ID_AUTORIZACION NOT IN (SELECT /*+ PARALLEL (2) */ ID_AUTORIZACION_ORIGINAL FROM AUTORIZACION_ADQUIRENTE_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_TRANSACCION_INI) BETWEEN ' || v_date_ini3 || ' AND ' || v_date_dep6 || ' AND ID_AUTORIZACION_ORIGINAL IS NOT NULL)';
                            
        v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZACION: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA AUTORIZACION_CONSULTA:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION_CONSULTA SELECT /*+ PARALLEL (2) */ C.* FROM AUTORIZACION_CONSULTA' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) ||  ' C WHERE TRUNC(C.FECHA_CONSULTA) <= ' || v_date_dep;
                            
        v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZACION_CONSULTA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA AUTORIZACION_ADQUIRENTE_LOG:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION_ADQUIRENTE_LOG SELECT /*+ PARALLEL (2) */ * FROM AUTORIZACION_ADQUIRENTE_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_TRANSACCION_INI) <= ' || v_date_dep;
        
        v_num_row := SQL%rowcount;
         
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZACION_ADQUIRENTE_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);

        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA RESPUESTA_MC_LOG:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.RESPUESTA_MC_LOG SELECT /*+ PARALLEL (2) */ * FROM RESPUESTA_MC_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC (FECHA_TRANSACCION_INI) <= ' || v_date_dep; 
        
        v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'RESPUESTA_MC_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';

-- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
-- IMPORT DE CONSUMOS CUOTA A CUOTA QUE YA COMPLETARON SU CICLO Y DE SUS TABLAS DEPENDIENTES:

        FOR r IN (SELECT owner, table_name FROM DBA_TABLES WHERE owner = v_sche_dest
                  AND table_name IN ('PROMOCION_LOG','CONSUMOS_DATOS_ADICIONALES','CONSUMOS_CARGOS_ADICIONALES','CONSUMOS_CUOTAS','CONSUMOS'))
        LOOP

            v_time2 := systimestamp;

            EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || r.owner || '.' || r.table_name || ' SELECT /*+ PARALLEL (2) */ I.* FROM ' || r.table_name || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' I join CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C on I.ID_CONSUMO = C.ID_CONSUMO AND TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ' AND C.ID_GRUPO_TRANSACCION IN (11,12) AND C.NRO_CUOTA = C.CUOTAS AND C.FECHA_PRESENT <= ' || v_date_dep;

            v_num_row := SQL%rowcount;
            v_time3 := systimestamp;
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados por cuota cuota en ' || r.owner || '.' || r.table_name || ': ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);

            EXECUTE IMMEDIATE 'COMMIT';

        END LOOP;

-- IMPORT DE AUTORIZACIONES ASOCIADAS A CUOTAS QUE YA COMPLETARON SU CICLO:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION SELECT /*+ PARALLEL (2) */ A.* FROM AUTORIZACION' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' A WHERE A.ID_AUTORIZACION IN (SELECT C.ID_AUTORIZACION FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C WHERE C.ID_GRUPO_TRANSACCION IN (11,12) AND C.NRO_CUOTA = C.CUOTAS AND C.FECHA_PRESENT <= ' || v_date_dep || ')';

        v_num_row := SQL%rowcount;
        v_time3 := systimestamp;
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados por cuota cuota en ' || v_sche_dest || '.AUTORIZACION: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);

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
                                 'AUTORIZACION_CONSULTA',
                                 -- CODIGO ADAPTADO A ENTIDAD 702 - CONSTRAINTS - 21/07/2026
                                 'CLEARING',
                                 'QUEUE_PRESENTATION_INCOMING'
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

v_time4 := systimestamp;

    v_time_tot1:= substr(TO_CHAR(v_time4-v_time1,'SSSS.FF'),9,8);
		
		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,v_time_tot1,v_fecha_dep,v_sche_dest,'Fin del proceso de copia de datos a la BD Historica ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);

ELSIF v_acc_ejec='DELETE' AND v_fecha_dep <= v_ult_proc THEN

v_time1 := systimestamp;
		
		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_ori,'Inicia el proceso de depuracion de datos en las tablas de: ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
        
-------------------------------------------------------------
-------- PROCESO DE UPDATE Y DELETE EN PRODUCCION -----------
-------------------------------------------------------------
        
        SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_CLEANING_1@TO_PROD_ENTIDAD702(v_sche_ori, v_fecha_dep, v_proc_id);

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
                                 'AUTORIZACION_CONSULTA',
                                 -- CODIGO ADAPTADO A ENTIDAD 702 - CONSTRAINTS - 21/07/2026
                                 'CLEARING',
                                 'QUEUE_PRESENTATION_INCOMING'
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
                           WHERE ID_AUTORIZACION_ADQUIRENTE IN (SELECT /*+ PARALLEL (2) */ ID_AUTORIZACION_ADQUIRENTE FROM ' || v_sche_dest || '.AUTORIZACION_ADQUIRENTE_LOG WHERE TRUNC(FECHA_TRANSACCION_INI) BETWEEN ' || v_date_inim || ' AND ' || v_date_dep || '
                                                                INTERSECT
                                                                SELECT /*+ PARALLEL (2) */ ID_AUTORIZACION_ADQUIRENTE FROM AUTORIZACION_ADQUIRENTE_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_TRANSACCION_INI) <= ' || v_date_dep ||')';
                                                                
       v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Para evitar duplicidad, con fecha entre ' || v_fecha_inim || ' y ' || v_fecha_dep || ' numero de registros eliminados en ' || v_sche_dest || '.' || 'AUTORIZACION_ADQUIRENTE_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
                                             
-- SE ELIMINAN REGISTROS DE LA TABLA RESPUESTA_MC_LOG:

       v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_dest || '.RESPUESTA_MC_LOG
                           WHERE ID_RESPUESTA_MC IN (SELECT /*+ PARALLEL (2) */ ID_RESPUESTA_MC FROM ' || v_sche_dest || '.RESPUESTA_MC_LOG WHERE TRUNC(FECHA_TRANSACCION_INI) BETWEEN ' || v_date_inim || ' AND ' || v_date_dep || '
                                                     INTERSECT
                                                     SELECT /*+ PARALLEL (2) */ ID_RESPUESTA_MC FROM RESPUESTA_MC_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_TRANSACCION_INI) <= ' || v_date_dep ||')';
                                                     
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
                                 'AUTORIZACION_CONSULTA',
                                 -- CODIGO ADAPTADO A ENTIDAD 702 - CONSTRAINTS - 21/07/2026
                                 'CLEARING',
                                 'QUEUE_PRESENTATION_INCOMING'
								 )
                       AND constraint_type = 'R'
              ORDER BY table_name ASC)
    LOOP
    
        EXECUTE IMMEDIATE   'ALTER TABLE ' || r.owner|| '.' || r.table_name || ' ENABLE NOVALIDATE CONSTRAINT ' || r.constraint_name;
    
    END LOOP;
END;
        
        v_time4 := systimestamp;

        v_time_tot1:= substr(TO_CHAR(v_time4-v_time1,'SSSS.FF'),9,8);
        
sys.dbms_session.sleep(1);
		
		PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,v_time_tot1,v_fecha_dep,v_sche_ori,'Fin del proceso de depuracion de datos en las tablas de: ' || v_sche_ori, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
		
ELSIF v_acc_ejec='ALL' THEN 

-------------------------------------------------------------
----- SE DESHABILITAN LOS CONSTRAINTS EN LA BD DESTINO  -----
-------------------------------------------------------------
			
	   PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_dest,'Inicio del proceso de copia de registros a la BD Historica ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);

v_time1 := systimestamp;

v_time5 := systimestamp;
            
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
                                 'AUTORIZACION_CONSULTA',
                                 -- CODIGO ADAPTADO A ENTIDAD 702 - CONSTRAINTS - 21/07/2026
                                 'CLEARING',
                                 'QUEUE_PRESENTATION_INCOMING'
								 )
                       AND constraint_type = 'R'
              ORDER BY table_name ASC)
    LOOP
        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE   'ALTER TABLE ' || r.owner|| '.' || r.table_name || ' DISABLE CONSTRAINT ' || r.constraint_name;
        
        v_time3 := systimestamp;
        
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
        
        -- INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,'Se deshabilito el constraint: ' || r.table_name || '.' || r.constraint_name, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
        
    END LOOP;
END;

sys.dbms_session.sleep(1);
			
			PRC_WRITE_ERROR_LOG_DATA_CLEANING(SEQ_LOG_DEPURADORES.CURRVAL,sysdate,NULL,v_fecha_dep,v_sche_dest,'Se deshabilitan los constraints en la BD ' || v_sche_dest, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);

-------------------------------------------------------------
----- INICIA EL BLOQUE DE COPIADO DE DATOS AL HISTORICO -----
-------------------------------------------------------------

-- IMPORT DE LAS TABLAS PROMOCION_LOG, CONSUMOS_DATOS_ADICIONALES, CONSUMOS_CARGOS_ADICIONALES, CONSUMOS_CUOTAS, RETENCIONES_CONSUMOS, PRESENTACIONES, TC33A:

        FOR r IN (SELECT owner, table_name FROM DBA_TABLES WHERE owner = v_sche_dest
              AND table_name IN ('PROMOCION_LOG','CONSUMOS_DATOS_ADICIONALES','CONSUMOS_CARGOS_ADICIONALES','CONSUMOS_CUOTAS','RETENCIONES_CONSUMOS','PRESENTACIONES','TC33A'))
        LOOP
            
            v_time2 := systimestamp;
            -- CODIGO ORIGINAL
            -- EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || r.owner || '.' || r.table_name || ' SELECT /*+ PARALLEL (2) */ I.* FROM ' || r.table_name || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' I join CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C on I.ID_CONSUMO = C.ID_CONSUMO AND TRUNC(C.FECHA_OPER) <= ' || v_date_dep;
            -- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
			EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || r.owner || '.' || r.table_name || ' SELECT /*+ PARALLEL (2) */ I.* FROM ' || r.table_name || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' I join CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C on I.ID_CONSUMO = C.ID_CONSUMO AND TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ' AND C.ID_GRUPO_TRANSACCION NOT IN (11,12)';
		
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
            
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || r.owner || '.' || r.table_name || ': ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
		
            EXECUTE IMMEDIATE 'COMMIT';
		
        END LOOP;
        
-- IMPORT DE LA TABLA COMERCIOS_LIQ_DETALLES:

        v_time2 := systimestamp;

        -- CODIGO ORIGINAL
        -- EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.COMERCIOS_LIQ_DETALLES SELECT /*+ PARALLEL (2) */ D.* FROM COMERCIOS_LIQ_DETALLES'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' D 
        --                    WHERE D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ S.ID_CONSUMO FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' S WHERE TRUNC (S.FECHA_OPER) <= ' || v_date_dep || ')';
        -- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.COMERCIOS_LIQ_DETALLES SELECT /*+ PARALLEL (2) */ D.* FROM COMERCIOS_LIQ_DETALLES'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' D 
                           WHERE (D.NRO_LIQUIDACION, D.ID_COMERCIO_CENTRAL) IN (SELECT C.NRO_LIQUIDACION, C.ID_COMERCIO_CENTRAL FROM COMERCIOS_LIQ_CABECERA'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C WHERE TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= ' || v_date_dep || ')';
		  
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
            
            EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || r.owner || '.' || r.table_name || ' SELECT /*+ PARALLEL (2) */ D.* FROM ' || r.table_name || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' D join COMERCIOS_LIQ_CABECERA' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C ON D.NRO_LIQUIDACION = C.NRO_LIQUIDACION AND D.ID_COMERCIO_CENTRAL=C.ID_COMERCIO_CENTRAL AND TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= ' || v_date_dep;
		
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
            
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || r.owner || '.' || r.table_name || ': ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
		
            EXECUTE IMMEDIATE 'COMMIT';
		
        END LOOP;

-- IMPORT DE LA TABLA COMERCIOS_LIQ_CABECERA:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.COMERCIOS_LIQ_CABECERA SELECT /*+ PARALLEL (2) */ C.* FROM COMERCIOS_LIQ_CABECERA' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) ||  ' C WHERE TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= ' || v_date_dep;
                            
        v_num_row := SQL%rowcount;
                            
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'COMERCIOS_LIQ_CABECERA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
        
        EXECUTE IMMEDIATE 'COMMIT';
		
-- IMPORT DE LA TABLA AUTORIZ_INTENTOS_REVERSOS:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZ_INTENTOS_REVERSOS SELECT /*+ PARALLEL (2) */ I.* FROM AUTORIZ_INTENTOS_REVERSOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) ||  '  I JOIN AUTORIZACION_REVERSOS_COLA' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) ||  ' R ON I.ID_AUTORIZACION_REVERSO = R.ID_AUTORIZACION_REVERSO AND TRUNC (R.FECHA_ALTA) <= ' || v_date_dep;

        v_num_row := SQL%rowcount;
                            
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZ_INTENTOS_REVERSOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA AUTORIZACION_REVERSOS_COLA:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION_REVERSOS_COLA SELECT /*+ PARALLEL (2) */ * FROM AUTORIZACION_REVERSOS_COLA' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) ||  ' WHERE TRUNC (FECHA_ALTA) <= ' || v_date_dep;
                           
        v_num_row := SQL%rowcount;
                           
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZACION_REVERSOS_COLA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA CONSUMOS:

        v_time2 := systimestamp;

        -- CODIGO ORIGINAL
        -- EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.CONSUMOS SELECT /*+ PARALLEL (2) */ C.* FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) ||  ' C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep;
        -- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.CONSUMOS SELECT /*+ PARALLEL (2) */ C.* FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) ||  ' C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ' AND C.ID_GRUPO_TRANSACCION NOT IN (11,12)';
                            
        v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'CONSUMOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        	
-- IMPORT DE LA TABLA AUTORIZACION:

        v_time2 := systimestamp;
        
        -- CODIGO ORIGINAL
        -- EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION SELECT /*+ PARALLEL (2) */ * FROM AUTORIZACION' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_AUTORIZACION) <= ' || v_date_dep ||
        --                   ' AND ID_AUTORIZACION NOT IN (SELECT /*+ PARALLEL (2) */ ID_AUTORIZACION_ORIGINAL FROM AUTORIZACION_ADQUIRENTE_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_TRANSACCION_INI) BETWEEN ' || v_date_ini3 || ' AND ' || v_date_dep6 || ' AND ID_AUTORIZACION_ORIGINAL IS NOT NULL)';
        -- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION SELECT /*+ PARALLEL (2) */ * FROM AUTORIZACION' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_AUTORIZACION) <= ' || v_date_dep ||
                          ' AND ID_GRUPO_TRANSACCION NOT IN (11,12)' ||
                          ' AND ID_AUTORIZACION NOT IN (SELECT /*+ PARALLEL (2) */ ID_AUTORIZACION_ORIGINAL FROM AUTORIZACION_ADQUIRENTE_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_TRANSACCION_INI) BETWEEN ' || v_date_ini3 || ' AND ' || v_date_dep6 || ' AND ID_AUTORIZACION_ORIGINAL IS NOT NULL)';
                            
        v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZACION: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA AUTORIZACION_CONSULTA:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION_CONSULTA SELECT /*+ PARALLEL (2) */ C.* FROM AUTORIZACION_CONSULTA' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) ||  ' C WHERE TRUNC(C.FECHA_CONSULTA) <= ' || v_date_dep;
                            
        v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZACION_CONSULTA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';  
        
-- IMPORT DE LA TABLA AUTORIZACION_ADQUIRENTE_LOG:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION_ADQUIRENTE_LOG SELECT /*+ PARALLEL (2) */ * FROM AUTORIZACION_ADQUIRENTE_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_TRANSACCION_INI) <= ' || v_date_dep;
        
        v_num_row := SQL%rowcount;
         
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'AUTORIZACION_ADQUIRENTE_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);

        EXECUTE IMMEDIATE 'COMMIT';
        
-- IMPORT DE LA TABLA RESPUESTA_MC_LOG:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.RESPUESTA_MC_LOG SELECT /*+ PARALLEL (2) */ * FROM RESPUESTA_MC_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC (FECHA_TRANSACCION_INI) <= ' || v_date_dep;
        
        v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados en ' || v_sche_dest || '.' || 'RESPUESTA_MC_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';

-- CODIGO CUOTA A CUOTA ADAPTADO A ENTIDAD 702 - 21/07/2026
-- IMPORT DE CONSUMOS CUOTA A CUOTA QUE YA COMPLETARON SU CICLO Y DE SUS TABLAS DEPENDIENTES:

        FOR r IN (SELECT owner, table_name FROM DBA_TABLES WHERE owner = v_sche_dest
                  AND table_name IN ('PROMOCION_LOG','CONSUMOS_DATOS_ADICIONALES','CONSUMOS_CARGOS_ADICIONALES','CONSUMOS_CUOTAS','CONSUMOS'))
        LOOP

            v_time2 := systimestamp;

            EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || r.owner || '.' || r.table_name || ' SELECT /*+ PARALLEL (2) */ I.* FROM ' || r.table_name || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' I join CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C on I.ID_CONSUMO = C.ID_CONSUMO AND TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ' AND C.ID_GRUPO_TRANSACCION IN (11,12) AND C.NRO_CUOTA = C.CUOTAS AND C.FECHA_PRESENT <= ' || v_date_dep;

            v_num_row := SQL%rowcount;
            v_time3 := systimestamp;
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados por cuota cuota en ' || r.owner || '.' || r.table_name || ': ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);

            EXECUTE IMMEDIATE 'COMMIT';

        END LOOP;

-- IMPORT DE AUTORIZACIONES ASOCIADAS A CUOTAS QUE YA COMPLETARON SU CICLO:

        v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.AUTORIZACION SELECT /*+ PARALLEL (2) */ A.* FROM AUTORIZACION' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' A WHERE A.ID_AUTORIZACION IN (SELECT C.ID_AUTORIZACION FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C WHERE C.ID_GRUPO_TRANSACCION IN (11,12) AND C.NRO_CUOTA = C.CUOTAS AND C.FECHA_PRESENT <= ' || v_date_dep || ')';

        v_num_row := SQL%rowcount;
        v_time3 := systimestamp;
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);

        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Con fecha menor a ' || v_fecha_dep || ' numero de registros insertados por cuota cuota en ' || v_sche_dest || '.AUTORIZACION: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);

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
                                 'AUTORIZACION_CONSULTA',
                                 -- CODIGO ADAPTADO A ENTIDAD 702 - CONSTRAINTS - 21/07/2026
                                 'CLEARING',
                                 'QUEUE_PRESENTATION_INCOMING'
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
        
        SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_CLEANING_1@TO_PROD_ENTIDAD702(v_sche_ori, v_fecha_dep, v_proc_id);
        
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
                                 'AUTORIZACION_CONSULTA',
                                 -- CODIGO ADAPTADO A ENTIDAD 702 - CONSTRAINTS - 21/07/2026
                                 'CLEARING',
                                 'QUEUE_PRESENTATION_INCOMING'
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
                           WHERE ID_AUTORIZACION_ADQUIRENTE IN (SELECT /*+ PARALLEL (2) */ ID_AUTORIZACION_ADQUIRENTE FROM ' || v_sche_dest || '.AUTORIZACION_ADQUIRENTE_LOG WHERE TRUNC(FECHA_TRANSACCION_INI) BETWEEN ' || v_date_inim || ' AND ' || v_date_dep || '
                                                                INTERSECT
                                                                SELECT /*+ PARALLEL (2) */ ID_AUTORIZACION_ADQUIRENTE FROM AUTORIZACION_ADQUIRENTE_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_TRANSACCION_INI) <= ' || v_date_dep ||')';
                                                                
       v_num_row := SQL%rowcount;
        
        v_time3 := systimestamp;
            
        v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                            
        INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (SEQ_LOG_DEPURADORES.CURRVAL,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,v_sche_dest,'Para evitar duplicidad, con fecha entre ' || v_fecha_inim || ' y ' || v_fecha_dep || ' numero de registros eliminados en ' || v_sche_dest || '.' || 'AUTORIZACION_ADQUIRENTE_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_1',NULL,NULL,NULL);
                            
        EXECUTE IMMEDIATE 'COMMIT';
                                             
-- SE ELIMINAN REGISTROS DE LA TABLA RESPUESTA_MC_LOG:

       v_time2 := systimestamp;

        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_dest || '.RESPUESTA_MC_LOG
                           WHERE ID_RESPUESTA_MC IN (SELECT /*+ PARALLEL (2) */ ID_RESPUESTA_MC FROM ' || v_sche_dest || '.RESPUESTA_MC_LOG WHERE TRUNC(FECHA_TRANSACCION_INI) BETWEEN ' || v_date_inim || ' AND ' || v_date_dep || '
                                                     INTERSECT
                                                     SELECT /*+ PARALLEL (2) */ ID_RESPUESTA_MC FROM RESPUESTA_MC_LOG' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_TRANSACCION_INI) <= ' || v_date_dep ||')';
                                                     
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
                                 'AUTORIZACION_CONSULTA',
                                 -- CODIGO ADAPTADO A ENTIDAD 702 - CONSTRAINTS - 21/07/2026
                                 'CLEARING',
                                 'QUEUE_PRESENTATION_INCOMING'
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
--  EJEMPLO para la ejecución: CALL SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_2 --> Solo borra los datos de la entidad prod_entidad701 de las tablas que conforman el proceso PRC_WFGADQ_ENTITY_DATA_CLEANING_2

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
		v_sche_ori 	    VARCHAR2 (20) := 'PROD_ENTIDAD702';                 -- ESQUEMA A ORIGEN
		v_sche_dest 	VARCHAR2 (10):= SUBSTR(v_sche_ori,6,15);            -- ESQUEMA DESTINO
		--v_acc_ejec 		VARCHAR2 (10):= acc_ejec;                       -- ACCION A EJECUTAR
		v_fecha_dep     DATE;                   					        -- FECHA DE DEPURACION
		v_fecha_dep1    DATE:='01/01/2023';                                 -- FECHA DEFINIDA PARA HACER EL UPDATE DE LOS ARN DE LAS TABLAS IPM Y CTF_VISA EN CONSUMOS
		v_date_dep1     VARCHAR2(15):= '''' || v_fecha_dep1 || '''';        -- FECHA DE DEPURACION EN FORMATO 'DD/MM/YYYY'
		v_fecha_dep3    DATE;                                               -- FECHA DE DEPURACION + 3 MESES
		v_date_dep3     VARCHAR2(15);                                       -- FECHA DE DEPURACION + 3 MESES EN FORMATO 'DD/MM/YYYY'
		v_fecha_limit   DATE;
		v_fecha_ini3    DATE;
		v_date_ini3     VARCHAR2(15);
		v_fecha_dep6    DATE;                                               -- FECHA DE DEPURACION + 6 MESES
		v_date_dep6     VARCHAR2(15);
		v_date_dep      VARCHAR2(15);								        -- FECHA DE DEPURACION EN FORMATO 'DD/MM/YYYY'
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

    IF v_hora_actual < '03:09' OR v_hora_actual >= '03:40' THEN
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
--			EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.TQR4_ADQUIRENCIA SELECT /*+ PARALLEL (2) */ I.* FROM TQR4_ADQUIRENCIA' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' I join CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C on I.ID_CONSUMO = C.ID_CONSUMO AND TRUNC(C.FECHA_OPER) <= ' || v_date_dep;
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
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.IPM SELECT /*+ PARALLEL (2) */ D.* FROM IPM' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' D WHERE D.ID_IPM_FILE IN (SELECT /*+ PARALLEL (2) */ I.ID_IPM_FILE FROM IPM_FILE' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' I WHERE TRUNC(I.FECHA_CARGA) <= ' || v_date_dep || ' OR I.FECHA_CARGA IS NULL)
--                            OR D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ')';
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
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.IPM_FILE SELECT /*+ PARALLEL (2) */ * FROM IPM_FILE'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_CARGA) <= ' || v_date_dep || ' OR TRUNC(FECHA_CARGA) IS NULL';
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
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.CTF_VISA SELECT /*+ PARALLEL (2) */ D.* FROM CTF_VISA'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' D WHERE D.ID_CTF_FILE IN (SELECT /*+ PARALLEL (2) */ I.ID_CTF_FILE FROM CTF_FILE_VISA'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' I WHERE TRUNC(I.FECHA_CARGA) <= ' || v_date_dep || ' OR I.FECHA_CARGA IS NULL)
--                           OR D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM CONSUMOS'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ')';
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
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.IN_T464 SELECT /*+ PARALLEL (2) */ * FROM IN_T464'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || 'I WHERE TRUNC(I.ORIGINAL_SETTLEMENT_DATE) <= ' || v_date_dep || '
--                           OR I.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ ID_CONSUMO FROM CONSUMOS'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_OPER) <= ' || v_date_dep || ')';
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
        
        SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_CLEANING_2@TO_PROD_ENTIDAD702(v_sche_ori, v_fecha_dep, v_proc_id);
       
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
--			EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.TQR4_ADQUIRENCIA SELECT /*+ PARALLEL (2) */ I.* FROM TQR4_ADQUIRENCIA' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' I join CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C on I.ID_CONSUMO = C.ID_CONSUMO AND TRUNC(C.FECHA_OPER) <= ' || v_date_dep;
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
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.IPM SELECT /*+ PARALLEL (2) */ D.* FROM IPM' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' D WHERE D.ID_IPM_FILE IN (SELECT  I.ID_IPM_FILE FROM IPM_FILE' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' I WHERE TRUNC(I.FECHA_CARGA) <= ' || v_date_dep || ' OR I.FECHA_CARGA IS NULL)
--                            OR D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM CONSUMOS' || TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ')';
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
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.IPM_FILE SELECT /*+ PARALLEL (2) */ * FROM IPM_FILE'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_CARGA) <= ' || v_date_dep || ' OR TRUNC(FECHA_CARGA) IS NULL';
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
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.CTF_VISA SELECT /*+ PARALLEL (2) */ D.* FROM CTF_VISA'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' D WHERE D.ID_CTF_FILE IN (SELECT  I.ID_CTF_FILE FROM CTF_FILE_VISA'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' I WHERE TRUNC(I.FECHA_CARGA) <= ' || v_date_dep || ' OR I.FECHA_CARGA IS NULL)
--                           OR D.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ C.ID_CONSUMO FROM CONSUMOS'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ')';
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
--        EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_sche_dest || '.IN_T464 SELECT /*+ PARALLEL (2) */ * FROM IN_T464'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || 'I WHERE TRUNC(I.ORIGINAL_SETTLEMENT_DATE) <= ' || v_date_dep || '
--                           OR I.ID_CONSUMO IN (SELECT /*+ PARALLEL (2) */ ID_CONSUMO FROM CONSUMOS'|| TO_NUMBER(SUBSTR(v_sche_ori,13,3)) || ' WHERE TRUNC(FECHA_OPER) <= ' || v_date_dep || ')';
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

END PKG_WFGADQ_ENTITY_DATA_COPY_AND_CLEANING_702;
/

