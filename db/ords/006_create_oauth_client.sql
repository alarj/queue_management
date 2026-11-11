-- Create one OAuth client for one queue API caller.
-- Run in SQL Developer as JOBS_API after 005_oauth_authentication.sql.
-- The client secret is not printed or stored in this script.

SET SERVEROUTPUT ON;
SET DEFINE ON;

ACCEPT oauth_client_name CHAR PROMPT 'OAuth client name: '
ACCEPT oauth_client_secret CHAR PROMPT 'OAuth client secret: ' HIDE
ACCEPT oauth_support_email CHAR PROMPT 'Support email: '

DECLARE
    l_client ORDS_TYPES.t_client_credentials;
BEGIN
    l_client := ORDS_SECURITY.REGISTER_CLIENT(
        p_name                       => '&&oauth_client_name',
        p_grant_type                 => 'client_credentials',
        p_support_email              => '&&oauth_support_email',
        p_description                => 'Queue API client',
        p_client_secret              => ORDS_TYPES.oauth_client_secret(
                                        p_secret => '&&oauth_client_secret'),
        p_token_duration             => 3600,
        p_token_endpoint_auth_method => 'CLIENT_SECRET_BASIC'
    );
    ORDS_SECURITY.GRANT_CLIENT_ROLE(
        p_client_key => l_client.client_key,
        p_role_name  => 'jobs.api.client'
    );
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('ORDS_OAUTH_CLIENT_ID=' || l_client.client_key.client_id);
END;
/

UNDEFINE oauth_client_name;
UNDEFINE oauth_client_secret;
UNDEFINE oauth_support_email;
