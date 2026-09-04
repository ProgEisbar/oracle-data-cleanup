CREATE OR REPLACE PROCEDURE SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_CLEANING_1 (sche_ori IN VARCHAR2, fecha_depuracion IN VARCHAR2, proc_id IN NUMBER)
-- STORED PROCEDURE USADO PARA REALIZAR EL PROCESO DE DEPURACIÓN DE DATOS EN LAS BD DE WOLFGANG ADQUIRENCIA
-- IMPORTANTE: ESTE PROCESO DEPENDE DE LA PREVIA EJECUCION DEL SP PRC_WFGADQ_ENTITY_DATA_CLEANING_2 O DEBE SER EJECUTADO CON FECHA DE DEPURACION MENOR A LA USADA EN EL SP MENCIONADO
-- TOMA LA FECHA  DE DEPURACION QUE SE LE INDICA, DEJANDO EN LINEA 6 MESES
-- PARAMETROS DE ENTRADA:
--  sche_ori: esquema origen (PROD_ENTIDAD700, PROD_ENTIDAD701, PROD_ENTIDAD702 y ENTIDAD703)
--  fecha_depuracion: fecha de depuración en formato DD/MM/YYYY
--  proc_id:id del proceso (cuando se ejecuta de manera automatica)
--  EJEMPLO para la ejecución: EXEC SOPORTEDBA.PRC_WFGADQ_ENTITY_DATA_CLEANING_1('ENTIDAD703','31/12/2021');
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
                                   'AUTORIZACION_CONSULTA',
                                   'AJUSTES_COMERCIOS',
                                   'AJUSTES_SOCIOS',
                                   'AUTORIZACION_EMISOR_LOG',
                                   'AUTORIZACION_PAYMENT',
                                   'NOVEDADES_SAFE',
                                   'PAGOS')
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

-- DELETE DE LAS TABLAS PROMOCION_LOG, CONSUMOS_DATOS_ADICIONALES, CONSUMOS_CARGOS_ADICIONALES, CONSUMOS_CUOTAS, RETENCIONES_CONSUMOS, PRESENTACIONES:

BEGIN

    declare
    
         CURSOR CUR_ID_CONSUMOS 
         is
         SELECT /*+ PARALLEL (4) */ C.ID_CONSUMO FROM CONSUMOS C WHERE TRUNC(C.FECHA_OPER) <= v_fecha_dep;
         
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
            
            --v_time2 := systimestamp;
            --
            --FORALL i IN registros.FIRST .. registros.LAST
            --
            ---- DELETE DE TC33A
            --DELETE FROM TC33A WHERE ID_CONSUMO = registros(i);
            --    
            --v_num_row := SQL%rowcount;
            --
            --v_time3 := systimestamp;
            --
            --v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
            --    
            --INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en TC33A: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
            --    
            --EXECUTE IMMEDIATE 'COMMIT';
                    
        close CUR_ID_CONSUMOS;
    END;
END; 

-- DELETE DE LA TABLA COMERCIOS_LIQ_DETALLES:

        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.COMERCIOS_LIQ_DETALLES D WHERE D.ID_CONSUMO IN (SELECT /*+ PARALLEL (4) */ S.ID_CONSUMO FROM ' || v_sche_ori || '.CONSUMOS S WHERE TRUNC (S.FECHA_OPER) <= ' || v_date_dep || ')';
		  
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
         SELECT /*+ PARALLEL (4) */ D.NRO_LIQUIDACION, D.ID_COMERCIO_CENTRAL FROM COMERCIOS_LIQ_CONCEPTOS D WHERE exists(select 1 FROM COMERCIOS_LIQ_CABECERA C WHERE D.NRO_LIQUIDACION = C.NRO_LIQUIDACION AND D.ID_COMERCIO_CENTRAL=C.ID_COMERCIO_CENTRAL AND TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= v_fecha_dep);
         
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
         SELECT /*+ PARALLEL (4) */ D.NRO_LIQUIDACION, D.ID_COMERCIO_CENTRAL FROM COMERCIOS_LIQ_IMPUESTOS D WHERE exists(select 1 FROM COMERCIOS_LIQ_CABECERA C WHERE D.NRO_LIQUIDACION = C.NRO_LIQUIDACION AND D.ID_COMERCIO_CENTRAL=C.ID_COMERCIO_CENTRAL AND TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= v_fecha_dep);
         
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
         SELECT /*+ PARALLEL (4) */ D.NRO_LIQUIDACION, D.ID_COMERCIO_CENTRAL FROM COMERCIOS_LIQ_PLAZOS D WHERE exists(select 1 FROM COMERCIOS_LIQ_CABECERA C WHERE D.NRO_LIQUIDACION = C.NRO_LIQUIDACION AND D.ID_COMERCIO_CENTRAL=C.ID_COMERCIO_CENTRAL AND TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= v_fecha_dep);
         
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
         SELECT /*+ PARALLEL (4) */  NRO_LIQUIDACION, ID_COMERCIO_CENTRAL, ID_MARCA FROM COMERCIOS_LIQ_CABECERA C WHERE TRUNC(C.FECHA_PROCESO_LIQUIDACION) <= v_fecha_dep;
         
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
         SELECT /*+ PARALLEL (4) */ ID_AUTORIZACION_REVERSO FROM AUTORIZACION_REVERSOS_COLA WHERE TRUNC(FECHA_ALTA) <= v_fecha_dep;
         
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

-- DELETE DE LA TABLA CONSUMOS: (SE MODIFICA EL 09/04/2026 DESPUES DE LA IMPLEMENTACION DEL MVP2 DE TRANSPORTE)

    --    v_time2 := systimestamp;
    --    
    --    EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.CONSUMOS D WHERE D.ID_CONSUMO IN (SELECT /*+ PARALLEL (4) */ C.ID_CONSUMO FROM ' || v_sche_ori || '.CONSUMOS C WHERE TRUNC(C.FECHA_OPER) <= ' || v_date_dep || ')';
	--	  
    --           v_num_row := SQL%rowcount;
    --           
    --           v_time3 := systimestamp;
    --           
    --           v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
	--	
	--	INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en CONSUMOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
	--	
	--	EXECUTE IMMEDIATE 'COMMIT';

-- DELETE DE LA TABLA CONSUMOS Y TC33A:

v_time2 := systimestamp;

BEGIN

    declare
    
         CURSOR CUR_ID_CONSUMOS 
         is
         SELECT /*+ PARALLEL (4) */
                C.ID_CONSUMO,
                CASE
                    WHEN C.ID_COD_MOVIMIENTO IN (1,2) THEN C.ID_TC33A
                    ELSE NULL
                END AS ID_TC33A
           FROM CONSUMOS C
          WHERE TRUNC(C.FECHA_OPER) <= v_fecha_dep;
         
		TYPE t_registro_ids IS RECORD (
        id_con  CONSUMOS.ID_CONSUMO%TYPE,
        id_tc   CONSUMOS.ID_TC33A%TYPE);
		
		TYPE lv_tbl IS TABLE OF t_registro_ids;
		registros lv_tbl;
         
        begin
         
        open CUR_ID_CONSUMOS;

            fetch CUR_ID_CONSUMOS BULK COLLECT INTO registros;
            
            FORALL i IN registros.FIRST .. registros.LAST
            
            -- DELETE DE CONSUMOS
            DELETE FROM CONSUMOS WHERE ID_CONSUMO = registros(i).id_con;
                
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
        
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en CONSUMOS: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
            
            v_time2 := systimestamp;
            
            FORALL i IN registros.FIRST .. registros.LAST
            
            -- DELETE DE TC33A
            DELETE FROM TC33A T
             WHERE T.ID_TC33A = registros(i).id_tc
               AND NOT EXISTS (
                       SELECT 1
                         FROM CONSUMOS C
                        WHERE C.ID_TC33A = T.ID_TC33A
                   );
                
            v_num_row := SQL%rowcount;
            
            v_time3 := systimestamp;
        
            v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
                
            INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en TC33A: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
                
            EXECUTE IMMEDIATE 'COMMIT';
                    
        close CUR_ID_CONSUMOS;
    END;
END; 

-- DELETE DE LA TABLA COMERCIOS_LIQ_DETALLES 2:

    --    v_time2 := systimestamp;
    --    
    --    EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.COMERCIOS_LIQ_DETALLES D WHERE D.ID_CONSUMO NOT IN (SELECT /*+ PARALLEL (4) */ S.ID_CONSUMO FROM ' || v_sche_ori || '.CONSUMOS S) AND TRUNC (D.FECHA_OPER) <= ' || v_date_dep;
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
        
        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.AUTORIZACION D WHERE D.ID_AUTORIZACION IN (SELECT /*+ PARALLEL (4) */ C.ID_AUTORIZACION FROM ' || v_sche_ori || '.AUTORIZACION C WHERE TRUNC(C.FECHA_AUTORIZACION) <= ' || v_date_dep || ')
                           AND D.ID_AUTORIZACION NOT IN (SELECT /*+ PARALLEL (4) */ L.ID_AUTORIZACION_ORIGINAL FROM ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG L WHERE TRUNC(L.FECHA_TRANSACCION_INI) BETWEEN ' || v_date_ini3 || ' AND ' || v_date_dep6 || ' AND L.ID_AUTORIZACION_ORIGINAL IS NOT NULL)';
		  
               v_num_row := SQL%rowcount;
               
               v_time3 := systimestamp;
               
               v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en AUTORIZACION: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';   
		
-- DELETE DE LA TABLA AUTORIZACION_CONSULTA:

        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.AUTORIZACION_CONSULTA D WHERE D.ID_CONSULTA IN (SELECT /*+ PARALLEL (4) */ C.ID_CONSULTA FROM ' || v_sche_ori || '.AUTORIZACION_CONSULTA C WHERE TRUNC(C.FECHA_CONSULTA) <= ' || v_date_dep || ')';
		  
               v_num_row := SQL%rowcount;
               
               v_time3 := systimestamp;
               
               v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en AUTORIZACION_CONSULTA: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';   
        
-- DELETE DE LA TABLA AUTORIZACION_ADQUIRENTE_LOG:

        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG D WHERE D.ID_AUTORIZACION_ADQUIRENTE IN (SELECT /*+ PARALLEL (4) */ C.ID_AUTORIZACION_ADQUIRENTE FROM ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG C WHERE TRUNC(C.FECHA_TRANSACCION_INI) <= ' || v_date_dep || ')
                           AND D.ID_AUTORIZACION_ADQUIRENTE NOT IN (SELECT /*+ PARALLEL (4) */ A.ID_AUTORIZACION_ADQUIRENTE FROM ' || v_sche_ori || '.AUTORIZACION A WHERE TRUNC(A.FECHA_AUTORIZACION) <= ' || v_date_dep || ' AND A.ID_AUTORIZACION_ADQUIRENTE IS NOT NULL)
                           AND D.ID_AUTORIZACION_ADQUIRENTE NOT IN (SELECT /*+ PARALLEL (4) */ L.ID_AUTO_ADQ_ANULAR_REVERSAR FROM ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG L WHERE TRUNC(L.FECHA_TRANSACCION_INI) = ' || v_date_ini3 || ' AND L.ID_AUTO_ADQ_ANULAR_REVERSAR IS NOT NULL)';
          
               v_num_row := SQL%rowcount;
               
               v_time3 := systimestamp;
               
               v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros eliminados en AUTORIZACION_ADQUIRENTE_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';
		
-- UPDATE DE LA TABLA AUTORIZACION_ADQUIRENTE_LOG:

        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE  'UPDATE ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG SET ID_AUTO_ADQ_ANULAR_REVERSAR = NULL WHERE TRUNC(FECHA_TRANSACCION_INI) <= ' || v_date_dep || ' AND ID_AUTO_ADQ_ANULAR_REVERSAR IS NOT NULL AND ID_AUTO_ADQ_ANULAR_REVERSAR
                            NOT IN (SELECT /*+ PARALLEL (4) */ ID_AUTORIZACION_ADQUIRENTE FROM ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG WHERE TRUNC(FECHA_TRANSACCION_INI) <= ' || v_date_dep || ')';  
        
               v_num_row := SQL%rowcount;
               
               v_time3 := systimestamp;
               
               v_time_tot2:= substr(TO_CHAR(v_time3-v_time2,'SSSS.FF'),9,8);
		
		INSERT INTO SOPORTEDBA.LOG_DEPURADORES (PROCESS_ID,DATE_TIME,EXECUTION_TIME,CLEANING_DATE,ENTITY,MESSAGE,SP_NAME,ERROR_CODE,ERROR_BACKTRACE,STACK_ERROR) VALUES (v_proc_id,(SELECT SYSDATE - INTERVAL '3' HOUR FROM DUAL),v_time_tot2,NULL,NULL,'Con fecha menor a ' || v_fecha_dep || ' numero de registros actualizados en AUTORIZACION_ADQUIRENTE_LOG: ' || v_num_row, 'PRC_WFGADQ_ENTITY_DATA_CLEANING_1',NULL,NULL,NULL);
		
		EXECUTE IMMEDIATE 'COMMIT';
		
-- DELETE DE LA TABLA RESPUESTA_MC_LOG:

        v_time2 := systimestamp;
        
        EXECUTE IMMEDIATE 'DELETE FROM ' || v_sche_ori || '.RESPUESTA_MC_LOG D WHERE D.ID_RESPUESTA_MC IN (SELECT /*+ PARALLEL (4) */ C.ID_RESPUESTA_MC FROM ' || v_sche_ori || '.RESPUESTA_MC_LOG C WHERE TRUNC(C.FECHA_TRANSACCION_INI) <= ' || v_date_dep || ')
                           AND D.ID_AUTORIZACION_ADQUIRENTE NOT IN (SELECT /*+ PARALLEL (4) */ L.ID_AUTORIZACION_ADQUIRENTE FROM ' || v_sche_ori || '.AUTORIZACION_ADQUIRENTE_LOG L WHERE TRUNC(L.FECHA_TRANSACCION_INI) <= ' || v_date_dep || ' AND L.ID_AUTORIZACION_ADQUIRENTE IS NOT NULL)';
          
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
                                          'AUTORIZACION_CONSULTA',
                                          'AJUSTES_COMERCIOS',
                                          'AJUSTES_SOCIOS',
                                          'AUTORIZACION_EMISOR_LOG',
                                          'AUTORIZACION_PAYMENT',
                                          'NOVEDADES_SAFE',
                                          'PAGOS')
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

	-- SE AGREGA PARA ESCRIBIR EN EL LOG CUANDO FALLE AL LEVANTAR UNA FK

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

