--------------------------------------------------------------------------------
-- AUDITORIA_GO_702_ENTIDAD_FINAL.sql
-- BASE: ENTIDAD / ORIGEN
--
-- ARQUITECTURA:
--   1) HISTORICO inserta EXPORT_REQUEST en LOG_DEPURACION_AUDITORIA_GO de ENTIDAD.
--   2) JOB local de ENTIDAD lee el pedido reciente.
--   3) PRC_WORKER exporta DATA_ONLY localmente y envía el DMP al HISTORICO.
--   4) HISTORICO importa, valida e inserta DELETE_REQUEST.
--   5) JOB local de ENTIDAD lee DELETE_REQUEST y borra localmente.
--
-- SEGURIDAD:
--   - Data Pump y DELETE se ejecutan localmente en ENTIDAD.
--   - No se crea Scheduler ni se abre Data Pump mediante DB LINK.
--   - El dispatcher automático solo acepta requests de los últimos 30 minutos.
--   - Para ejecución manual puede indicarse un PROCESS_ID exacto.
--   - Antes del DELETE se compara la cantidad actual con ROWS_EXPECTED.
--
-- AJUSTAR SI CORRESPONDE:
--   DB LINK ENTIDAD -> HISTORICO: TO_HISTORICO
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- GRANTS NECESARIOS EN ENTIDAD, SI FALTAN
--------------------------------------------------------------------------------
/*
GRANT EXECUTE ON SYS.DBMS_DATAPUMP TO SOPORTEDBA;
GRANT EXECUTE ON SYS.DBMS_FILE_TRANSFER TO SOPORTEDBA;
GRANT EXECUTE ON SYS.DBMS_SCHEDULER TO SOPORTEDBA;
GRANT EXECUTE ON SYS.UTL_FILE TO SOPORTEDBA;
GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO SOPORTEDBA;
GRANT CREATE TABLE TO SOPORTEDBA;
GRANT CREATE JOB TO SOPORTEDBA;
GRANT EXP_FULL_DATABASE TO SOPORTEDBA;

-- SOPORTEDBA también debe poder leer y borrar sobre:
-- PROD_ENTIDAD702.AUDITORIA_GO
*/
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 0) LIMPIEZA DE OBJETOS DEL MODELO ANTERIOR QUE QUEDARON INSTALADOS
--------------------------------------------------------------------------------
BEGIN
    DBMS_SCHEDULER.DROP_JOB(
        job_name => 'SOPORTEDBA.JOB_AUTO_EXP_AUD_GO_702',
        force    => TRUE
    );
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -27475 THEN
            RAISE;
        END IF;
END;
/

BEGIN
    DBMS_SCHEDULER.DROP_PROGRAM(
        program_name => 'SOPORTEDBA.PROG_AUTO_EXP_AUD_GO_702',
        force        => TRUE
    );
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -27476 THEN
            RAISE;
        END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP PROCEDURE SOPORTEDBA.PRC_AUTO_EXPORT_AUD_GO_702';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -4043 THEN
            RAISE;
        END IF;
END;
/
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 1) WORKER LOCAL: EXPORT / DELETE
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SOPORTEDBA.PRC_WORKER_AUDITORIA_GO_702 (
    p_process_id     IN NUMBER,
    p_accion         IN VARCHAR2,
    p_fecha_dep    IN DATE,
    p_dump_file      IN VARCHAR2 DEFAULT NULL,
    p_log_file       IN VARCHAR2 DEFAULT NULL,
    p_expected_rows  IN NUMBER   DEFAULT NULL
) AUTHID DEFINER
IS
    v_db_link_hist   VARCHAR2(30) := 'TO_HISTORICO';

    v_fecha_ini    DATE := DATE '1900-01-01';
    v_num_row           NUMBER := 0;
    v_num_row_del   NUMBER := 0;

    v_handle         NUMBER;
    v_estado_job      VARCHAR2(30);
    v_job_name       VARCHAR2(30);
    v_filtro         VARCHAR2(4000);

    v_time1          TIMESTAMP;
    v_time_tot       VARCHAR2(20);

    v_sche_ori         VARCHAR2(30) := 'PROD_ENTIDAD702';
    v_table_name          VARCHAR2(30) := 'AUDITORIA_GO';

    PROCEDURE log_local (
        p_execution_time  IN VARCHAR2,
        p_cleaning_date   IN DATE,
        p_entity          IN VARCHAR2,
        p_message         IN VARCHAR2,
        p_error_code      IN NUMBER DEFAULT NULL,
        p_error_backtrace IN VARCHAR2 DEFAULT NULL,
        p_stack_error     IN VARCHAR2 DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO SOPORTEDBA.LOG_DEPURACION_AUDITORIA_GO
            (PROCESS_ID, DATE_TIME, EXECUTION_TIME, CLEANING_DATE, ENTITY,
             MESSAGE, SP_NAME, ERROR_CODE, ERROR_BACKTRACE, STACK_ERROR)
        VALUES
            (p_process_id, SYSDATE, p_execution_time, p_cleaning_date, p_entity,
             SUBSTR(p_message, 1, 300), 'PRC_WORKER_AUDITORIA_GO_702',
             p_error_code, SUBSTR(p_error_backtrace, 1, 300),
             SUBSTR(p_stack_error, 1, 300));

        COMMIT;
    END log_local;

    PROCEDURE close_hist_link IS
    BEGIN
        BEGIN
            COMMIT;
            EXECUTE IMMEDIATE
                'ALTER SESSION CLOSE DATABASE LINK ' || v_db_link_hist;
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
    END close_hist_link;

    PROCEDURE remove_datapump_file (
        p_file_name IN VARCHAR2
    ) IS
    BEGIN
        IF p_file_name IS NOT NULL THEN
            BEGIN
                UTL_FILE.FREMOVE('DATA_PUMP_DIR', p_file_name);

                log_local(
                    NULL,
                    p_fecha_dep,
                    v_sche_ori,
                    'Se elimina archivo de DATA_PUMP_DIR en entidad: ' ||
                    p_file_name
                );
            EXCEPTION
                WHEN OTHERS THEN
                    log_local(
                        NULL,
                        p_fecha_dep,
                        v_sche_ori,
                        'No se pudo eliminar archivo de DATA_PUMP_DIR en entidad: ' ||
                        p_file_name || ' - ' || SUBSTR(SQLERRM, 1, 180),
                        SQLCODE,
                        DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                        DBMS_UTILITY.FORMAT_ERROR_STACK
                    );
            END;
        END IF;
    END remove_datapump_file;

BEGIN
    IF p_process_id IS NULL OR p_fecha_dep IS NULL THEN
        RAISE_APPLICATION_ERROR(
            -20090,
            'PROCESS_ID y FECHA_DEP son obligatorios.'
        );
    END IF;

    IF UPPER(p_accion) = 'EXPORT' THEN
        IF p_dump_file IS NULL OR p_log_file IS NULL THEN
            RAISE_APPLICATION_ERROR(
                -20091,
                'DUMP_FILE y LOG_FILE son obligatorios para EXPORT.'
            );
        END IF;

        ------------------------------------------------------------------------
        -- CONTEO LOCAL PREVIO
        ------------------------------------------------------------------------
        SELECT COUNT(*)
        INTO v_num_row
        FROM PROD_ENTIDAD702.AUDITORIA_GO
        WHERE FECHA_OPERACION >= v_fecha_ini
          AND FECHA_OPERACION <  p_fecha_dep;

        log_local(
            NULL,
            p_fecha_dep,
            v_sche_ori,
            'EXPORT_START|Se inicia export local de AUDITORIA_GO. Numero de registros a exportar: ' ||
            v_num_row || '|DUMP=' || p_dump_file
        );

        IF v_num_row = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20092,
                'No existen filas para exportar con FECHA_OPERACION < ' ||
                TO_CHAR(p_fecha_dep, 'DD/MM/YYYY HH24:MI:SS')
            );
        END IF;

        IF p_expected_rows IS NOT NULL AND v_num_row <> p_expected_rows THEN
            RAISE_APPLICATION_ERROR(
                -20093,
                'Cantidad previa al export distinta a la solicitada. ACTUAL=' ||
                v_num_row || ', EXPECTED=' || p_expected_rows
            );
        END IF;

        v_filtro :=
            'WHERE FECHA_OPERACION >= TO_DATE(''' ||
            TO_CHAR(v_fecha_ini, 'YYYY-MM-DD HH24:MI:SS') ||
            ''', ''YYYY-MM-DD HH24:MI:SS'') ' ||
            'AND FECHA_OPERACION < TO_DATE(''' ||
            TO_CHAR(p_fecha_dep, 'YYYY-MM-DD HH24:MI:SS') ||
            ''', ''YYYY-MM-DD HH24:MI:SS'')';

        v_job_name := 'EXP_AUD_702_' || SUBSTR(TO_CHAR(p_process_id), -10);
        v_time1    := SYSTIMESTAMP;

        ------------------------------------------------------------------------
        -- EXPORT LOCAL DATA_ONLY
        ------------------------------------------------------------------------
        v_handle := DBMS_DATAPUMP.OPEN(
            operation => 'EXPORT',
            job_mode  => 'TABLE',
            job_name  => v_job_name,
            version   => 'COMPATIBLE'
        );

        DBMS_DATAPUMP.ADD_FILE(
            handle    => v_handle,
            filename  => p_dump_file,
            directory => 'DATA_PUMP_DIR',
            filetype  => DBMS_DATAPUMP.KU$_FILE_TYPE_DUMP_FILE,
            reusefile => 1
        );

        DBMS_DATAPUMP.ADD_FILE(
            handle    => v_handle,
            filename  => p_log_file,
            directory => 'DATA_PUMP_DIR',
            filetype  => DBMS_DATAPUMP.KU$_FILE_TYPE_LOG_FILE,
            reusefile => 1
        );

        -- Equivalente PL/SQL a CONTENT=DATA_ONLY.
        DBMS_DATAPUMP.SET_PARAMETER(
            handle => v_handle,
            name   => 'INCLUDE_METADATA',
            value  => 0
        );

        DBMS_DATAPUMP.METADATA_FILTER(
            handle => v_handle,
            name   => 'SCHEMA_EXPR',
            value  => 'IN (''' || v_sche_ori || ''')'
        );

        DBMS_DATAPUMP.METADATA_FILTER(
            handle => v_handle,
            name   => 'NAME_EXPR',
            value  => 'IN (''' || v_table_name || ''')'
        );

        DBMS_DATAPUMP.DATA_FILTER(
            handle      => v_handle,
            name        => 'SUBQUERY',
            value       => v_filtro,
            table_name  => v_table_name,
            schema_name => v_sche_ori
        );

        DBMS_DATAPUMP.START_JOB(v_handle);

        DBMS_DATAPUMP.WAIT_FOR_JOB(
            handle    => v_handle,
            job_state => v_estado_job
        );

        -- WAIT_FOR_JOB finaliza y desacopla el job.
        v_handle := NULL;

        IF v_estado_job <> 'COMPLETED' THEN
            RAISE_APPLICATION_ERROR(
                -20094,
                'Export Data Pump finalizó con estado ' || v_estado_job
            );
        END IF;

        v_time_tot :=
            SUBSTR(TO_CHAR(SYSTIMESTAMP - v_time1, 'SSSS.FF'), 9, 8);

        log_local(
            v_time_tot,
            p_fecha_dep,
            v_sche_ori,
            'EXPORT_DONE_LOCAL|Finaliza export local de AUDITORIA_GO. STATE=' ||
            v_estado_job || '|Registros exportados=' || v_num_row
        );

        ------------------------------------------------------------------------
        -- ENVIAR DMP AL HISTORICO
        ------------------------------------------------------------------------
        close_hist_link;

        log_local(
            NULL,
            p_fecha_dep,
            v_sche_ori,
            'PUT_FILE_START|Se inicia transferencia del dump al historico: ' || p_dump_file
        );

        v_time1 := SYSTIMESTAMP;

        SYS.DBMS_FILE_TRANSFER.PUT_FILE(
            source_directory_object      => 'DATA_PUMP_DIR',
            source_file_name             => p_dump_file,
            destination_directory_object => 'DATA_PUMP_DIR',
            destination_file_name        => p_dump_file,
            destination_database         => v_db_link_hist
        );

        COMMIT;
        close_hist_link;

        v_time_tot :=
            SUBSTR(TO_CHAR(SYSTIMESTAMP - v_time1, 'SSSS.FF'), 9, 8);

        log_local(
            v_time_tot,
            p_fecha_dep,
            v_sche_ori,
            'EXPORT_SENT|Export local transferido al historico' ||
            '|Dump enviado=' || p_dump_file ||
            '|Log export=' || p_log_file ||
            '|Registros exportados=' || v_num_row
        );

        remove_datapump_file(p_dump_file);
        remove_datapump_file(p_log_file);

    ELSIF UPPER(p_accion) = 'DELETE' THEN
        ------------------------------------------------------------------------
        -- VALIDAR CANTIDAD ANTES DE BORRAR
        ------------------------------------------------------------------------
        SELECT COUNT(*)
        INTO v_num_row
        FROM PROD_ENTIDAD702.AUDITORIA_GO
        WHERE FECHA_OPERACION >= v_fecha_ini
          AND FECHA_OPERACION <  p_fecha_dep;

        log_local(
            NULL,
            p_fecha_dep,
            v_sche_ori,
            'DELETE_START|Se inicia validacion previa al delete en AUDITORIA_GO. Numero de registros: ' || v_num_row ||
            '|EXPECTED=' || NVL(TO_CHAR(p_expected_rows), 'NULL') ||
            '|FECHA_OPERACION<' ||
            TO_CHAR(p_fecha_dep, 'DD/MM/YYYY HH24:MI:SS')
        );

        IF p_expected_rows IS NULL THEN
            RAISE_APPLICATION_ERROR(
                -20095,
                'ROWS_EXPECTED es obligatorio para DELETE.'
            );
        END IF;

        IF v_num_row <> p_expected_rows THEN
            RAISE_APPLICATION_ERROR(
                -20096,
                'DELETE cancelado por diferencia de cantidades. ACTUAL=' ||
                v_num_row || ', EXPECTED=' || p_expected_rows
            );
        END IF;

        ------------------------------------------------------------------------
        -- DELETE LOCAL
        ------------------------------------------------------------------------
        v_time1 := SYSTIMESTAMP;

        DELETE /*+ PARALLEL(2) */
        FROM PROD_ENTIDAD702.AUDITORIA_GO
        WHERE FECHA_OPERACION >= v_fecha_ini
          AND FECHA_OPERACION <  p_fecha_dep;

        v_num_row_del := SQL%ROWCOUNT;

        IF v_num_row_del <> p_expected_rows THEN
            ROLLBACK;

            RAISE_APPLICATION_ERROR(
                -20097,
                'DELETE revertido por diferencia de cantidades. DELETED=' ||
                v_num_row_del || ', EXPECTED=' || p_expected_rows
            );
        END IF;

        COMMIT;

        v_time_tot :=
            SUBSTR(TO_CHAR(SYSTIMESTAMP - v_time1, 'SSSS.FF'), 9, 8);

        log_local(
            v_time_tot,
            p_fecha_dep,
            v_sche_ori,
            'DELETE_DONE|Depuracion local finalizada en AUDITORIA_GO' ||
            '|Registros eliminados=' || v_num_row_del
        );

    ELSE
        RAISE_APPLICATION_ERROR(
            -20098,
            'Acción no soportada: ' || NVL(p_accion, 'NULL')
        );
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        BEGIN
            IF v_handle IS NOT NULL THEN
                DBMS_DATAPUMP.DETACH(v_handle);
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;

        BEGIN
            log_local(
                NULL,
                p_fecha_dep,
                v_sche_ori,
                UPPER(NVL(p_accion, 'NULL')) || '_ERROR|' ||
                    SUBSTR(SQLERRM, 1, 250),
                SQLCODE,
                DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                DBMS_UTILITY.FORMAT_ERROR_STACK
            );
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;

        RAISE;
END;
/
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 2) DISPATCHER
--
-- AUTOMATICO:
--   p_process_id NULL -> solo toma requests de los últimos 30 minutos.
--
-- MANUAL:
--   p_process_id informado -> solo toma ese PROCESS_ID, aunque sea antiguo.
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SOPORTEDBA.PRC_DISPATCH_AUDITORIA_GO_702 (
    p_process_id IN NUMBER DEFAULT NULL
) AUTHID DEFINER
IS
BEGIN
    --------------------------------------------------------------------------
    -- EXPORT_REQUEST
    --------------------------------------------------------------------------
    FOR r IN (
        SELECT req.PROCESS_ID,
               req.CLEANING_DATE AS FECHA_DEP,
               REGEXP_SUBSTR(
                   req.MESSAGE,
                   'Dump solicitado=([^|]+)',
                   1,
                   1,
                   NULL,
                   1
               ) AS DUMP_FILE,
               REGEXP_SUBSTR(
                   req.MESSAGE,
                   'Log export=([^|]+)',
                   1,
                   1,
                   NULL,
                   1
               ) AS LOG_FILE,
               TO_NUMBER(
                   REGEXP_SUBSTR(
                       req.MESSAGE,
                       'Registros solicitados=([0-9]+)',
                       1,
                       1,
                       NULL,
                       1
                   )
               ) AS EXPECTED_ROWS
        FROM SOPORTEDBA.LOG_DEPURACION_AUDITORIA_GO req
        WHERE req.SP_NAME = 'PRC_REQUEST_AUDITORIA_GO_702'
          AND req.MESSAGE LIKE 'EXPORT_REQUEST|%'
          AND (
                p_process_id IS NOT NULL
                OR req.DATE_TIME >=
                   (SYSDATE - INTERVAL '3' HOUR) - INTERVAL '30' MINUTE
              )
          AND (
                p_process_id IS NULL
                OR req.PROCESS_ID = p_process_id
              )
          AND NOT EXISTS (
              SELECT 1
              FROM SOPORTEDBA.LOG_DEPURACION_AUDITORIA_GO st
              WHERE st.PROCESS_ID = req.PROCESS_ID
                AND st.SP_NAME = 'PRC_WORKER_AUDITORIA_GO_702'
                AND (
                       st.MESSAGE LIKE 'EXPORT_START|%'
                    OR st.MESSAGE LIKE 'EXPORT_SENT|%'
                    OR st.MESSAGE LIKE 'EXPORT_ERROR|%'
                )
          )
        ORDER BY req.DATE_TIME
    ) LOOP
        SOPORTEDBA.PRC_WORKER_AUDITORIA_GO_702(
            p_process_id    => r.PROCESS_ID,
            p_accion        => 'EXPORT',
            p_fecha_dep     => r.FECHA_DEP,
            p_dump_file     => r.DUMP_FILE,
            p_log_file      => r.LOG_FILE,
            p_expected_rows => r.EXPECTED_ROWS
        );
    END LOOP;

    --------------------------------------------------------------------------
    -- DELETE_REQUEST
    --------------------------------------------------------------------------
    FOR r IN (
        SELECT req.PROCESS_ID,
               req.CLEANING_DATE AS FECHA_DEP,
               TO_NUMBER(
                   REGEXP_SUBSTR(
                       req.MESSAGE,
                       'Registros autorizados para eliminar=([0-9]+)',
                       1,
                       1,
                       NULL,
                       1
                   )
               )
                   AS EXPECTED_ROWS
        FROM SOPORTEDBA.LOG_DEPURACION_AUDITORIA_GO req
        WHERE req.SP_NAME = 'PRC_REQUEST_AUDITORIA_GO_702'
          AND req.MESSAGE LIKE 'DELETE_REQUEST|%'
          AND (
                p_process_id IS NOT NULL
                OR req.DATE_TIME >=
                   (SYSDATE - INTERVAL '3' HOUR) - INTERVAL '30' MINUTE
              )
          AND (
                p_process_id IS NULL
                OR req.PROCESS_ID = p_process_id
              )
          AND NOT EXISTS (
              SELECT 1
              FROM SOPORTEDBA.LOG_DEPURACION_AUDITORIA_GO st
              WHERE st.PROCESS_ID = req.PROCESS_ID
                AND st.SP_NAME = 'PRC_WORKER_AUDITORIA_GO_702'
                AND (
                       st.MESSAGE LIKE 'DELETE_START|%'
                    OR st.MESSAGE LIKE 'DELETE_DONE|%'
                    OR st.MESSAGE LIKE 'DELETE_ERROR|%'
                )
          )
        ORDER BY req.DATE_TIME
    ) LOOP
        SOPORTEDBA.PRC_WORKER_AUDITORIA_GO_702(
            p_process_id    => r.PROCESS_ID,
            p_accion        => 'DELETE',
            p_fecha_dep     => r.FECHA_DEP,
            p_expected_rows => r.EXPECTED_ROWS
        );
    END LOOP;
END;
/
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 3) WRAPPER SIN ARGUMENTOS PARA EL SCHEDULER
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SOPORTEDBA.PRC_DISPATCH_AUTO_AUD_GO_702
AUTHID DEFINER
IS
BEGIN
    SOPORTEDBA.PRC_DISPATCH_AUDITORIA_GO_702(NULL);
END;
/
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 4) PROGRAM + JOB LOCAL
--
-- HISTORICO inicia el orquestador a las 03:00.
-- ENTIDAD revisa cada 5 minutos entre 03:05 y 04:55.
-- Se dejó una ventana de dos horas para cubrir EXPORT + IMPORT + DELETE.
--------------------------------------------------------------------------------
BEGIN
    DBMS_SCHEDULER.DROP_JOB(
        job_name => 'SOPORTEDBA.JOB_DISPATCH_AUD_GO_702',
        force    => TRUE
    );
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -27475 THEN
            RAISE;
        END IF;
END;
/

BEGIN
    DBMS_SCHEDULER.DROP_PROGRAM(
        program_name => 'SOPORTEDBA.PROG_DISPATCH_AUD_GO_702',
        force        => TRUE
    );
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -27476 THEN
            RAISE;
        END IF;
END;
/

BEGIN
    DBMS_SCHEDULER.CREATE_PROGRAM(
        program_name        => 'SOPORTEDBA.PROG_DISPATCH_AUD_GO_702',
        program_type        => 'STORED_PROCEDURE',
        program_action      => 'SOPORTEDBA.PRC_DISPATCH_AUTO_AUD_GO_702',
        number_of_arguments => 0,
        enabled             => FALSE,
        comments            => 'Dispatcher local de EXPORT_REQUEST y DELETE_REQUEST para AUDITORIA_GO'
    );

    DBMS_SCHEDULER.ENABLE(
        name => 'SOPORTEDBA.PROG_DISPATCH_AUD_GO_702'
    );
END;
/

BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'SOPORTEDBA.JOB_DISPATCH_AUD_GO_702',
        program_name    => 'SOPORTEDBA.PROG_DISPATCH_AUD_GO_702',
        start_date      => SYSTIMESTAMP
                           AT TIME ZONE 'America/Argentina/Buenos_Aires',
        repeat_interval =>
            'FREQ=DAILY;BYHOUR=3,4;' ||
            'BYMINUTE=5,10,15,20,25,30,35,40,45,50,55;BYSECOND=0',
        enabled         => FALSE,
        auto_drop       => FALSE,
        comments        => 'AUDITORIA_GO: dispatcher entre 03:05 y 04:55 hora Argentina'
    );

    DBMS_SCHEDULER.SET_ATTRIBUTE(
        name      => 'SOPORTEDBA.JOB_DISPATCH_AUD_GO_702',
        attribute => 'logging_level',
        value     => DBMS_SCHEDULER.LOGGING_RUNS
    );

    DBMS_SCHEDULER.ENABLE(
        name => 'SOPORTEDBA.JOB_DISPATCH_AUD_GO_702'
    );
END;
/
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 5) VALIDACIONES
--------------------------------------------------------------------------------
ALTER PROCEDURE SOPORTEDBA.PRC_WORKER_AUDITORIA_GO_702 COMPILE;
ALTER PROCEDURE SOPORTEDBA.PRC_DISPATCH_AUDITORIA_GO_702 COMPILE;
ALTER PROCEDURE SOPORTEDBA.PRC_DISPATCH_AUTO_AUD_GO_702 COMPILE;

SELECT owner,
       object_name,
       object_type,
       status
FROM dba_objects
WHERE owner = 'SOPORTEDBA'
  AND object_name IN (
      'PRC_WORKER_AUDITORIA_GO_702',
      'PRC_DISPATCH_AUDITORIA_GO_702',
      'PRC_DISPATCH_AUTO_AUD_GO_702',
      'PROG_DISPATCH_AUD_GO_702',
      'JOB_DISPATCH_AUD_GO_702'
  )
ORDER BY object_name;

SELECT name,
       type,
       line,
       position,
       text
FROM dba_errors
WHERE owner = 'SOPORTEDBA'
  AND name IN (
      'PRC_WORKER_AUDITORIA_GO_702',
      'PRC_DISPATCH_AUDITORIA_GO_702',
      'PRC_DISPATCH_AUTO_AUD_GO_702'
  )
ORDER BY name, sequence;

SELECT owner,
       program_name,
       enabled,
       program_type,
       program_action
FROM dba_scheduler_programs
WHERE owner = 'SOPORTEDBA'
  AND program_name = 'PROG_DISPATCH_AUD_GO_702';

SELECT owner,
       job_name,
       enabled,
       state,
       repeat_interval,
       last_start_date,
       next_run_date,
       failure_count
FROM dba_scheduler_jobs
WHERE owner = 'SOPORTEDBA'
  AND job_name = 'JOB_DISPATCH_AUD_GO_702';
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- EJECUCION MANUAL SEGURA
--------------------------------------------------------------------------------
/*
-- Procesar únicamente un PROCESS_ID concreto:
BEGIN
    SOPORTEDBA.PRC_DISPATCH_AUDITORIA_GO_702(12345);
END;
/

-- Dispatcher automático: solo requests de los últimos 30 minutos:
BEGIN
    SOPORTEDBA.PRC_DISPATCH_AUDITORIA_GO_702;
END;
/
*/
--------------------------------------------------------------------------------

