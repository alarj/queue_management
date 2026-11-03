# ORDS API kasutusjuhend

## 1. Dokumendi päritolu

Koostaja: AI (OpenAI Codex) projekti lähteülesande ja teostatud MVP1 ORDS API
põhjal. Juhend on mõeldud liidestatavale rakendusele ja selle workerile.

## 2. Sisukord

- [3. Ühendus](#3-ühendus)
- [4. Endpoint’id](#4-endpointid)
- [5. Workeri töövoog](#5-workeri-töövoog)
- [6. Vead ja korduskatsed](#6-vead-ja-korduskatsed)

## 3. Ühendus

Baasaadress:

```text
https://GAEA57CDC53A00B-WOQC8AR450A6CUM0.adb.eu-frankfurt-1.oraclecloudapps.com/ords/jobs
```

Soovituslik konfiguratsioon:

```dotenv
ORDS_BASE_URL=https://GAEA57CDC53A00B-WOQC8AR450A6CUM0.adb.eu-frankfurt-1.oraclecloudapps.com/ords/jobs
ORDS_USERNAME=JOBS_API
ORDS_PASSWORD=
```

Projekti juurkausta [`.env.example`](../.env.example) sisaldab kõiki nõutud
parameetreid ilma saladuse väärtuseta. Kopeeri see lokaalseks `.env` failiks ja
lisa `ORDS_PASSWORD` väärtus serveris käsitsi. `.env` on Gitist välistatud.

Liidestatav rakendus lisab oma konfiguratsiooni ka registreeritud
`application_code` väärtuse. Kõik päringud kasutavad HTTP Basic autentimist.
Kasutajanimi ja parool tulevad rakenduse saladuste konfiguratsioonist.
JSON-päringute päis on `Content-Type: application/json`.

Ilma kehtiva Basic mandaadita tagastab ORDS `401 Unauthorized`.

Rakendus saadab igas päringus oma registreeritud `application_code` väärtuse.

## 4. Endpoint’id

### 4.1. Töö lisamine

```http
POST /application/jobs
```

```json
{
  "application_code": "err_video_to_text",
  "job_type_code": "diarization",
  "application_job_id": "165",
  "idempotency_key": "unikaalne-võti",
  "previous_job_id": null,
  "parameters": {}
}
```

Uus töö tagastab `201`; sama idempotentsusvõtme kordus tagastab `200` ja sama
töö. Vastus:

```json
{"job_id":123,"status":"QUEUED"}
```

### 4.2. Töö olek

```http
GET /application/jobs/123?application_code=err_video_to_text
```

Vastus sisaldab `job_id`, `application_job_id`, `job_type_code`,
`previous_job_id`, `status` ja ajatemplid.

### 4.3. Workeri käivitumine

Kutsu üks kord workeri käivitumisel, enne claim’i:

```http
POST /worker/startup
```

```json
{
  "application_code": "err_video_to_text",
  "worker_instance_id": "worker-20261103-001",
  "host_id": "ubuntu-main",
  "boot_id": "väärtus-failist-/proc/sys/kernel/random/boot_id"
}
```

Vastus sisaldab `active_job` väärtust. Kui see pole `null`, peab worker
kontrollima, kas sama protsess töötab endiselt.

### 4.4. Järgmise töö küsimine

```http
POST /worker/claim
```

```json
{
  "application_code": "err_video_to_text",
  "claim_request_id": "unikaalne-päringu-tunnus",
  "worker_instance_id": "worker-20261103-001",
  "host_id": "ubuntu-main",
  "boot_id": "linux-boot-id"
}
```

`204` tähendab, et tööd ei anta. `200` vastus sisaldab vähemalt:

```json
{
  "job_id": 123,
  "application_job_id": "165",
  "job_type_code": "diarization",
  "parameters": {},
  "status": "CLAIMED",
  "execution_token": "00112233445566778899AABBCCDDEEFF"
}
```

Worker valib adapteri ainult `job_type_code` järgi.

### 4.5. Käivitamise kinnitus

```http
POST /worker/jobs/123/start
```

```json
{
  "application_code": "err_video_to_text",
  "execution_token": "00112233445566778899AABBCCDDEEFF",
  "worker_instance_id": "worker-20261103-001",
  "host_id": "ubuntu-main",
  "boot_id": "linux-boot-id"
}
```

Saada alles pärast tegeliku protsessi edukat käivitamist.

### 4.6. Heartbeat

```http
POST /worker/jobs/123/heartbeat
```

Päringu väljad on samad nagu käivitamise kinnitamisel. Saada töötamise ajal
iga 5 minuti järel.

### 4.7. Töö lõpetamine

```http
POST /worker/jobs/123/complete
```

```json
{
  "application_code": "err_video_to_text",
  "execution_token": "00112233445566778899AABBCCDDEEFF",
  "worker_instance_id": "worker-20261103-001",
  "host_id": "ubuntu-main",
  "boot_id": "linux-boot-id",
  "outcome": "SUCCEEDED",
  "exit_code": 0,
  "end_reason": "COMPLETED"
}
```

`outcome` on `SUCCEEDED`, `FAILED`, `INTERRUPTED` või `UNKNOWN`.

## 5. Workeri töövoog

1. Loe `boot_id` ja loo uus `worker_instance_id`.
2. Kutsu `/worker/startup`.
3. Kui vana aktiivne töö tagastatakse, kontrolli selle protsessi tegelikku olekut.
4. Jõudeolekus kutsu `/worker/claim` kohe ja seejärel iga 5 minuti järel.
5. Käivita vastuse `job_type_code` adapter `parameters` väärtustega.
6. Saada `/start`, seejärel heartbeat iga 5 minuti järel.
7. Saada lõpus `/complete`.
8. Töötav worker uut tööd ei claim’i.

## 6. Vead ja korduskatsed

Oracle’i viga:

```json
{
  "error_code": "INVALID_STATE",
  "message": "job cannot be completed from status QUEUED",
  "oracle_error": "ORA-20008: job cannot be completed from status QUEUED"
}
```

- `409` tähendab oleku-, tokeni-, sõltuvus- või idempotentsuskonflikti.
- `429` korral järgi `Retry-After` päist.
- Võrguvea või ajutise 5xx korral proovi kasvava ooteajaga uuesti.
- Esitamise kordus kasutab sama `idempotency_key` väärtust.
- Claim’i kordus kasutab sama `claim_request_id` väärtust.
- Start, heartbeat ja complete kordused kasutavad sama `execution_token` väärtust.
- Heartbeat’i saatmise viga ei ole põhjus töötava OS-protsessi lõpetamiseks.
