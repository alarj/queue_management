-- Serveriülese tööjärjekorra Oracle'i põhiskeem.
-- Käivita SQL Developeris JOBS_APP kasutajana ühe skriptina.
-- Skript ei loo kasutajaid, ORDS-i objekte ega algandmeid.

CREATE SEQUENCE applications_seq
    START WITH 1
    INCREMENT BY 1
    NOCACHE;

CREATE SEQUENCE job_types_seq
    START WITH 1
    INCREMENT BY 1
    NOCACHE;

CREATE SEQUENCE jobs_seq
    START WITH 1
    INCREMENT BY 1
    NOCACHE;

CREATE SEQUENCE queue_order_seq
    START WITH 100
    INCREMENT BY 100
    NOCACHE;

CREATE SEQUENCE job_attempts_seq
    START WITH 1
    INCREMENT BY 1
    NOCACHE;

CREATE SEQUENCE job_events_seq
    START WITH 1
    INCREMENT BY 1
    NOCACHE;

CREATE TABLE applications (
    application_id NUMBER DEFAULT applications_seq.NEXTVAL NOT NULL,
    application_code VARCHAR2(250 CHAR) NOT NULL,
    display_name VARCHAR2(250 CHAR) NOT NULL,
    enabled NUMBER(1) DEFAULT 1 NOT NULL,
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at TIMESTAMP,
    CONSTRAINT applications_pk PRIMARY KEY (application_id),
    CONSTRAINT applications_code_uq UNIQUE (application_code),
    CONSTRAINT applications_enabled_ck CHECK (enabled IN (0, 1))
);

COMMENT ON TABLE applications IS
    'Keskse järjekorraga liidestatud rakenduste register.';
COMMENT ON COLUMN applications.application_id IS
    'Rakenduse sequence''ist automaatselt saadav primaarvõti.';
COMMENT ON COLUMN applications.application_code IS
    'Rakenduse püsiv masinloetav tunnus, mille rakendus saadab ORDS-i päringutes.';
COMMENT ON COLUMN applications.display_name IS
    'Rakenduse inimesele kuvatav nimi.';
COMMENT ON COLUMN applications.enabled IS
    '1 lubab rakendusel töid esitada ja claim''ida; 0 keelab selle.';
COMMENT ON COLUMN applications.created_at IS
    'Rakenduse kirje loomise aeg UTC-s.';
COMMENT ON COLUMN applications.updated_at IS
    'Rakenduse kirje viimase muutmise aeg UTC-s.';

CREATE TABLE job_types (
    job_type_id NUMBER DEFAULT job_types_seq.NEXTVAL NOT NULL,
    application_id NUMBER NOT NULL,
    job_type_code VARCHAR2(250 CHAR) NOT NULL,
    display_name VARCHAR2(250 CHAR) NOT NULL,
    enabled NUMBER(1) DEFAULT 1 NOT NULL,
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at TIMESTAMP,
    CONSTRAINT job_types_pk PRIMARY KEY (job_type_id),
    CONSTRAINT job_types_app_id_uq UNIQUE (application_id, job_type_id),
    CONSTRAINT job_types_app_code_uq UNIQUE (application_id, job_type_code),
    CONSTRAINT job_types_application_fk
        FOREIGN KEY (application_id)
        REFERENCES applications (application_id),
    CONSTRAINT job_types_enabled_ck CHECK (enabled IN (0, 1))
);

COMMENT ON TABLE job_types IS
    'Rakendustele registreeritud tööliigid, millele vastab rakenduse workeris lubatud adapter.';
COMMENT ON COLUMN job_types.job_type_id IS
    'Tööliigi sequence''ist automaatselt saadav primaarvõti.';
COMMENT ON COLUMN job_types.application_id IS
    'Rakendus, millele tööliik kuulub.';
COMMENT ON COLUMN job_types.job_type_code IS
    'Püsiv masinloetav tööliigi tunnus, mis valib rakenduse workeris adapteri.';
COMMENT ON COLUMN job_types.display_name IS
    'Tööliigi inimesele kuvatav nimi.';
COMMENT ON COLUMN job_types.enabled IS
    '1 lubab seda liiki uusi töid esitada ja käivitada; 0 keelab selle.';
COMMENT ON COLUMN job_types.created_at IS
    'Tööliigi kirje loomise aeg UTC-s.';
COMMENT ON COLUMN job_types.updated_at IS
    'Tööliigi kirje viimase muutmise aeg UTC-s.';

CREATE TABLE jobs (
    job_id NUMBER DEFAULT jobs_seq.NEXTVAL NOT NULL,
    application_id NUMBER NOT NULL,
    job_type_id NUMBER NOT NULL,
    application_job_id VARCHAR2(250 CHAR) NOT NULL,
    previous_job_id NUMBER,
    idempotency_key VARCHAR2(250 CHAR) NOT NULL,
    parameters_json JSON NOT NULL,
    status VARCHAR2(250 CHAR) DEFAULT 'QUEUED' NOT NULL,
    queue_order NUMBER DEFAULT queue_order_seq.NEXTVAL NOT NULL,
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at TIMESTAMP,
    completed_at TIMESTAMP,
    CONSTRAINT jobs_pk PRIMARY KEY (job_id),
    CONSTRAINT jobs_app_id_job_id_uq UNIQUE (application_id, job_id),
    CONSTRAINT jobs_app_idempotency_uq UNIQUE (application_id, idempotency_key),
    CONSTRAINT jobs_application_fk
        FOREIGN KEY (application_id)
        REFERENCES applications (application_id),
    CONSTRAINT jobs_job_type_fk
        FOREIGN KEY (application_id, job_type_id)
        REFERENCES job_types (application_id, job_type_id),
    CONSTRAINT jobs_previous_job_fk
        FOREIGN KEY (application_id, previous_job_id)
        REFERENCES jobs (application_id, job_id),
    CONSTRAINT jobs_previous_not_self_ck
        CHECK (previous_job_id IS NULL OR previous_job_id <> job_id),
    CONSTRAINT jobs_status_ck
        CHECK (status IN (
            'QUEUED',
            'HELD',
            'CLAIMED',
            'RUNNING',
            'SUCCEEDED',
            'FAILED',
            'INTERRUPTED',
            'REMOVED',
            'UNKNOWN'
        ))
);

COMMENT ON TABLE jobs IS
    'Rakendusteülene autoriteetne tööjärjekord ja töö hetkeseis.';
COMMENT ON COLUMN jobs.job_id IS
    'Töö sequence''ist automaatselt saadav primaarvõti ja ORDS API keskne töö tunnus.';
COMMENT ON COLUMN jobs.application_id IS
    'Rakendus, millele töö kuulub.';
COMMENT ON COLUMN jobs.job_type_id IS
    'Registreeritud tööliik, mis määrab rakenduse workeris kasutatava adapteri.';
COMMENT ON COLUMN jobs.application_job_id IS
    'Töö esitanud rakenduse enda protsessi või tegevuse tunnus.';
COMMENT ON COLUMN jobs.previous_job_id IS
    'Sama rakenduse eelmine töö, mis peab enne selle töö käivitamist olema olekus SUCCEEDED.';
COMMENT ON COLUMN jobs.idempotency_key IS
    'Rakenduse antud korduskindluse tunnus; sama rakenduse sama võti ei loo uut tööd.';
COMMENT ON COLUMN jobs.parameters_json IS
    'Tööliigi lepingu järgi valideeritud käivitusparameetrid JSON-vormingus.';
COMMENT ON COLUMN jobs.status IS
    'Töö keskne olek.';
COMMENT ON COLUMN jobs.queue_order IS
    'Töö sorteerimisvõti FIFO-järjekorras; algväärtus tuleb sequence''ist sammuga 100.';
COMMENT ON COLUMN jobs.created_at IS
    'Töö loomise aeg UTC-s.';
COMMENT ON COLUMN jobs.updated_at IS
    'Töö viimase muutmise aeg UTC-s.';
COMMENT ON COLUMN jobs.completed_at IS
    'Töö lõppolekusse jõudmise aeg UTC-s.';

CREATE UNIQUE INDEX jobs_one_active_uq
    ON jobs (
        CASE
            WHEN status IN ('CLAIMED', 'RUNNING', 'UNKNOWN') THEN 1
            ELSE NULL
        END
    );

CREATE UNIQUE INDEX jobs_queued_order_uq
    ON jobs (
        CASE
            WHEN status = 'QUEUED' THEN queue_order
            ELSE NULL
        END
    );

CREATE INDEX jobs_queue_ix
    ON jobs (status, queue_order);

CREATE INDEX jobs_previous_job_ix
    ON jobs (application_id, previous_job_id);

CREATE INDEX jobs_job_type_ix
    ON jobs (application_id, job_type_id);

CREATE TABLE job_attempts (
    job_attempt_id NUMBER DEFAULT job_attempts_seq.NEXTVAL NOT NULL,
    job_id NUMBER NOT NULL,
    attempt_number NUMBER NOT NULL,
    claim_request_id VARCHAR2(250 CHAR) NOT NULL,
    execution_token RAW(16) DEFAULT SYS_GUID() NOT NULL,
    worker_instance_id VARCHAR2(250 CHAR) NOT NULL,
    host_id VARCHAR2(250 CHAR) NOT NULL,
    boot_id VARCHAR2(250 CHAR) NOT NULL,
    claimed_at TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    started_at TIMESTAMP,
    last_heartbeat_at TIMESTAMP,
    ended_at TIMESTAMP,
    exit_code NUMBER,
    end_reason VARCHAR2(250 CHAR),
    CONSTRAINT job_attempts_pk PRIMARY KEY (job_attempt_id),
    CONSTRAINT job_attempts_job_number_uq UNIQUE (job_id, attempt_number),
    CONSTRAINT job_attempts_claim_request_uq UNIQUE (claim_request_id),
    CONSTRAINT job_attempts_token_uq UNIQUE (execution_token),
    CONSTRAINT job_attempts_job_fk
        FOREIGN KEY (job_id)
        REFERENCES jobs (job_id),
    CONSTRAINT job_attempts_number_ck CHECK (attempt_number > 0)
);

COMMENT ON TABLE job_attempts IS
    'Töö reserveerimise ja käivitamise katsed koos workeri, hosti ning täitmise oleku andmetega.';
COMMENT ON COLUMN job_attempts.job_attempt_id IS
    'Täitmiskatse sequence''ist automaatselt saadav primaarvõti.';
COMMENT ON COLUMN job_attempts.job_id IS
    'Töö, mida selle katsega käivitati.';
COMMENT ON COLUMN job_attempts.attempt_number IS
    'Katse järjekorranumber sama töö piires, alates ühest.';
COMMENT ON COLUMN job_attempts.claim_request_id IS
    'Workeri antud globaalselt unikaalne korduskindel claim-päringu tunnus.';
COMMENT ON COLUMN job_attempts.execution_token IS
    'Oracle''i SYS_GUID abil loodud unikaalne token käivitamise, heartbeat''i ja lõpetamise kinnitamiseks.';
COMMENT ON COLUMN job_attempts.worker_instance_id IS
    'Konkreetse workeri käivituse tunnus.';
COMMENT ON COLUMN job_attempts.host_id IS
    'Ubuntu hosti püsiv tunnus.';
COMMENT ON COLUMN job_attempts.boot_id IS
    'Ubuntu konkreetse buudi tunnus failist /proc/sys/kernel/random/boot_id.';
COMMENT ON COLUMN job_attempts.claimed_at IS
    'Aeg UTC-s, mil Oracle reserveeris töö workerile.';
COMMENT ON COLUMN job_attempts.started_at IS
    'Aeg UTC-s, mil worker kinnitas tegeliku protsessi käivitumise.';
COMMENT ON COLUMN job_attempts.last_heartbeat_at IS
    'Viimase eduka heartbeat''i aeg UTC-s.';
COMMENT ON COLUMN job_attempts.ended_at IS
    'Täitmiskatse lõpetamise aeg UTC-s.';
COMMENT ON COLUMN job_attempts.exit_code IS
    'Rakenduse adapteri teatatud protsessi väljumiskood, kui see on olemas.';
COMMENT ON COLUMN job_attempts.end_reason IS
    'Masinloetav põhjus, miks täitmiskatse lõppes.';

CREATE TABLE job_events (
    job_event_id NUMBER DEFAULT job_events_seq.NEXTVAL NOT NULL,
    job_id NUMBER NOT NULL,
    event_type VARCHAR2(250 CHAR) NOT NULL,
    actor_type VARCHAR2(250 CHAR) NOT NULL,
    actor_id VARCHAR2(250 CHAR) NOT NULL,
    details_json JSON,
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT job_events_pk PRIMARY KEY (job_event_id),
    CONSTRAINT job_events_job_fk
        FOREIGN KEY (job_id)
        REFERENCES jobs (job_id),
    CONSTRAINT job_events_actor_type_ck
        CHECK (actor_type IN ('APPLICATION', 'WORKER', 'USER', 'SYSTEM'))
);

COMMENT ON TABLE job_events IS
    'Töö oleku- ja haldustoimingute ajalooline sündmuslogi.';
COMMENT ON COLUMN job_events.job_event_id IS
    'Sündmuse sequence''ist automaatselt saadav primaarvõti.';
COMMENT ON COLUMN job_events.job_id IS
    'Töö, millega sündmus on seotud.';
COMMENT ON COLUMN job_events.event_type IS
    'Masinloetav sündmuse liik.';
COMMENT ON COLUMN job_events.actor_type IS
    'Sündmuse põhjustanud osapoole liik: APPLICATION, WORKER, USER või SYSTEM.';
COMMENT ON COLUMN job_events.actor_id IS
    'Sündmuse põhjustanud konkreetse osapoole tunnus.';
COMMENT ON COLUMN job_events.details_json IS
    'Sündmuseliigipõhised struktureeritud lisaandmed ilma saladusteta.';
COMMENT ON COLUMN job_events.created_at IS
    'Sündmuse toimumise aeg UTC-s.';

CREATE INDEX job_events_job_created_ix
    ON job_events (job_id, created_at);
