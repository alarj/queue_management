-- OAuth protection for the jobs.api module.
-- Run in SQL Developer as JOBS_API after 004_ords_handlers.sql.

SET DEFINE OFF;

BEGIN
    ORDS.CREATE_ROLE(p_role_name => 'jobs.api.client');

    ORDS.DEFINE_PRIVILEGE(
        p_privilege_name => 'jobs.api.auth',
        p_roles          => OWA.VC_ARR('jobs.api.client'),
        p_label          => 'Queue API OAuth authentication',
        p_description    => 'Requires an OAuth client with the jobs.api.client role.'
    );
    ORDS.SET_MODULE_PRIVILEGE(
        p_module_name    => 'jobs.api',
        p_privilege_name => 'jobs.api.auth'
    );
    COMMIT;
END;
/
