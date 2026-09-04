--------------------------------------------------------------------------------
-- AUDITORIA_GO_702_HISTORICO_FINAL.sql
-- BASE: HISTORICO / DESTINO
--
-- ARQUITECTURA:
--   1) JOB local de HISTORICO inicia el orquestador a las 03:00.
--   2) Inserta EXPORT_REQUEST en ENTIDAD, hace COMMIT y cierra DB LINK.
--   3) Espera EXPORT_SENT producido por el job local de ENTIDAD.
--   4) Importa DATA_ONLY localmente como SOPORTEDBA con APPEND.
--   5) Valida DELTA = ROWS_EXPORT.
--   6) Inserta DELETE_REQUEST en ENTIDAD, hace COMMIT y cierra DB LINK.
--   7) Espera DELETE_DONE y finaliza.
--
-- SEGURIDAD:
--   - Nunca abre Data Pump ni crea Scheduler mediante DB LINK.
--   - Import local ejecutado por SOPORTEDBA.
--   - No se dispara DELETE si la validación del import falla.
--   - Evita repetir automáticamente un corte ya iniciado/procesado.
--
-- AJUSTAR SI CORRESPONDE:
--   DB LINK HISTORICO -> ENTIDAD: TO_PROD_ENTIDAD702
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- GRANTS NECESARIOS EN HISTORICO, SI FALTAN
--------------------------------------------------------------------------------
/*
GRANT EXECUTE ON SYS.DBMS_DATAPUMP TO SOPORTEDBA;
GRANT EXECUTE ON SYS.DBMS_LOCK TO SOPORTEDBA;
GRANT EXECUTE ON SYS.DBMS_SCHEDULER TO SOPORTEDBA;
GRANT EXECUTE ON SYS.UTL_FILE TO SOPORTEDBA;
GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO SOPORTEDBA;
GRANT CREATE TABLE TO SOPORTEDBA;
GRANT CREATE JOB TO SOPORTEDBA;
GRANT IMP_FULL_DATABASE TO SOPORTEDBA;

-- SOPORTEDBA debe poder consultar:
-- ENTIDAD702.AUDITORIA_GO
*/
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 0) LIMPIEZA DE OBJETOS DEL MODELO ANTERIOR QUE QUEDARON INSTALADOS
--------------------------------------------------------------------------------
BEGIN
    DBMS_SCHEDULER.DROP_JOB(
        job_name => 'SOPORTEDBA.JOB_AUTO_IMP_DEL_AUD_GO_702',
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
        program_name => 'SOPORTEDBA.PROG_AUTO_IMP_DEL_AUD_GO_702',
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
    EXECUTE IMMEDIATE
        'DROP PROCEDURE SOPORTEDBA.PRC_AUTO_IMPORT_DELETE_AUD_GO_702';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -4043 THEN
            RAISE;
        END IF;
END;
/
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 1) ORQUESTADOR LOCAL DEL HISTORICO
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SOPORTEDBA.PRC_ORCH_AUDITORIA_GO_702 (
    p_fecha_dep_manual IN VARCHAR2 DEFAULT NULL
) AUTHID DEFINER
IS
    v_db_link_entidad    VARCHAR2(30) := 'TO_PROD_ENTIDAD702';

    v_time1              TIMESTAMP := SYSTIMESTAMP;
    v_time2              TIMESTAMP;
    v_time_tot           VARCHAR2(20);

    v_fecha_dep        DATE;
    v_fecha_ini        DATE := DATE '1900-01-01';
    v_fecha_token        VARCHAR2(8);

    v_sche_dest          VARCHAR2(30) := 'ENTIDAD702';
    v_sche_ori           VARCHAR2(30) := 'PROD_ENTIDAD702';

    v_proc_id            NUMBER := SOPORTEDBA.SEQ_LOG_DEP_AUDITORIA_GO.NEXTVAL;

    v_dump_file          VARCHAR2(255);
    v_export_log_file    VARCHAR2(255);
    v_import_log_file    VARCHAR2(255);

    v_num_row_exp        NUMBER := 0;
    v_num_row_hist_ini   NUMBER := 0;
    v_num_row_hist_fin    NUMBER := 0;
    v_num_row_imp  NUMBER := 0;
    v_num_row_del       NUMBER := 0;

    v_msg                VARCHAR2(300);
    v_error_msg          VARCHAR2(300);

    v_handle             NUMBER;
    v_estado_job          VARCHAR2(30);
    v_job_name           VARCHAR2(30);

    v_existe             NUMBER := 0;

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
            (v_proc_id, SYSDATE, p_execution_time, p_cleaning_date, p_entity,
             SUBSTR(p_message, 1, 300), 'PRC_ORCH_AUDITORIA_GO_702',
             p_error_code, SUBSTR(p_error_backtrace, 1, 300),
             SUBSTR(p_stack_error, 1, 300));

        COMMIT;
    END log_local;

    PROCEDURE close_entidad_link IS
    BEGIN
        BEGIN
            COMMIT;
            EXECUTE IMMEDIATE
                'ALTER SESSION CLOSE DATABASE LINK ' || v_db_link_entidad;
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
    END close_entidad_link;

    PROCEDURE remove_datapump_file (
        p_file_name IN VARCHAR2
    ) IS
    BEGIN
        IF p_file_name IS NOT NULL THEN
            BEGIN
                UTL_FILE.FREMOVE('DATA_PUMP_DIR', p_file_name);

                log_local(
                    NULL,
                    v_fecha_dep,
                    v_sche_dest,
                    'Se elimina archivo de DATA_PUMP_DIR en historico: ' ||
                    p_file_name
                );
            EXCEPTION
                WHEN OTHERS THEN
                    log_local(
                        NULL,
                        v_fecha_dep,
                        v_sche_dest,
                        'No se pudo eliminar archivo de DATA_PUMP_DIR en historico: ' ||
                        p_file_name || ' - ' || SUBSTR(SQLERRM, 1, 180),
                        SQLCODE,
                        DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                        DBMS_UTILITY.FORMAT_ERROR_STACK
                    );
            END;
        END IF;
    END remove_datapump_file;

    PROCEDURE insert_remote_request (
        p_message IN VARCHAR2
    ) IS
    BEGIN
        EXECUTE IMMEDIATE
            'INSERT INTO SOPORTEDBA.LOG_DEPURACION_AUDITORIA_GO@' ||
            v_db_link_entidad || ' (
                PROCESS_ID,
                DATE_TIME,
                EXECUTION_TIME,
                CLEANING_DATE,
                ENTITY,
                MESSAGE,
                SP_NAME,
                ERROR_CODE,
                ERROR_BACKTRACE,
                STACK_ERROR
            )
            VALUES (
                :1,
                SYSDATE - INTERVAL ''3'' HOUR,
                NULL,
                :2,
                :3,
                :4,
                :5,
                NULL,
                NULL,
                NULL
            )'
        USING
            v_proc_id,
            v_fecha_dep,
            v_sche_ori,
            SUBSTR(p_message, 1, 300),
            'PRC_REQUEST_AUDITORIA_GO_702';

        COMMIT;
        close_entidad_link;
    END insert_remote_request;

    PROCEDURE wait_remote_message (
        p_success_like     IN VARCHAR2,
        p_error_like       IN VARCHAR2,
        p_success_message  OUT VARCHAR2
    ) IS
        v_intentos NUMBER := 0;
    BEGIN
        LOOP
            v_intentos := v_intentos + 1;

            BEGIN
                EXECUTE IMMEDIATE
                    'SELECT MESSAGE
                       FROM (
                             SELECT MESSAGE
                               FROM SOPORTEDBA.LOG_DEPURACION_AUDITORIA_GO@' ||
                               v_db_link_entidad || '
                              WHERE PROCESS_ID = :1
                                AND SP_NAME =
                                    ''PRC_WORKER_AUDITORIA_GO_702''
                                AND MESSAGE LIKE :2
                              ORDER BY DATE_TIME DESC
                            )
                      WHERE ROWNUM = 1'
                INTO p_success_message
                USING v_proc_id, p_success_like;

                close_entidad_link;
                EXIT;

            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    close_entidad_link;
            END;

            BEGIN
                EXECUTE IMMEDIATE
                    'SELECT MESSAGE
                       FROM (
                             SELECT MESSAGE
                               FROM SOPORTEDBA.LOG_DEPURACION_AUDITORIA_GO@' ||
                               v_db_link_entidad || '
                              WHERE PROCESS_ID = :1
                                AND SP_NAME =
                                    ''PRC_WORKER_AUDITORIA_GO_702''
                                AND MESSAGE LIKE :2
                              ORDER BY DATE_TIME DESC
                            )
                      WHERE ROWNUM = 1'
                INTO v_error_msg
                USING v_proc_id, p_error_like;

                close_entidad_link;

                RAISE_APPLICATION_ERROR(
                    -20052,
                    'Error remoto AUDITORIA_GO: ' || v_error_msg
                );

            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    close_entidad_link;
            END;

            -- 480 intentos x 30 segundos = 4 horas.
            IF v_intentos >= 480 THEN
                RAISE_APPLICATION_ERROR(
                    -20053,
                    'Timeout esperando ' || p_success_like ||
                    '. PROCESS_ID=' || v_proc_id
                );
            END IF;

            DBMS_LOCK.SLEEP(30);
        END LOOP;
    END wait_remote_message;

BEGIN
    --------------------------------------------------------------------------
    -- FECHA DE CORTE
    --------------------------------------------------------------------------
    IF p_fecha_dep_manual IS NOT NULL THEN
        v_fecha_dep :=
            TO_DATE(p_fecha_dep_manual, 'DD/MM/YYYY');
    ELSE
        v_fecha_dep :=
            ADD_MONTHS(TRUNC(SYSDATE), -6);
    END IF;

    IF v_fecha_dep > TRUNC(SYSDATE) THEN
        RAISE_APPLICATION_ERROR(
            -20054,
            'La fecha de corte no puede ser futura.'
        );
    END IF;

    --------------------------------------------------------------------------
    -- NO REPETIR UN CORTE YA INICIADO O FINALIZADO
    --
    -- Ante un ERROR se requiere revisión manual; no se relanza automáticamente.
    --------------------------------------------------------------------------
    SELECT COUNT(*)
    INTO v_existe
    FROM SOPORTEDBA.LOG_DEPURACION_AUDITORIA_GO
    WHERE SP_NAME = 'PRC_ORCH_AUDITORIA_GO_702'
      AND CLEANING_DATE = v_fecha_dep
      AND (
             MESSAGE LIKE 'START|%'
          OR MESSAGE = 'END|OK'
          OR MESSAGE LIKE 'END|NO_ROWS_TO_EXPORT%'
          OR MESSAGE LIKE 'ERROR|%'
      );

    IF v_existe > 0 THEN
        RETURN;
    END IF;

    v_fecha_token := TO_CHAR(v_fecha_dep, 'YYYYMMDD');

    v_dump_file :=
        'exp_aud_go_702_' || v_proc_id || '_' || v_fecha_token || '.dmp';

    v_export_log_file :=
        'exp_aud_go_702_' || v_proc_id || '_' || v_fecha_token || '.log';

    log_local(
        NULL,
        v_fecha_dep,
        v_sche_dest,
        'START|Se inicia el proceso de copia y depuracion de registros en AUDITORIA_GO con FECHA_OPERACION menor a ' ||
        TO_CHAR(v_fecha_dep, 'DD/MM/YYYY HH24:MI:SS')
    );

    --------------------------------------------------------------------------
    -- CONTROL PREVIO EN HISTORICO
    --------------------------------------------------------------------------
    SELECT COUNT(*)
    INTO v_num_row_hist_ini
    FROM ENTIDAD702.AUDITORIA_GO
    WHERE FECHA_OPERACION >= v_fecha_ini
      AND FECHA_OPERACION <  v_fecha_dep;

    log_local(
        NULL,
        v_fecha_dep,
        v_sche_dest,
        'HIST_BEFORE|Numero de registros existentes en historico AUDITORIA_GO: ' || v_num_row_hist_ini
    );

    --------------------------------------------------------------------------
    -- CONTEO REMOTO EN ENTIDAD, COMMIT Y CIERRE DEL DB LINK
    --------------------------------------------------------------------------
    EXECUTE IMMEDIATE
        'SELECT COUNT(*)
           FROM PROD_ENTIDAD702.AUDITORIA_GO@' ||
           v_db_link_entidad || '
          WHERE FECHA_OPERACION >= :1
            AND FECHA_OPERACION <  :2'
    INTO v_num_row_exp
    USING v_fecha_ini, v_fecha_dep;

    close_entidad_link;

    log_local(
        NULL,
        v_fecha_dep,
        v_sche_dest,
        'REMOTE_COUNT|Numero de registros a copiar desde PROD_ENTIDAD702.AUDITORIA_GO: ' || v_num_row_exp
    );

    IF v_num_row_exp = 0 THEN
        log_local(
            NULL,
            v_fecha_dep,
            v_sche_dest,
            'END|NO_ROWS_TO_EXPORT|No existen registros para copiar y depurar en AUDITORIA_GO'
        );
        RETURN;
    END IF;

    --------------------------------------------------------------------------
    -- EXPORT_REQUEST
    --------------------------------------------------------------------------
    insert_remote_request(
        'EXPORT_REQUEST|Se solicita export local de AUDITORIA_GO' ||
        '|Dump solicitado=' || v_dump_file ||
        '|Log export=' || v_export_log_file ||
        '|Registros solicitados=' || v_num_row_exp
    );

    log_local(
        NULL,
        v_fecha_dep,
        v_sche_dest,
        'EXPORT_REQUEST_SENT|Se solicita export en entidad. PROCESS_ID=' || v_proc_id
    );

    --------------------------------------------------------------------------
    -- ESPERAR EXPORT_SENT / EXPORT_ERROR
    --------------------------------------------------------------------------
    wait_remote_message(
        p_success_like    => 'EXPORT_SENT|%',
        p_error_like      => 'EXPORT_ERROR|%',
        p_success_message => v_msg
    );

    v_dump_file :=
        REGEXP_SUBSTR(v_msg, 'Dump enviado=([^|]+)', 1, 1, NULL, 1);

    v_export_log_file :=
        REGEXP_SUBSTR(v_msg, 'Log export=([^|]+)', 1, 1, NULL, 1);

    v_num_row_exp :=
        TO_NUMBER(
            REGEXP_SUBSTR(
                v_msg,
                'Registros exportados=([0-9]+)',
                1,
                1,
                NULL,
                1
            )
        );

    log_local(
        NULL,
        v_fecha_dep,
        v_sche_dest,
        'EXPORT_SENT_DETECTED|Se detecta export enviado desde entidad. DUMP=' ||
        v_dump_file || '|Registros exportados=' || v_num_row_exp
    );

    --------------------------------------------------------------------------
    -- IMPORT LOCAL DATA_ONLY CON APPEND
    --------------------------------------------------------------------------
    close_entidad_link;

    v_time2 := SYSTIMESTAMP;

    v_job_name :=
        'IMP_AUD_702_' || SUBSTR(TO_CHAR(v_proc_id), -10);

    v_import_log_file :=
        'imp_' || REPLACE(v_dump_file, '.dmp', '.log');

    v_handle := DBMS_DATAPUMP.OPEN(
        operation => 'IMPORT',
        job_mode  => 'TABLE',
        job_name  => v_job_name,
        version   => 'COMPATIBLE'
    );

    DBMS_DATAPUMP.ADD_FILE(
        handle    => v_handle,
        filename  => v_dump_file,
        directory => 'DATA_PUMP_DIR',
        filetype  => DBMS_DATAPUMP.KU$_FILE_TYPE_DUMP_FILE
    );

    DBMS_DATAPUMP.ADD_FILE(
        handle    => v_handle,
        filename  => v_import_log_file,
        directory => 'DATA_PUMP_DIR',
        filetype  => DBMS_DATAPUMP.KU$_FILE_TYPE_LOG_FILE,
        reusefile => 1
    );

    DBMS_DATAPUMP.SET_PARAMETER(
        handle => v_handle,
        name   => 'INCLUDE_METADATA',
        value  => 0
    );

    DBMS_DATAPUMP.METADATA_REMAP(
        handle    => v_handle,
        name      => 'REMAP_SCHEMA',
        old_value => v_sche_ori,
        value     => v_sche_dest
    );

    DBMS_DATAPUMP.SET_PARAMETER(
        handle => v_handle,
        name   => 'TABLE_EXISTS_ACTION',
        value  => 'APPEND'
    );

    DBMS_DATAPUMP.START_JOB(v_handle);

    DBMS_DATAPUMP.WAIT_FOR_JOB(
        handle    => v_handle,
        job_state => v_estado_job
    );

    v_handle := NULL;

    IF v_estado_job <> 'COMPLETED' THEN
        RAISE_APPLICATION_ERROR(
            -20055,
            'Import Data Pump finalizó con estado ' || v_estado_job
        );
    END IF;

    v_time_tot :=
        SUBSTR(TO_CHAR(SYSTIMESTAMP - v_time2, 'SSSS.FF'), 9, 8);

    log_local(
        v_time_tot,
        v_fecha_dep,
        v_sche_dest,
        'IMPORT_DONE|Finaliza import local en historico. STATE=' || v_estado_job
    );

    --------------------------------------------------------------------------
    -- VALIDAR DELTA
    --------------------------------------------------------------------------
    SELECT COUNT(*)
    INTO v_num_row_hist_fin
    FROM ENTIDAD702.AUDITORIA_GO
    WHERE FECHA_OPERACION >= v_fecha_ini
      AND FECHA_OPERACION <  v_fecha_dep;

    v_num_row_imp :=
        v_num_row_hist_fin - v_num_row_hist_ini;

    log_local(
        NULL,
        v_fecha_dep,
        v_sche_dest,
        'VALIDATION|Numero de registros insertados en historico: ' || v_num_row_imp ||
        '|EXP=' || v_num_row_exp
    );

    IF v_num_row_imp <> v_num_row_exp THEN
        RAISE_APPLICATION_ERROR(
            -20056,
            'Validación fallida. DELTA=' ||
            v_num_row_imp || ', EXPORTADAS=' || v_num_row_exp
        );
    END IF;

    --------------------------------------------------------------------------
    -- DELETE_REQUEST
    --------------------------------------------------------------------------
    insert_remote_request(
        'DELETE_REQUEST|Se autoriza depuracion local de AUDITORIA_GO' ||
        '|Registros autorizados para eliminar=' || v_num_row_exp
    );

    log_local(
        NULL,
        v_fecha_dep,
        v_sche_dest,
        'DELETE_REQUEST_SENT|Se solicita depuracion en entidad. PROCESS_ID=' || v_proc_id
    );

    --------------------------------------------------------------------------
    -- ESPERAR DELETE_DONE / DELETE_ERROR
    --------------------------------------------------------------------------
    wait_remote_message(
        p_success_like    => 'DELETE_DONE|%',
        p_error_like      => 'DELETE_ERROR|%',
        p_success_message => v_msg
    );

    v_num_row_del :=
        TO_NUMBER(
            REGEXP_SUBSTR(
                v_msg,
                'Registros eliminados=([0-9]+)',
                1,
                1,
                NULL,
                1
            )
        );

    log_local(
        NULL,
        v_fecha_dep,
        v_sche_dest,
        'DELETE_DONE_DETECTED|Numero de registros eliminados en entidad AUDITORIA_GO: ' || v_num_row_del
    );

    IF v_num_row_del <> v_num_row_exp THEN
        RAISE_APPLICATION_ERROR(
            -20057,
            'DELETE finalizó con cantidad distinta. DELETED=' ||
            v_num_row_del || ', EXPORTADAS=' || v_num_row_exp
        );
    END IF;

    v_time_tot :=
        SUBSTR(TO_CHAR(SYSTIMESTAMP - v_time1, 'SSSS.FF'), 9, 8);

    remove_datapump_file(v_dump_file);
    remove_datapump_file(v_import_log_file);

    log_local(
        v_time_tot,
        v_fecha_dep,
        v_sche_dest,
        'END|OK'
    );

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;

        BEGIN
            close_entidad_link;
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;

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
                NVL(v_fecha_dep, TRUNC(SYSDATE)),
                v_sche_dest,
                'ERROR|' || SUBSTR(SQLERRM, 1, 250),
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
-- 2) WRAPPER AUTOMATICO SIN ARGUMENTOS
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SOPORTEDBA.PRC_AUTO_ORCH_AUD_GO_702
AUTHID DEFINER
IS
BEGIN
    SOPORTEDBA.PRC_ORCH_AUDITORIA_GO_702(NULL);
END;
/
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 3) PROGRAM + JOB LOCAL DEL HISTORICO
-- Corre una vez por día a las 03:00 hora Argentina.
--------------------------------------------------------------------------------
BEGIN
    DBMS_SCHEDULER.DROP_JOB(
        job_name => 'SOPORTEDBA.JOB_ORCH_AUD_GO_702',
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
        program_name => 'SOPORTEDBA.PROG_ORCH_AUD_GO_702',
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
        program_name        => 'SOPORTEDBA.PROG_ORCH_AUD_GO_702',
        program_type        => 'STORED_PROCEDURE',
        program_action      => 'SOPORTEDBA.PRC_AUTO_ORCH_AUD_GO_702',
        number_of_arguments => 0,
        enabled             => FALSE,
        comments            => 'Orquestador diario de AUDITORIA_GO'
    );

    DBMS_SCHEDULER.ENABLE(
        name => 'SOPORTEDBA.PROG_ORCH_AUD_GO_702'
    );
END;
/

BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'SOPORTEDBA.JOB_ORCH_AUD_GO_702',
        program_name    => 'SOPORTEDBA.PROG_ORCH_AUD_GO_702',
        start_date      => SYSTIMESTAMP
                           AT TIME ZONE 'America/Argentina/Buenos_Aires',
        repeat_interval =>
            'FREQ=DAILY;BYHOUR=3;BYMINUTE=0;BYSECOND=0',
        enabled         => FALSE,
        auto_drop       => FALSE,
        comments        => 'AUDITORIA_GO: orquestador diario a las 03:00 hora Argentina'
    );

    DBMS_SCHEDULER.SET_ATTRIBUTE(
        name      => 'SOPORTEDBA.JOB_ORCH_AUD_GO_702',
        attribute => 'logging_level',
        value     => DBMS_SCHEDULER.LOGGING_RUNS
    );

    DBMS_SCHEDULER.ENABLE(
        name => 'SOPORTEDBA.JOB_ORCH_AUD_GO_702'
    );
END;
/
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 4) VALIDACIONES
--------------------------------------------------------------------------------
ALTER PROCEDURE SOPORTEDBA.PRC_ORCH_AUDITORIA_GO_702 COMPILE;
ALTER PROCEDURE SOPORTEDBA.PRC_AUTO_ORCH_AUD_GO_702 COMPILE;

SELECT owner,
       object_name,
       object_type,
       status
FROM dba_objects
WHERE owner = 'SOPORTEDBA'
  AND object_name IN (
      'PRC_ORCH_AUDITORIA_GO_702',
      'PRC_AUTO_ORCH_AUD_GO_702',
      'PROG_ORCH_AUD_GO_702',
      'JOB_ORCH_AUD_GO_702'
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
      'PRC_ORCH_AUDITORIA_GO_702',
      'PRC_AUTO_ORCH_AUD_GO_702'
  )
ORDER BY name, sequence;

SELECT owner,
       program_name,
       enabled,
       program_type,
       program_action
FROM dba_scheduler_programs
WHERE owner = 'SOPORTEDBA'
  AND program_name = 'PROG_ORCH_AUD_GO_702';

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
  AND job_name = 'JOB_ORCH_AUD_GO_702';

SELECT owner,
       job_name,
       status,
       actual_start_date,
       run_duration,
       error#,
       additional_info
FROM dba_scheduler_job_run_details
WHERE owner = 'SOPORTEDBA'
  AND job_name = 'JOB_ORCH_AUD_GO_702'
ORDER BY log_date DESC
FETCH FIRST 20 ROWS ONLY;
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- EJECUCION MANUAL
--------------------------------------------------------------------------------
/*
-- Circuito completo manual con corte automático de seis meses:
BEGIN
    SOPORTEDBA.PRC_ORCH_AUDITORIA_GO_702;
END;
/

-- Circuito completo manual con fecha explícita:
BEGIN
    SOPORTEDBA.PRC_ORCH_AUDITORIA_GO_702('01/12/2025');
END;
/
*/
--------------------------------------------------------------------------------

