-- MVP1 ORDS handlers.
-- Run in SQL Developer as JOBS_API after the execute grant.

SET DEFINE OFF;

DECLARE
    c_module CONSTANT VARCHAR2(30) := 'jobs.api';
BEGIN
    ORDS.DEFINE_MODULE(
        p_module_name    => c_module,
        p_base_path      => '/',
        p_items_per_page => 0,
        p_status         => 'PUBLISHED'
    );

    ORDS.CREATE_ROLE(p_role_name => 'jobs.api.client');
    ORDS.DEFINE_PRIVILEGE(
        p_privilege_name => 'jobs.api.auth',
        p_roles          => OWA.VC_ARR('jobs.api.client'),
        p_label          => 'Queue API OAuth authentication',
        p_description    => 'Requires an OAuth client with the jobs.api.client role.'
    );
    ORDS.SET_MODULE_PRIVILEGE(
        p_module_name    => c_module,
        p_privilege_name => 'jobs.api.auth'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'application/jobs');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'application/jobs',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_source => q'~
            DECLARE
                l_body CLOB := :body_text;
                l_json VARCHAR2(4000);
                l_status PLS_INTEGER;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.submit_job(l_body, l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE);
                owa_util.http_header_close;
                htp.prn(l_json);
            END;
        ~'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'application/jobs/:job_id');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'application/jobs/:job_id',
        p_method => 'GET',
        p_source_type => ORDS.source_type_plsql,
        p_source => q'~
            DECLARE
                l_json VARCHAR2(4000);
                l_status PLS_INTEGER;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.get_job_status(
                    TO_NUMBER(:job_id), :application_code, l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE);
                owa_util.http_header_close;
                htp.prn(l_json);
            END;
        ~'
    );
    ORDS.DEFINE_PARAMETER(
        p_module_name        => c_module,
        p_pattern            => 'application/jobs/:job_id',
        p_method             => 'GET',
        p_name               => 'application_code',
        p_bind_variable_name => 'application_code',
        p_source_type        => 'URI',
        p_param_type         => 'STRING',
        p_access_method      => 'IN'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'worker/startup');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'worker/startup',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_source => q'~
            DECLARE
                l_body CLOB := :body_text; l_json CLOB; l_status PLS_INTEGER;
                l_pos PLS_INTEGER := 1;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.worker_startup(l_body, l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE); owa_util.http_header_close;
                WHILE l_json IS NOT NULL AND l_pos <= dbms_lob.getlength(l_json) LOOP
                    htp.prn(dbms_lob.substr(l_json, 8000, l_pos)); l_pos := l_pos + 8000;
                END LOOP;
            END;
        ~'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'worker/claim');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'worker/claim',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_source => q'~
            DECLARE
                l_body CLOB := :body_text; l_json CLOB; l_status PLS_INTEGER;
                l_pos PLS_INTEGER := 1;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.claim_job(l_body, l_status);
                :status_code := l_status;
                IF l_status <> 204 THEN
                    owa_util.mime_header('application/json', FALSE); owa_util.http_header_close;
                    WHILE l_json IS NOT NULL AND l_pos <= dbms_lob.getlength(l_json) LOOP
                        htp.prn(dbms_lob.substr(l_json, 8000, l_pos)); l_pos := l_pos + 8000;
                    END LOOP;
                END IF;
            END;
        ~'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'worker/jobs/:job_id/start');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'worker/jobs/:job_id/start',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_source => q'~
            DECLARE
                l_body CLOB := :body_text; l_json VARCHAR2(4000);
                l_status PLS_INTEGER;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.start_job(TO_NUMBER(:job_id), l_body, l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE); owa_util.http_header_close;
                htp.prn(l_json);
            END;
        ~'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'worker/jobs/:job_id/heartbeat');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'worker/jobs/:job_id/heartbeat',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_source => q'~
            DECLARE
                l_body CLOB := :body_text; l_json VARCHAR2(4000);
                l_status PLS_INTEGER;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.heartbeat(TO_NUMBER(:job_id), l_body, l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE); owa_util.http_header_close;
                htp.prn(l_json);
            END;
        ~'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'worker/jobs/:job_id/complete');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'worker/jobs/:job_id/complete',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_source => q'~
            DECLARE
                l_body CLOB := :body_text; l_json VARCHAR2(4000);
                l_status PLS_INTEGER;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.complete_job(TO_NUMBER(:job_id), l_body, l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE); owa_util.http_header_close;
                htp.prn(l_json);
            END;
        ~'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'admin/queue');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'admin/queue',
        p_method => 'GET',
        p_source_type => ORDS.source_type_plsql,
        p_source => q'~
            DECLARE
                l_json CLOB; l_status PLS_INTEGER; l_pos PLS_INTEGER := 1;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.admin_queue(l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE); owa_util.http_header_close;
                WHILE l_json IS NOT NULL AND l_pos <= dbms_lob.getlength(l_json) LOOP
                    htp.prn(dbms_lob.substr(l_json, 8000, l_pos)); l_pos := l_pos + 8000;
                END LOOP;
            END;
        ~'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'admin/jobs/:job_id');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'admin/jobs/:job_id',
        p_method => 'GET',
        p_source_type => ORDS.source_type_plsql,
        p_source => q'~
            DECLARE
                l_json CLOB; l_status PLS_INTEGER; l_pos PLS_INTEGER := 1;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.admin_job(TO_NUMBER(:job_id), l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE); owa_util.http_header_close;
                WHILE l_json IS NOT NULL AND l_pos <= dbms_lob.getlength(l_json) LOOP
                    htp.prn(dbms_lob.substr(l_json, 8000, l_pos)); l_pos := l_pos + 8000;
                END LOOP;
            END;
        ~'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'admin/jobs/:job_id/move-up');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'admin/jobs/:job_id/move-up',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_source => q'~
            DECLARE
                l_body CLOB := :body_text; l_json VARCHAR2(4000);
                l_status PLS_INTEGER;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.admin_move_job(
                    TO_NUMBER(:job_id), 'UP', l_body, l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE); owa_util.http_header_close;
                htp.prn(l_json);
            END;
        ~'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'admin/jobs/:job_id/move-down');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'admin/jobs/:job_id/move-down',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_source => q'~
            DECLARE
                l_body CLOB := :body_text; l_json VARCHAR2(4000);
                l_status PLS_INTEGER;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.admin_move_job(
                    TO_NUMBER(:job_id), 'DOWN', l_body, l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE); owa_util.http_header_close;
                htp.prn(l_json);
            END;
        ~'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'admin/jobs/:job_id/move-first');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'admin/jobs/:job_id/move-first',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_source => q'~
            DECLARE
                l_body CLOB := :body_text; l_json VARCHAR2(4000);
                l_status PLS_INTEGER;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.admin_move_job(
                    TO_NUMBER(:job_id), 'FIRST', l_body, l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE); owa_util.http_header_close;
                htp.prn(l_json);
            END;
        ~'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'admin/jobs/:job_id/move-last');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'admin/jobs/:job_id/move-last',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_source => q'~
            DECLARE
                l_body CLOB := :body_text; l_json VARCHAR2(4000);
                l_status PLS_INTEGER;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.admin_move_job(
                    TO_NUMBER(:job_id), 'LAST', l_body, l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE); owa_util.http_header_close;
                htp.prn(l_json);
            END;
        ~'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'admin/jobs/:job_id/hold');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'admin/jobs/:job_id/hold',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_source => q'~
            DECLARE
                l_body CLOB := :body_text; l_json VARCHAR2(4000);
                l_status PLS_INTEGER;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.admin_hold_job(
                    TO_NUMBER(:job_id), l_body, l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE); owa_util.http_header_close;
                htp.prn(l_json);
            END;
        ~'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'admin/jobs/:job_id/resume');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'admin/jobs/:job_id/resume',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_source => q'~
            DECLARE
                l_body CLOB := :body_text; l_json VARCHAR2(4000);
                l_status PLS_INTEGER;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.admin_resume_job(
                    TO_NUMBER(:job_id), l_body, l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE); owa_util.http_header_close;
                htp.prn(l_json);
            END;
        ~'
    );

    ORDS.DEFINE_TEMPLATE(c_module, 'admin/jobs/:job_id/remove');
    ORDS.DEFINE_HANDLER(
        p_module_name => c_module,
        p_pattern => 'admin/jobs/:job_id/remove',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_source => q'~
            DECLARE
                l_body CLOB := :body_text; l_json VARCHAR2(4000);
                l_status PLS_INTEGER;
            BEGIN
                l_json := JOBS_APP.pkg_jobs_api.admin_remove_job(
                    TO_NUMBER(:job_id), l_body, l_status);
                :status_code := l_status;
                owa_util.mime_header('application/json', FALSE); owa_util.http_header_close;
                htp.prn(l_json);
            END;
        ~'
    );

    COMMIT;
END;
/
