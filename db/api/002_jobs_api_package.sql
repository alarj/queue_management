-- MVP1 queue API package.
-- Run in SQL Developer as JOBS_APP.

CREATE OR REPLACE PACKAGE pkg_jobs_api AUTHID DEFINER AS
    FUNCTION submit_job(p_body CLOB, o_http_status OUT PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION get_job_status(p_job_id NUMBER, p_application_code VARCHAR2,
                            o_http_status OUT PLS_INTEGER) RETURN VARCHAR2;

    FUNCTION worker_startup(p_body CLOB, o_http_status OUT PLS_INTEGER) RETURN CLOB;
    FUNCTION claim_job(p_body CLOB, o_http_status OUT PLS_INTEGER) RETURN CLOB;
    FUNCTION start_job(p_job_id NUMBER, p_body CLOB,
                       o_http_status OUT PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION heartbeat(p_job_id NUMBER, p_body CLOB,
                       o_http_status OUT PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION complete_job(p_job_id NUMBER, p_body CLOB,
                          o_http_status OUT PLS_INTEGER) RETURN VARCHAR2;

    FUNCTION admin_queue(o_http_status OUT PLS_INTEGER) RETURN CLOB;
    FUNCTION admin_job(p_job_id NUMBER, o_http_status OUT PLS_INTEGER) RETURN CLOB;
    FUNCTION admin_move_job(p_job_id NUMBER, p_direction VARCHAR2, p_body CLOB,
                            o_http_status OUT PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION admin_hold_job(p_job_id NUMBER, p_body CLOB,
                            o_http_status OUT PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION admin_resume_job(p_job_id NUMBER, p_body CLOB,
                              o_http_status OUT PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION admin_remove_job(p_job_id NUMBER, p_body CLOB,
                              o_http_status OUT PLS_INTEGER) RETURN VARCHAR2;

END pkg_jobs_api;
/

CREATE OR REPLACE PACKAGE BODY pkg_jobs_api AS
    c_invalid_request       CONSTANT PLS_INTEGER := -20001;
    c_application_not_found CONSTANT PLS_INTEGER := -20002;
    c_application_disabled CONSTANT PLS_INTEGER := -20003;
    c_job_type_not_found   CONSTANT PLS_INTEGER := -20004;
    c_job_type_disabled    CONSTANT PLS_INTEGER := -20005;
    c_job_not_found        CONSTANT PLS_INTEGER := -20006;
    c_idempotency_conflict CONSTANT PLS_INTEGER := -20007;
    c_invalid_state        CONSTANT PLS_INTEGER := -20008;
    c_invalid_token        CONSTANT PLS_INTEGER := -20009;
    c_dependency_conflict  CONSTANT PLS_INTEGER := -20010;
    c_claim_conflict       CONSTANT PLS_INTEGER := -20011;

    PROCEDURE fail(p_code PLS_INTEGER, p_message VARCHAR2) IS
    BEGIN
        raise_application_error(p_code, p_message);
    END;

    FUNCTION parse_body(p_body CLOB) RETURN JSON_OBJECT_T IS
    BEGIN
        IF p_body IS NULL THEN
            fail(c_invalid_request, 'request body is required');
        END IF;
        RETURN JSON_OBJECT_T.parse(p_body);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            fail(c_invalid_request, 'request body must be a JSON object');
            RETURN NULL;
    END;

    FUNCTION required_string(p_object JSON_OBJECT_T, p_name VARCHAR2) RETURN VARCHAR2 IS
        l_value VARCHAR2(32767);
    BEGIN
        IF NOT p_object.has(p_name) THEN
            fail(c_invalid_request, p_name || ' is required');
        END IF;
        l_value := TRIM(p_object.get_string(p_name));
        IF l_value IS NULL THEN
            fail(c_invalid_request, p_name || ' is required');
        END IF;
        IF LENGTH(l_value) > 250 THEN
            fail(c_invalid_request, p_name || ' is longer than 250 characters');
        END IF;
        RETURN l_value;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            fail(c_invalid_request, p_name || ' must be a string');
            RETURN NULL;
    END;

    FUNCTION optional_number(p_object JSON_OBJECT_T, p_name VARCHAR2) RETURN NUMBER IS
    BEGIN
        IF NOT p_object.has(p_name) THEN
            RETURN NULL;
        END IF;
        RETURN p_object.get_number(p_name);
    EXCEPTION
        WHEN OTHERS THEN
            fail(c_invalid_request, p_name || ' must be a number or null');
            RETURN NULL;
    END;

    FUNCTION optional_boolean(p_object JSON_OBJECT_T, p_name VARCHAR2,
                              p_default BOOLEAN) RETURN BOOLEAN IS
    BEGIN
        IF NOT p_object.has(p_name) THEN
            RETURN p_default;
        END IF;
        RETURN p_object.get_boolean(p_name);
    EXCEPTION
        WHEN OTHERS THEN
            fail(c_invalid_request, p_name || ' must be a boolean');
            RETURN p_default;
    END;

    FUNCTION required_parameters(p_object JSON_OBJECT_T) RETURN CLOB IS
        l_parameters JSON_OBJECT_T;
    BEGIN
        IF NOT p_object.has('parameters') THEN
            fail(c_invalid_request, 'parameters is required');
        END IF;
        l_parameters := p_object.get_object('parameters');
        IF l_parameters IS NULL THEN
            fail(c_invalid_request, 'parameters must be a JSON object');
        END IF;
        RETURN l_parameters.to_clob();
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            fail(c_invalid_request, 'parameters must be a JSON object');
            RETURN NULL;
    END;

    FUNCTION token_raw(p_token VARCHAR2) RETURN RAW IS
    BEGIN
        IF p_token IS NULL OR LENGTH(p_token) <> 32 THEN
            fail(c_invalid_token, 'execution token is invalid');
        END IF;
        RETURN HEXTORAW(p_token);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            fail(c_invalid_token, 'execution token is invalid');
            RETURN NULL;
    END;

    FUNCTION utc_text(p_value TIMESTAMP) RETURN VARCHAR2 IS
    BEGIN
        IF p_value IS NULL THEN
            RETURN NULL;
        END IF;
        RETURN TO_CHAR(p_value, 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"');
    END;

    FUNCTION application_id(p_application_code VARCHAR2,
                            p_require_enabled BOOLEAN := TRUE) RETURN NUMBER IS
        l_application_id applications.application_id%TYPE;
        l_enabled applications.enabled%TYPE;
    BEGIN
        SELECT application_id, enabled
          INTO l_application_id, l_enabled
          FROM applications
         WHERE application_code = p_application_code;

        IF p_require_enabled AND l_enabled <> 1 THEN
            fail(c_application_disabled, 'application is disabled');
        END IF;
        RETURN l_application_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            fail(c_application_not_found, 'application was not found');
            RETURN NULL;
    END;

    FUNCTION job_type_id(p_application_id NUMBER, p_job_type_code VARCHAR2)
        RETURN NUMBER IS
        l_job_type_id job_types.job_type_id%TYPE;
        l_enabled job_types.enabled%TYPE;
    BEGIN
        SELECT job_type_id, enabled
          INTO l_job_type_id, l_enabled
          FROM job_types
         WHERE application_id = p_application_id
           AND job_type_code = p_job_type_code;

        IF l_enabled <> 1 THEN
            fail(c_job_type_disabled, 'job type is disabled');
        END IF;
        RETURN l_job_type_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            fail(c_job_type_not_found, 'job type was not found for the application');
            RETURN NULL;
    END;

    PROCEDURE add_event(p_job_id NUMBER, p_event_type VARCHAR2,
                        p_actor_type VARCHAR2, p_actor_id VARCHAR2,
                        p_details CLOB := NULL) IS
    BEGIN
        IF p_details IS NULL THEN
            INSERT INTO job_events(job_id, event_type, actor_type, actor_id)
            VALUES (p_job_id, p_event_type, p_actor_type, p_actor_id);
        ELSE
            INSERT INTO job_events(job_id, event_type, actor_type, actor_id, details_json)
            VALUES (p_job_id, p_event_type, p_actor_type, p_actor_id, JSON(p_details));
        END IF;
    END;

    FUNCTION error_response(p_sqlcode NUMBER, p_sqlerrm VARCHAR2,
                            o_http_status OUT PLS_INTEGER) RETURN VARCHAR2 IS
        l_error_code VARCHAR2(250);
        l_message VARCHAR2(4000);
        l_result JSON_OBJECT_T := JSON_OBJECT_T();
    BEGIN
        CASE p_sqlcode
            WHEN c_invalid_request THEN
                l_error_code := 'INVALID_REQUEST'; o_http_status := 400;
            WHEN c_application_not_found THEN
                l_error_code := 'APPLICATION_NOT_FOUND'; o_http_status := 404;
            WHEN c_application_disabled THEN
                l_error_code := 'APPLICATION_DISABLED'; o_http_status := 403;
            WHEN c_job_type_not_found THEN
                l_error_code := 'JOB_TYPE_NOT_FOUND'; o_http_status := 404;
            WHEN c_job_type_disabled THEN
                l_error_code := 'JOB_TYPE_DISABLED'; o_http_status := 403;
            WHEN c_job_not_found THEN
                l_error_code := 'JOB_NOT_FOUND'; o_http_status := 404;
            WHEN c_idempotency_conflict THEN
                l_error_code := 'IDEMPOTENCY_CONFLICT'; o_http_status := 409;
            WHEN c_invalid_state THEN
                l_error_code := 'INVALID_STATE'; o_http_status := 409;
            WHEN c_invalid_token THEN
                l_error_code := 'INVALID_TOKEN'; o_http_status := 409;
            WHEN c_dependency_conflict THEN
                l_error_code := 'DEPENDENCY_CONFLICT'; o_http_status := 409;
            WHEN c_claim_conflict THEN
                l_error_code := 'CLAIM_CONFLICT'; o_http_status := 409;
            ELSE
                l_error_code := 'INTERNAL_ERROR'; o_http_status := 500;
        END CASE;

        l_message := REGEXP_REPLACE(p_sqlerrm, '^ORA-[0-9]+: *', '');
        l_result.put('error_code', l_error_code);
        l_result.put('message', l_message);
        l_result.put('oracle_error', p_sqlerrm);
        RETURN l_result.to_string();
    END;

    FUNCTION rollback_error(p_sqlcode NUMBER, p_sqlerrm VARCHAR2,
                            o_http_status OUT PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        ROLLBACK TO api_call;
        RETURN error_response(p_sqlcode, p_sqlerrm, o_http_status);
    END;

    FUNCTION job_response(p_job_id NUMBER, p_include_parameters BOOLEAN := FALSE)
        RETURN JSON_OBJECT_T IS
        l_result JSON_OBJECT_T := JSON_OBJECT_T();
        l_parameters CLOB;
        l_application_job_id jobs.application_job_id%TYPE;
        l_job_type_code job_types.job_type_code%TYPE;
        l_previous_job_id jobs.previous_job_id%TYPE;
        l_status jobs.status%TYPE;
        l_created_at jobs.created_at%TYPE;
        l_updated_at jobs.updated_at%TYPE;
        l_completed_at jobs.completed_at%TYPE;
    BEGIN
        SELECT j.application_job_id, jt.job_type_code, j.previous_job_id,
               j.status, j.created_at, j.updated_at, j.completed_at,
               JSON_SERIALIZE(j.parameters_json RETURNING CLOB)
          INTO l_application_job_id, l_job_type_code, l_previous_job_id,
               l_status, l_created_at, l_updated_at, l_completed_at, l_parameters
          FROM jobs j
          JOIN job_types jt ON jt.job_type_id = j.job_type_id
         WHERE j.job_id = p_job_id;

        l_result.put('job_id', p_job_id);
        l_result.put('application_job_id', l_application_job_id);
        l_result.put('job_type_code', l_job_type_code);
        IF l_previous_job_id IS NULL THEN l_result.put_null('previous_job_id');
        ELSE l_result.put('previous_job_id', l_previous_job_id); END IF;
        l_result.put('status', l_status);
        l_result.put('created_at', utc_text(l_created_at));
        IF l_updated_at IS NULL THEN l_result.put_null('updated_at');
        ELSE l_result.put('updated_at', utc_text(l_updated_at)); END IF;
        IF l_completed_at IS NULL THEN l_result.put_null('completed_at');
        ELSE l_result.put('completed_at', utc_text(l_completed_at)); END IF;
        IF p_include_parameters THEN
            l_result.put('parameters', JSON_OBJECT_T.parse(l_parameters));
        END IF;
        RETURN l_result;
    END;

    FUNCTION claim_response(p_job_id NUMBER, p_execution_token RAW,
                            p_attempt_number NUMBER) RETURN CLOB IS
        l_result JSON_OBJECT_T;
    BEGIN
        l_result := job_response(p_job_id, TRUE);
        l_result.put('attempt_number', p_attempt_number);
        l_result.put('execution_token', RAWTOHEX(p_execution_token));
        RETURN l_result.to_clob();
    END;

    FUNCTION job_status_text(p_job_id NUMBER, p_status VARCHAR2) RETURN VARCHAR2 IS
        l_result JSON_OBJECT_T := JSON_OBJECT_T();
    BEGIN
        l_result.put('job_id', p_job_id);
        l_result.put('status', p_status);
        RETURN l_result.to_string();
    END;

    FUNCTION submit_job(p_body CLOB, o_http_status OUT PLS_INTEGER) RETURN VARCHAR2 IS
        l_body JSON_OBJECT_T;
        l_application_code VARCHAR2(250);
        l_job_type_code VARCHAR2(250);
        l_application_job_id VARCHAR2(250);
        l_idempotency_key VARCHAR2(250);
        l_parameters CLOB;
        l_previous_job_id NUMBER;
        l_application_id NUMBER;
        l_job_type_id NUMBER;
        l_job_id NUMBER;
        l_matches NUMBER;
        l_existing_status jobs.status%TYPE;
    BEGIN
        SAVEPOINT api_call;
        l_body := parse_body(p_body);
        l_application_code := required_string(l_body, 'application_code');
        l_job_type_code := required_string(l_body, 'job_type_code');
        l_application_job_id := required_string(l_body, 'application_job_id');
        l_idempotency_key := required_string(l_body, 'idempotency_key');
        l_previous_job_id := optional_number(l_body, 'previous_job_id');
        l_parameters := required_parameters(l_body);
        l_application_id := application_id(l_application_code);
        l_job_type_id := job_type_id(l_application_id, l_job_type_code);

        IF l_previous_job_id IS NOT NULL THEN
            SELECT COUNT(*) INTO l_matches
              FROM jobs
             WHERE job_id = l_previous_job_id
               AND application_id = l_application_id;
            IF l_matches = 0 THEN
                fail(c_dependency_conflict, 'previous job was not found for the application');
            END IF;
        END IF;

        BEGIN
            SELECT job_id, status,
                   CASE
                     WHEN job_type_id = l_job_type_id
                      AND application_job_id = l_application_job_id
                      AND DECODE(previous_job_id, l_previous_job_id, 1, 0) = 1
                      AND JSON_EQUAL(parameters_json, JSON(l_parameters) ERROR ON ERROR)
                     THEN 1 ELSE 0
                   END
              INTO l_job_id, l_existing_status, l_matches
              FROM jobs
             WHERE application_id = l_application_id
               AND idempotency_key = l_idempotency_key;

            IF l_matches <> 1 THEN
                fail(c_idempotency_conflict,
                     'idempotency key is already used for a different job');
            END IF;
            o_http_status := 200;
            RETURN job_status_text(l_job_id, l_existing_status);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN NULL;
        END;

        BEGIN
            INSERT INTO jobs(application_id, job_type_id, application_job_id,
                             previous_job_id, idempotency_key, parameters_json)
            VALUES (l_application_id, l_job_type_id, l_application_job_id,
                    l_previous_job_id, l_idempotency_key, JSON(l_parameters))
            RETURNING job_id INTO l_job_id;
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                SELECT job_id, status,
                       CASE
                         WHEN job_type_id = l_job_type_id
                          AND application_job_id = l_application_job_id
                          AND DECODE(previous_job_id, l_previous_job_id, 1, 0) = 1
                          AND JSON_EQUAL(parameters_json, JSON(l_parameters) ERROR ON ERROR)
                         THEN 1 ELSE 0
                       END
                  INTO l_job_id, l_existing_status, l_matches
                  FROM jobs
                 WHERE application_id = l_application_id
                   AND idempotency_key = l_idempotency_key;
                IF l_matches <> 1 THEN
                    fail(c_idempotency_conflict,
                         'idempotency key is already used for a different job');
                END IF;
                o_http_status := 200;
                RETURN job_status_text(l_job_id, l_existing_status);
        END;

        add_event(l_job_id, 'JOB_CREATED', 'APPLICATION', l_application_code);
        o_http_status := 201;
        RETURN job_status_text(l_job_id, 'QUEUED');
    EXCEPTION
        WHEN OTHERS THEN
            RETURN rollback_error(SQLCODE, SQLERRM, o_http_status);
    END;

    FUNCTION get_job_status(p_job_id NUMBER, p_application_code VARCHAR2,
                            o_http_status OUT PLS_INTEGER) RETURN VARCHAR2 IS
        l_application_id NUMBER;
        l_count NUMBER;
        l_result JSON_OBJECT_T;
    BEGIN
        l_application_id := application_id(TRIM(p_application_code));
        SELECT COUNT(*) INTO l_count
          FROM jobs
         WHERE job_id = p_job_id
           AND application_id = l_application_id;
        IF l_count = 0 THEN
            fail(c_job_not_found, 'job was not found');
        END IF;
        o_http_status := 200;
        l_result := job_response(p_job_id);
        RETURN l_result.to_string();
    EXCEPTION
        WHEN OTHERS THEN
            RETURN error_response(SQLCODE, SQLERRM, o_http_status);
    END;

    FUNCTION worker_startup(p_body CLOB, o_http_status OUT PLS_INTEGER) RETURN CLOB IS
        l_body JSON_OBJECT_T;
        l_application_code VARCHAR2(250);
        l_worker_instance_id VARCHAR2(250);
        l_host_id VARCHAR2(250);
        l_boot_id VARCHAR2(250);
        l_application_id NUMBER;
        l_job_id NUMBER;
        l_attempt_id NUMBER;
        l_stored_host_id VARCHAR2(250);
        l_stored_boot_id VARCHAR2(250);
        l_result JSON_OBJECT_T := JSON_OBJECT_T();
        l_active JSON_OBJECT_T;
        l_details JSON_OBJECT_T;
        l_token RAW(16);
        l_attempt_number NUMBER;
    BEGIN
        SAVEPOINT api_call;
        l_body := parse_body(p_body);
        l_application_code := required_string(l_body, 'application_code');
        l_worker_instance_id := required_string(l_body, 'worker_instance_id');
        l_host_id := required_string(l_body, 'host_id');
        l_boot_id := required_string(l_body, 'boot_id');
        l_application_id := application_id(l_application_code);

        BEGIN
            SELECT j.job_id, a.job_attempt_id, a.host_id, a.boot_id,
                   a.execution_token, a.attempt_number
              INTO l_job_id, l_attempt_id, l_stored_host_id, l_stored_boot_id,
                   l_token, l_attempt_number
              FROM jobs j
              JOIN job_attempts a ON a.job_id = j.job_id AND a.ended_at IS NULL
             WHERE j.application_id = l_application_id
               AND j.status IN ('CLAIMED', 'RUNNING', 'UNKNOWN')
             FOR UPDATE OF j.status;

            IF l_stored_host_id = l_host_id AND l_stored_boot_id <> l_boot_id THEN
                UPDATE job_attempts
                   SET ended_at = SYSTIMESTAMP,
                       end_reason = 'HOST_RESTART'
                 WHERE job_attempt_id = l_attempt_id;
                UPDATE jobs
                   SET status = 'INTERRUPTED', updated_at = SYSTIMESTAMP,
                       completed_at = SYSTIMESTAMP
                 WHERE job_id = l_job_id;
                l_details := JSON_OBJECT_T();
                l_details.put('reason', 'HOST_RESTART');
                add_event(l_job_id, 'JOB_INTERRUPTED', 'SYSTEM', 'JOBS_APP',
                          l_details.to_clob());
                l_result.put('interrupted_job_id', l_job_id);
                l_result.put_null('active_job');
            ELSE
                l_active := JSON_OBJECT_T.parse(claim_response(l_job_id, l_token,
                                                                l_attempt_number));
                l_result.put_null('interrupted_job_id');
                l_result.put('active_job', l_active);
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_result.put_null('interrupted_job_id');
                l_result.put_null('active_job');
        END;

        o_http_status := 200;
        RETURN l_result.to_clob();
    EXCEPTION
        WHEN OTHERS THEN
            RETURN TO_CLOB(rollback_error(SQLCODE, SQLERRM, o_http_status));
    END;

    FUNCTION claim_job(p_body CLOB, o_http_status OUT PLS_INTEGER) RETURN CLOB IS
        l_body JSON_OBJECT_T;
        l_application_code VARCHAR2(250);
        l_claim_request_id VARCHAR2(250);
        l_worker_instance_id VARCHAR2(250);
        l_host_id VARCHAR2(250);
        l_boot_id VARCHAR2(250);
        l_application_id NUMBER;
        l_job_id NUMBER;
        l_job_application_id NUMBER;
        l_attempt_number NUMBER;
        l_execution_token RAW(16);
        l_count NUMBER;
        l_existing_worker VARCHAR2(250);
        l_existing_host VARCHAR2(250);
        l_existing_boot VARCHAR2(250);
    BEGIN
        SAVEPOINT api_call;
        l_body := parse_body(p_body);
        l_application_code := required_string(l_body, 'application_code');
        l_claim_request_id := required_string(l_body, 'claim_request_id');
        l_worker_instance_id := required_string(l_body, 'worker_instance_id');
        l_host_id := required_string(l_body, 'host_id');
        l_boot_id := required_string(l_body, 'boot_id');
        l_application_id := application_id(l_application_code);

        BEGIN
            SELECT a.job_id, a.attempt_number, a.execution_token,
                   a.worker_instance_id, a.host_id, a.boot_id
              INTO l_job_id, l_attempt_number, l_execution_token,
                   l_existing_worker, l_existing_host, l_existing_boot
              FROM job_attempts a
              JOIN jobs j ON j.job_id = a.job_id
             WHERE a.claim_request_id = l_claim_request_id
               AND j.application_id = l_application_id;
            IF l_existing_worker <> l_worker_instance_id
               OR l_existing_host <> l_host_id OR l_existing_boot <> l_boot_id THEN
                fail(c_claim_conflict,
                     'claim request id is already used with different worker data');
            END IF;
            o_http_status := 200;
            RETURN claim_response(l_job_id, l_execution_token, l_attempt_number);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN NULL;
        END;

        SELECT COUNT(*) INTO l_count
          FROM jobs
         WHERE status IN ('CLAIMED', 'RUNNING', 'UNKNOWN');
        IF l_count > 0 THEN
            o_http_status := 204;
            RETURN NULL;
        END IF;

        BEGIN
            SELECT j.job_id, j.application_id
              INTO l_job_id, l_job_application_id
              FROM jobs j
             WHERE j.job_id = (
                   SELECT job_id
                     FROM (
                           SELECT q.job_id
                             FROM jobs q
                            WHERE q.status = 'QUEUED'
                              AND (q.previous_job_id IS NULL OR EXISTS (
                                  SELECT 1 FROM jobs p
                                   WHERE p.job_id = q.previous_job_id
                                     AND p.status = 'SUCCEEDED'))
                            ORDER BY q.queue_order
                          )
                    WHERE ROWNUM = 1
             )
             FOR UPDATE SKIP LOCKED;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                o_http_status := 204;
                RETURN NULL;
        END;

        IF l_job_application_id <> l_application_id THEN
            o_http_status := 204;
            RETURN NULL;
        END IF;

        SELECT COUNT(*) INTO l_count
          FROM jobs
         WHERE status IN ('CLAIMED', 'RUNNING', 'UNKNOWN');
        IF l_count > 0 THEN
            o_http_status := 204;
            RETURN NULL;
        END IF;

        SELECT NVL(MAX(attempt_number), 0) + 1
          INTO l_attempt_number
          FROM job_attempts
         WHERE job_id = l_job_id;

        INSERT INTO job_attempts(job_id, attempt_number, claim_request_id,
                                 worker_instance_id, host_id, boot_id)
        VALUES (l_job_id, l_attempt_number, l_claim_request_id,
                l_worker_instance_id, l_host_id, l_boot_id)
        RETURNING execution_token INTO l_execution_token;

        UPDATE jobs
           SET status = 'CLAIMED', updated_at = SYSTIMESTAMP
         WHERE job_id = l_job_id;
        add_event(l_job_id, 'JOB_CLAIMED', 'WORKER', l_worker_instance_id);

        o_http_status := 200;
        RETURN claim_response(l_job_id, l_execution_token, l_attempt_number);
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            ROLLBACK TO api_call;
            o_http_status := 204;
            RETURN NULL;
        WHEN OTHERS THEN
            RETURN TO_CLOB(rollback_error(SQLCODE, SQLERRM, o_http_status));
    END;

    PROCEDURE active_attempt(p_job_id NUMBER, p_body CLOB,
                             o_body OUT JSON_OBJECT_T,
                             o_worker_instance_id OUT VARCHAR2,
                             o_attempt_id OUT NUMBER,
                             o_job_status OUT VARCHAR2,
                             o_token OUT RAW,
                             o_attempt_ended OUT TIMESTAMP) IS
        l_application_code VARCHAR2(250);
        l_application_id NUMBER;
        l_host_id VARCHAR2(250);
        l_boot_id VARCHAR2(250);
        l_stored_host VARCHAR2(250);
        l_stored_boot VARCHAR2(250);
    BEGIN
        o_body := parse_body(p_body);
        l_application_code := required_string(o_body, 'application_code');
        o_worker_instance_id := required_string(o_body, 'worker_instance_id');
        l_host_id := required_string(o_body, 'host_id');
        l_boot_id := required_string(o_body, 'boot_id');
        o_token := token_raw(required_string(o_body, 'execution_token'));
        l_application_id := application_id(l_application_code);

        SELECT a.job_attempt_id, j.status, a.host_id, a.boot_id, a.ended_at
          INTO o_attempt_id, o_job_status, l_stored_host, l_stored_boot,
               o_attempt_ended
          FROM jobs j
          JOIN job_attempts a ON a.job_id = j.job_id
         WHERE j.job_id = p_job_id
           AND j.application_id = l_application_id
           AND a.execution_token = o_token
         FOR UPDATE OF j.status, a.ended_at;

        IF l_stored_host <> l_host_id OR l_stored_boot <> l_boot_id THEN
            fail(c_invalid_token, 'host or boot id does not match the execution token');
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            fail(c_invalid_token, 'execution token is not valid for the job');
    END;

    FUNCTION start_job(p_job_id NUMBER, p_body CLOB,
                       o_http_status OUT PLS_INTEGER) RETURN VARCHAR2 IS
        l_body JSON_OBJECT_T;
        l_worker_instance_id VARCHAR2(250);
        l_attempt_id NUMBER;
        l_status VARCHAR2(250);
        l_token RAW(16);
        l_started_at TIMESTAMP;
        l_attempt_ended TIMESTAMP;
        l_result JSON_OBJECT_T := JSON_OBJECT_T();
    BEGIN
        SAVEPOINT api_call;
        active_attempt(p_job_id, p_body, l_body, l_worker_instance_id,
                       l_attempt_id, l_status, l_token, l_attempt_ended);
        IF l_attempt_ended IS NOT NULL THEN
            fail(c_invalid_token, 'execution token belongs to a completed attempt');
        END IF;
        IF l_status = 'CLAIMED' THEN
            UPDATE job_attempts
               SET started_at = NVL(started_at, SYSTIMESTAMP),
                   last_heartbeat_at = SYSTIMESTAMP,
                   worker_instance_id = l_worker_instance_id
             WHERE job_attempt_id = l_attempt_id
             RETURNING started_at INTO l_started_at;
            UPDATE jobs SET status = 'RUNNING', updated_at = SYSTIMESTAMP
             WHERE job_id = p_job_id;
            add_event(p_job_id, 'JOB_STARTED', 'WORKER', l_worker_instance_id);
        ELSIF l_status = 'RUNNING' THEN
            SELECT started_at INTO l_started_at FROM job_attempts
             WHERE job_attempt_id = l_attempt_id;
        ELSE
            fail(c_invalid_state, 'job cannot be started from status ' || l_status);
        END IF;
        o_http_status := 200;
        l_result.put('job_id', p_job_id);
        l_result.put('status', 'RUNNING');
        l_result.put('started_at', utc_text(l_started_at));
        RETURN l_result.to_string();
    EXCEPTION
        WHEN OTHERS THEN
            RETURN rollback_error(SQLCODE, SQLERRM, o_http_status);
    END;

    FUNCTION heartbeat(p_job_id NUMBER, p_body CLOB,
                       o_http_status OUT PLS_INTEGER) RETURN VARCHAR2 IS
        l_body JSON_OBJECT_T;
        l_worker_instance_id VARCHAR2(250);
        l_attempt_id NUMBER;
        l_status VARCHAR2(250);
        l_token RAW(16);
        l_heartbeat TIMESTAMP;
        l_attempt_ended TIMESTAMP;
        l_result JSON_OBJECT_T := JSON_OBJECT_T();
    BEGIN
        SAVEPOINT api_call;
        active_attempt(p_job_id, p_body, l_body, l_worker_instance_id,
                       l_attempt_id, l_status, l_token, l_attempt_ended);
        IF l_attempt_ended IS NOT NULL THEN
            fail(c_invalid_token, 'execution token belongs to a completed attempt');
        END IF;
        IF l_status NOT IN ('RUNNING', 'UNKNOWN') THEN
            fail(c_invalid_state, 'heartbeat is not allowed for status ' || l_status);
        END IF;
        l_heartbeat := SYSTIMESTAMP;
        UPDATE job_attempts
           SET last_heartbeat_at = l_heartbeat,
               worker_instance_id = l_worker_instance_id
         WHERE job_attempt_id = l_attempt_id;
        IF l_status = 'UNKNOWN' THEN
            UPDATE jobs SET status = 'RUNNING', updated_at = SYSTIMESTAMP
             WHERE job_id = p_job_id;
            add_event(p_job_id, 'JOB_RECOVERED', 'WORKER', l_worker_instance_id);
        ELSE
            UPDATE jobs SET updated_at = SYSTIMESTAMP WHERE job_id = p_job_id;
        END IF;
        o_http_status := 200;
        l_result.put('job_id', p_job_id);
        l_result.put('status', 'RUNNING');
        l_result.put('last_heartbeat_at', utc_text(l_heartbeat));
        RETURN l_result.to_string();
    EXCEPTION
        WHEN OTHERS THEN
            RETURN rollback_error(SQLCODE, SQLERRM, o_http_status);
    END;

    FUNCTION complete_job(p_job_id NUMBER, p_body CLOB,
                          o_http_status OUT PLS_INTEGER) RETURN VARCHAR2 IS
        l_body JSON_OBJECT_T;
        l_worker_instance_id VARCHAR2(250);
        l_attempt_id NUMBER;
        l_status VARCHAR2(250);
        l_token RAW(16);
        l_outcome VARCHAR2(250);
        l_end_reason VARCHAR2(250);
        l_exit_code NUMBER;
        l_completed_at TIMESTAMP;
        l_attempt_ended TIMESTAMP;
        l_result JSON_OBJECT_T := JSON_OBJECT_T();
    BEGIN
        SAVEPOINT api_call;
        active_attempt(p_job_id, p_body, l_body, l_worker_instance_id,
                       l_attempt_id, l_status, l_token, l_attempt_ended);
        l_outcome := UPPER(required_string(l_body, 'outcome'));
        IF l_outcome NOT IN ('SUCCEEDED', 'FAILED', 'INTERRUPTED', 'UNKNOWN') THEN
            fail(c_invalid_request, 'outcome is invalid');
        END IF;
        l_exit_code := optional_number(l_body, 'exit_code');
        IF l_body.has('end_reason') THEN
            l_end_reason := required_string(l_body, 'end_reason');
        END IF;

        IF l_status IN ('SUCCEEDED', 'FAILED', 'INTERRUPTED') THEN
            IF l_status <> l_outcome THEN
                fail(c_invalid_state, 'job is already completed with another outcome');
            END IF;
            SELECT completed_at INTO l_completed_at FROM jobs WHERE job_id = p_job_id;
        ELSIF l_status NOT IN ('CLAIMED', 'RUNNING', 'UNKNOWN') THEN
            fail(c_invalid_state, 'job cannot be completed from status ' || l_status);
        ELSIF l_attempt_ended IS NOT NULL THEN
            fail(c_invalid_token, 'execution token belongs to a completed attempt');
        ELSIF l_status = 'UNKNOWN' AND l_outcome = 'UNKNOWN' THEN
            l_completed_at := NULL;
        ELSIF l_outcome = 'UNKNOWN' THEN
            UPDATE job_attempts
               SET last_heartbeat_at = SYSTIMESTAMP,
                   worker_instance_id = l_worker_instance_id,
                   end_reason = l_end_reason
             WHERE job_attempt_id = l_attempt_id;
            UPDATE jobs SET status = 'UNKNOWN', updated_at = SYSTIMESTAMP
             WHERE job_id = p_job_id;
            add_event(p_job_id, 'JOB_UNKNOWN', 'WORKER', l_worker_instance_id);
        ELSE
            l_completed_at := SYSTIMESTAMP;
            UPDATE job_attempts
               SET ended_at = l_completed_at, exit_code = l_exit_code,
                   end_reason = l_end_reason,
                   worker_instance_id = l_worker_instance_id
             WHERE job_attempt_id = l_attempt_id;
            UPDATE jobs
               SET status = l_outcome, updated_at = l_completed_at,
                   completed_at = l_completed_at
             WHERE job_id = p_job_id;
            add_event(p_job_id, 'JOB_' || l_outcome, 'WORKER', l_worker_instance_id);
        END IF;

        o_http_status := 200;
        l_result.put('job_id', p_job_id);
        l_result.put('status', l_outcome);
        IF l_completed_at IS NULL THEN l_result.put_null('completed_at');
        ELSE l_result.put('completed_at', utc_text(l_completed_at)); END IF;
        RETURN l_result.to_string();
    EXCEPTION
        WHEN OTHERS THEN
            RETURN rollback_error(SQLCODE, SQLERRM, o_http_status);
    END;

    FUNCTION admin_actor(p_body CLOB) RETURN VARCHAR2 IS
        l_body JSON_OBJECT_T;
    BEGIN
        l_body := parse_body(p_body);
        RETURN required_string(l_body, 'actor_id');
    END;

    FUNCTION admin_job_object(p_job_id NUMBER, p_include_details BOOLEAN)
        RETURN JSON_OBJECT_T IS
        l_result JSON_OBJECT_T := JSON_OBJECT_T();
        l_attempts JSON_ARRAY_T := JSON_ARRAY_T();
        l_events JSON_ARRAY_T := JSON_ARRAY_T();
        l_item JSON_OBJECT_T;
        l_application_code applications.application_code%TYPE;
        l_application_name applications.display_name%TYPE;
        l_job_type_code job_types.job_type_code%TYPE;
        l_job_type_name job_types.display_name%TYPE;
        l_application_job_id jobs.application_job_id%TYPE;
        l_previous_job_id jobs.previous_job_id%TYPE;
        l_status jobs.status%TYPE;
        l_queue_order jobs.queue_order%TYPE;
        l_parameters CLOB;
        l_created_at jobs.created_at%TYPE;
        l_updated_at jobs.updated_at%TYPE;
        l_completed_at jobs.completed_at%TYPE;
    BEGIN
        SELECT a.application_code, a.display_name,
               jt.job_type_code, jt.display_name,
               j.application_job_id, j.previous_job_id, j.status,
               j.queue_order, JSON_SERIALIZE(j.parameters_json RETURNING CLOB),
               j.created_at, j.updated_at, j.completed_at
          INTO l_application_code, l_application_name,
               l_job_type_code, l_job_type_name,
               l_application_job_id, l_previous_job_id, l_status,
               l_queue_order, l_parameters,
               l_created_at, l_updated_at, l_completed_at
          FROM jobs j
          JOIN applications a ON a.application_id = j.application_id
          JOIN job_types jt ON jt.job_type_id = j.job_type_id
         WHERE j.job_id = p_job_id;

        l_result.put('job_id', p_job_id);
        l_result.put('application_code', l_application_code);
        l_result.put('application_name', l_application_name);
        l_result.put('job_type_code', l_job_type_code);
        l_result.put('job_type_name', l_job_type_name);
        l_result.put('application_job_id', l_application_job_id);
        IF l_previous_job_id IS NULL THEN l_result.put_null('previous_job_id');
        ELSE l_result.put('previous_job_id', l_previous_job_id); END IF;
        l_result.put('status', l_status);
        l_result.put('queue_order', l_queue_order);
        l_result.put('created_at', utc_text(l_created_at));
        IF l_updated_at IS NULL THEN l_result.put_null('updated_at');
        ELSE l_result.put('updated_at', utc_text(l_updated_at)); END IF;
        IF l_completed_at IS NULL THEN l_result.put_null('completed_at');
        ELSE l_result.put('completed_at', utc_text(l_completed_at)); END IF;

        IF p_include_details THEN
            l_result.put('parameters', JSON_OBJECT_T.parse(l_parameters));

            FOR r IN (
                SELECT attempt_number, worker_instance_id, host_id, boot_id,
                       claimed_at, started_at, last_heartbeat_at, ended_at,
                       exit_code, end_reason
                  FROM job_attempts
                 WHERE job_id = p_job_id
                 ORDER BY attempt_number
            ) LOOP
                l_item := JSON_OBJECT_T();
                l_item.put('attempt_number', r.attempt_number);
                l_item.put('worker_instance_id', r.worker_instance_id);
                l_item.put('host_id', r.host_id);
                l_item.put('boot_id', r.boot_id);
                l_item.put('claimed_at', utc_text(r.claimed_at));
                IF r.started_at IS NULL THEN l_item.put_null('started_at');
                ELSE l_item.put('started_at', utc_text(r.started_at)); END IF;
                IF r.last_heartbeat_at IS NULL THEN l_item.put_null('last_heartbeat_at');
                ELSE l_item.put('last_heartbeat_at', utc_text(r.last_heartbeat_at)); END IF;
                IF r.ended_at IS NULL THEN l_item.put_null('ended_at');
                ELSE l_item.put('ended_at', utc_text(r.ended_at)); END IF;
                IF r.exit_code IS NULL THEN l_item.put_null('exit_code');
                ELSE l_item.put('exit_code', r.exit_code); END IF;
                IF r.end_reason IS NULL THEN l_item.put_null('end_reason');
                ELSE l_item.put('end_reason', r.end_reason); END IF;
                l_attempts.append(l_item);
            END LOOP;
            l_result.put('attempts', l_attempts);

            FOR r IN (
                SELECT event_type, actor_type, actor_id,
                       JSON_SERIALIZE(details_json RETURNING CLOB) details_json,
                       created_at
                  FROM job_events
                 WHERE job_id = p_job_id
                 ORDER BY created_at, job_event_id
            ) LOOP
                l_item := JSON_OBJECT_T();
                l_item.put('event_type', r.event_type);
                l_item.put('actor_type', r.actor_type);
                l_item.put('actor_id', r.actor_id);
                IF r.details_json IS NULL THEN l_item.put_null('details');
                ELSE l_item.put('details', JSON_ELEMENT_T.parse(r.details_json)); END IF;
                l_item.put('created_at', utc_text(r.created_at));
                l_events.append(l_item);
            END LOOP;
            l_result.put('events', l_events);
        END IF;

        RETURN l_result;
    END;

    FUNCTION admin_job_clob(p_job_id NUMBER, p_include_details BOOLEAN := FALSE)
        RETURN CLOB IS
        l_result JSON_OBJECT_T;
    BEGIN
        l_result := admin_job_object(p_job_id, p_include_details);
        RETURN l_result.to_clob();
    END;

    FUNCTION admin_job_text(p_job_id NUMBER) RETURN VARCHAR2 IS
        l_result JSON_OBJECT_T;
    BEGIN
        l_result := admin_job_object(p_job_id, FALSE);
        RETURN l_result.to_string();
    END;

    FUNCTION admin_queue(o_http_status OUT PLS_INTEGER) RETURN CLOB IS
        l_result JSON_OBJECT_T := JSON_OBJECT_T();
        l_active JSON_OBJECT_T;
        l_queued JSON_ARRAY_T := JSON_ARRAY_T();
        l_held JSON_ARRAY_T := JSON_ARRAY_T();
    BEGIN
        l_result.put_null('active_job');
        FOR r IN (
            SELECT job_id
              FROM jobs
             WHERE status IN ('CLAIMED', 'RUNNING', 'UNKNOWN')
             ORDER BY queue_order
        ) LOOP
            l_active := admin_job_object(r.job_id, FALSE);
            l_result.put('active_job', l_active);
        END LOOP;

        FOR r IN (
            SELECT job_id FROM jobs
             WHERE status = 'QUEUED'
             ORDER BY queue_order
        ) LOOP
            l_queued.append(admin_job_object(r.job_id, FALSE));
        END LOOP;
        l_result.put('queued_jobs', l_queued);

        FOR r IN (
            SELECT job_id FROM jobs
             WHERE status = 'HELD'
             ORDER BY updated_at NULLS LAST, created_at, job_id
        ) LOOP
            l_held.append(admin_job_object(r.job_id, FALSE));
        END LOOP;
        l_result.put('held_jobs', l_held);

        o_http_status := 200;
        RETURN l_result.to_clob();
    EXCEPTION
        WHEN OTHERS THEN
            RETURN TO_CLOB(error_response(SQLCODE, SQLERRM, o_http_status));
    END;

    FUNCTION admin_job(p_job_id NUMBER, o_http_status OUT PLS_INTEGER) RETURN CLOB IS
        l_result JSON_OBJECT_T;
    BEGIN
        BEGIN
            l_result := admin_job_object(p_job_id, TRUE);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                fail(c_job_not_found, 'job was not found');
        END;
        o_http_status := 200;
        RETURN l_result.to_clob();
    EXCEPTION
        WHEN OTHERS THEN
            RETURN TO_CLOB(error_response(SQLCODE, SQLERRM, o_http_status));
    END;

    FUNCTION admin_move_job(p_job_id NUMBER, p_direction VARCHAR2, p_body CLOB,
                            o_http_status OUT PLS_INTEGER) RETURN VARCHAR2 IS
        l_actor_id VARCHAR2(250);
        l_direction VARCHAR2(250) := UPPER(TRIM(p_direction));
        l_status jobs.status%TYPE;
        l_old_order jobs.queue_order%TYPE;
        l_new_order jobs.queue_order%TYPE;
        l_previous_job_id jobs.previous_job_id%TYPE;
        l_other_job_id jobs.job_id%TYPE;
        l_other_order jobs.queue_order%TYPE;
        l_other_previous_job_id jobs.previous_job_id%TYPE;
        l_count NUMBER;
        l_details JSON_OBJECT_T;
    BEGIN
        SAVEPOINT api_call;
        l_actor_id := admin_actor(p_body);
        IF l_direction NOT IN ('UP', 'DOWN', 'FIRST', 'LAST') THEN
            fail(c_invalid_request, 'move direction is invalid');
        END IF;

        LOCK TABLE jobs IN SHARE ROW EXCLUSIVE MODE;
        BEGIN
            SELECT status, queue_order, previous_job_id
              INTO l_status, l_old_order, l_previous_job_id
              FROM jobs
             WHERE job_id = p_job_id
             FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN fail(c_job_not_found, 'job was not found');
        END;
        IF l_status <> 'QUEUED' THEN
            fail(c_invalid_state, 'only a queued job can be moved');
        END IF;

        IF l_direction = 'UP' THEN
            BEGIN
                SELECT job_id, queue_order, previous_job_id
                  INTO l_other_job_id, l_other_order, l_other_previous_job_id
                  FROM (
                      SELECT job_id, queue_order, previous_job_id
                        FROM jobs
                       WHERE status = 'QUEUED' AND queue_order < l_old_order
                       ORDER BY queue_order DESC
                  )
                 WHERE ROWNUM = 1;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN l_other_job_id := NULL;
            END;
            IF l_other_job_id IS NOT NULL THEN
                IF l_previous_job_id = l_other_job_id THEN
                    fail(c_dependency_conflict,
                         'job cannot be moved before its previous job');
                END IF;
                UPDATE jobs SET status = 'HELD' WHERE job_id = l_other_job_id;
                UPDATE jobs SET queue_order = l_other_order, updated_at = SYSTIMESTAMP
                 WHERE job_id = p_job_id;
                UPDATE jobs SET status = 'QUEUED', queue_order = l_old_order,
                                updated_at = SYSTIMESTAMP
                 WHERE job_id = l_other_job_id;
                l_new_order := l_other_order;
            ELSE
                l_new_order := l_old_order;
            END IF;
        ELSIF l_direction = 'DOWN' THEN
            BEGIN
                SELECT job_id, queue_order, previous_job_id
                  INTO l_other_job_id, l_other_order, l_other_previous_job_id
                  FROM (
                      SELECT job_id, queue_order, previous_job_id
                        FROM jobs
                       WHERE status = 'QUEUED' AND queue_order > l_old_order
                       ORDER BY queue_order
                  )
                 WHERE ROWNUM = 1;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN l_other_job_id := NULL;
            END;
            IF l_other_job_id IS NOT NULL THEN
                IF l_other_previous_job_id = p_job_id THEN
                    fail(c_dependency_conflict,
                         'job cannot be moved after a dependent job');
                END IF;
                UPDATE jobs SET status = 'HELD' WHERE job_id = l_other_job_id;
                UPDATE jobs SET queue_order = l_other_order, updated_at = SYSTIMESTAMP
                 WHERE job_id = p_job_id;
                UPDATE jobs SET status = 'QUEUED', queue_order = l_old_order,
                                updated_at = SYSTIMESTAMP
                 WHERE job_id = l_other_job_id;
                l_new_order := l_other_order;
            ELSE
                l_new_order := l_old_order;
            END IF;
        ELSIF l_direction = 'FIRST' THEN
            SELECT COUNT(*) INTO l_count
              FROM jobs
             WHERE status = 'QUEUED'
               AND queue_order < l_old_order;
            IF l_count = 0 THEN
                l_new_order := l_old_order;
            ELSE
                SELECT COUNT(*) INTO l_count
                  FROM jobs
                 WHERE job_id = l_previous_job_id
                   AND status = 'QUEUED';
                IF l_count > 0 THEN
                    fail(c_dependency_conflict,
                         'job cannot be moved before its previous job');
                END IF;
                SELECT MIN(queue_order) - 100
                  INTO l_new_order
                  FROM jobs
                 WHERE status = 'QUEUED';
                UPDATE jobs SET queue_order = l_new_order, updated_at = SYSTIMESTAMP
                 WHERE job_id = p_job_id;
            END IF;
        ELSE
            SELECT COUNT(*) INTO l_count
              FROM jobs
             WHERE status = 'QUEUED'
               AND queue_order > l_old_order;
            IF l_count = 0 THEN
                l_new_order := l_old_order;
            ELSE
                SELECT COUNT(*) INTO l_count
                  FROM jobs
                 WHERE previous_job_id = p_job_id
                   AND status = 'QUEUED';
                IF l_count > 0 THEN
                    fail(c_dependency_conflict,
                         'job cannot be moved after a dependent job');
                END IF;
                l_new_order := queue_order_seq.NEXTVAL;
                UPDATE jobs SET queue_order = l_new_order, updated_at = SYSTIMESTAMP
                 WHERE job_id = p_job_id;
            END IF;
        END IF;

        IF l_new_order <> l_old_order THEN
            l_details := JSON_OBJECT_T();
            l_details.put('direction', LOWER(l_direction));
            l_details.put('old_queue_order', l_old_order);
            l_details.put('new_queue_order', l_new_order);
            add_event(p_job_id, 'JOB_MOVED', 'USER', l_actor_id,
                      l_details.to_clob());
        END IF;
        o_http_status := 200;
        RETURN admin_job_text(p_job_id);
    EXCEPTION
        WHEN OTHERS THEN
            RETURN rollback_error(SQLCODE, SQLERRM, o_http_status);
    END;

    FUNCTION admin_hold_job(p_job_id NUMBER, p_body CLOB,
                            o_http_status OUT PLS_INTEGER) RETURN VARCHAR2 IS
        l_actor_id VARCHAR2(250);
        l_status jobs.status%TYPE;
    BEGIN
        SAVEPOINT api_call;
        l_actor_id := admin_actor(p_body);
        LOCK TABLE jobs IN SHARE ROW EXCLUSIVE MODE;
        BEGIN
            SELECT status INTO l_status FROM jobs
             WHERE job_id = p_job_id FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN fail(c_job_not_found, 'job was not found');
        END;
        IF l_status <> 'QUEUED' THEN
            fail(c_invalid_state, 'only a queued job can be held');
        END IF;
        UPDATE jobs SET status = 'HELD', updated_at = SYSTIMESTAMP
         WHERE job_id = p_job_id;
        add_event(p_job_id, 'JOB_HELD', 'USER', l_actor_id);
        o_http_status := 200;
        RETURN admin_job_text(p_job_id);
    EXCEPTION
        WHEN OTHERS THEN
            RETURN rollback_error(SQLCODE, SQLERRM, o_http_status);
    END;

    FUNCTION admin_resume_job(p_job_id NUMBER, p_body CLOB,
                              o_http_status OUT PLS_INTEGER) RETURN VARCHAR2 IS
        l_actor_id VARCHAR2(250);
        l_status jobs.status%TYPE;
        l_queue_order jobs.queue_order%TYPE;
        l_details JSON_OBJECT_T;
    BEGIN
        SAVEPOINT api_call;
        l_actor_id := admin_actor(p_body);
        LOCK TABLE jobs IN SHARE ROW EXCLUSIVE MODE;
        BEGIN
            SELECT status INTO l_status FROM jobs
             WHERE job_id = p_job_id FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN fail(c_job_not_found, 'job was not found');
        END;
        IF l_status <> 'HELD' THEN
            fail(c_invalid_state, 'only a held job can be resumed');
        END IF;
        l_queue_order := queue_order_seq.NEXTVAL;
        UPDATE jobs SET status = 'QUEUED', queue_order = l_queue_order,
                        updated_at = SYSTIMESTAMP
         WHERE job_id = p_job_id;
        l_details := JSON_OBJECT_T();
        l_details.put('new_queue_order', l_queue_order);
        add_event(p_job_id, 'JOB_RESUMED', 'USER', l_actor_id,
                  l_details.to_clob());
        o_http_status := 200;
        RETURN admin_job_text(p_job_id);
    EXCEPTION
        WHEN OTHERS THEN
            RETURN rollback_error(SQLCODE, SQLERRM, o_http_status);
    END;

    FUNCTION admin_remove_job(p_job_id NUMBER, p_body CLOB,
                              o_http_status OUT PLS_INTEGER) RETURN VARCHAR2 IS
        l_actor_id VARCHAR2(250);
        l_status jobs.status%TYPE;
        l_completed_at TIMESTAMP;
    BEGIN
        SAVEPOINT api_call;
        l_actor_id := admin_actor(p_body);
        LOCK TABLE jobs IN SHARE ROW EXCLUSIVE MODE;
        BEGIN
            SELECT status INTO l_status FROM jobs
             WHERE job_id = p_job_id FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN fail(c_job_not_found, 'job was not found');
        END;
        IF l_status NOT IN ('QUEUED', 'HELD') THEN
            fail(c_invalid_state, 'only a queued or held job can be removed');
        END IF;
        l_completed_at := SYSTIMESTAMP;
        UPDATE jobs SET status = 'REMOVED', updated_at = l_completed_at,
                        completed_at = l_completed_at
         WHERE job_id = p_job_id;
        add_event(p_job_id, 'JOB_REMOVED', 'USER', l_actor_id);
        o_http_status := 200;
        RETURN admin_job_text(p_job_id);
    EXCEPTION
        WHEN OTHERS THEN
            RETURN rollback_error(SQLCODE, SQLERRM, o_http_status);
    END;

END pkg_jobs_api;
/

SHOW ERRORS PACKAGE pkg_jobs_api;
SHOW ERRORS PACKAGE BODY pkg_jobs_api;
