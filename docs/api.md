# ORDS API kasutusjuhend

## 1. Dokumendi päritolu

Koostaja: AI (OpenAI Codex) projekti lähteülesande ja teostatud MVP1 ORDS API
põhjal. Juhend on mõeldud liidestatavale rakendusele ja selle workerile.

## 2. Sisukord

- [3. Ühendus](#3-ühendus)
- [4. Endpoint’id](#4-endpointid)
- [4.1.1. Informatiivsed tööparameetrid](#411-informatiivsed-tööparameetrid)
- [5. Workeri töövoog](#5-workeri-töövoog)
- [5.1. Claim'itud töö puudub kohalikust rakendusest](#51-claimitud-töö-puudub-kohalikust-rakendusest)
- [6. Vead ja korduskatsed](#6-vead-ja-korduskatsed)

## 3. Ühendus

Baasaadress:

```text
https://GAEA57CDC53A00B-WOQC8AR450A6CUM0.adb.eu-frankfurt-1.oraclecloudapps.com/ords/jobs
```

Soovituslik konfiguratsioon:

```dotenv
ORDS_BASE_URL=https://GAEA57CDC53A00B-WOQC8AR450A6CUM0.adb.eu-frankfurt-1.oraclecloudapps.com/ords/jobs
ORDS_OAUTH_CLIENT_ID=
ORDS_OAUTH_CLIENT_SECRET=
```

Projekti juurkausta [`.env.example`](../.env.example) sisaldab kõiki nõutud
parameetreid ilma saladuse väärtuseta. `.env` on Gitist välistatud.

### 3.1. OAuth-kliendi loomine

Keskse süsteemi haldur loob iga API-kutsuja jaoks eraldi OAuth-kliendi,
käivitades `JOBS_API` skeemis
[`db/ords/006_create_oauth_client.sql`](../db/ords/006_create_oauth_client.sql).
Olemasoleva Basic-autentimisega paigalduse puhul tuleb enne seda käivitada
[`db/ords/005_oauth_authentication.sql`](../db/ords/005_oauth_authentication.sql).

Skript küsib kolm väärtust:

- kliendi nimi, näiteks `ttu_loeng` või `queue_management_admin`;
- kliendi saladus, mille rakenduse haldur genereerib ja salvestab oma `.env`-i;
- kontakt-e-post.

Skript prindib välja `ORDS_OAUTH_CLIENT_ID` väärtuse. Koos sisestatud
`ORDS_OAUTH_CLIENT_SECRET` väärtusega tuleb see panna ainult vastava
rakenduse `.env`-i. Igal rakendusel ja kesksel haldusbackendil on eri klient.

### 3.2. Tokeni küsimine ja kasutamine

Klient küsib tokeni käivitumisel või pärast eelmise tokeni aegumist:

```http
POST /oauth/token
Authorization: Basic base64(client_id:client_secret)
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
```

See on ainus OAuth-päring, kus kasutatakse HTTP Basic päist. Vastus sisaldab
vähemalt `access_token` ja `expires_in`; meie kliendi tokeni kehtivus on 3600
sekundit. Klient hoiab tokenit ainult mälus ja küsib uue 60 sekundit enne
aegumist. `client_credentials` voog ei kasuta refresh tokenit.

Kõik järjekorra API päringud kasutavad tokenit:

```http
Authorization: Bearer <access_token>
Content-Type: application/json
```

Kui API tagastab `401`, küsib klient ühe korra uue tokeni ja kordab sama
päringut. Kui ka teine päring tagastab `401`, tuleb käsitleda seda
autentimisveana.

Liidestatav rakendus lisab oma konfiguratsiooni ka registreeritud
`application_code` väärtuse. OAuth-klient tõendab API-kutsuja mandaadi, kuid
MVP1 ei seo seda automaatselt `application_code` väärtusega. Oracle kontrollib
siiski, et `application_code` ja `job_type_code` on registreeritud.

Ilma kehtiva Bearer tokenita tagastab ORDS `401 Unauthorized`.

### 3.3. Python `httpx` näidis

```python
import time
import httpx

token = None
token_expires_at = 0

async def authorization_header(client: httpx.AsyncClient) -> dict[str, str]:
    global token, token_expires_at
    if not token or time.time() >= token_expires_at:
        response = await client.post(
            f"{ORDS_BASE_URL}/oauth/token",
            auth=(ORDS_OAUTH_CLIENT_ID, ORDS_OAUTH_CLIENT_SECRET),
            data={"grant_type": "client_credentials"},
        )
        response.raise_for_status()
        body = response.json()
        token = body["access_token"]
        token_expires_at = time.time() + int(body["expires_in"]) - 60
    return {"Authorization": f"Bearer {token}"}
```

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

#### 4.1.1. Informatiivsed tööparameetrid

`parameters` on töötüübi lepinguga valideeritav JSON-objekt. Lisaks workeri
tegelikele sisenditele võib liidestatav rakendus sinna panna ohutu,
inimloetava hetkeseisu haldusvaate jaoks. Näiteks loengutöötleja saadab:

```json
"parameters": {
  "lecture_processing_id": 123,
  "lecture_title": "Loengu pealkiri",
  "lecture_start_at": "2026-11-01T10:00:00Z"
}
```

Informatiivne väärtus ei tohi sisaldada saladust, shellikäsku ega
failisüsteemiteed. Worker ei tohi selle põhjal muuta täitmisloogikat: ta loeb
autoriteetse töö konteksti rakenduse enda püsivast olekust tehnilise ID abil.
Haldusliides võib neid välju kasutada töö nime ja kuupäeva kuvamiseks.

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

Worker valib adapteri ainult `job_type_code` järgi. `parameters` sisaldab
töötüübi tehnilist identifikaatorit ning võib sisaldada ka jaotises 4.1.1
kirjeldatud informatiivseid välju; need ei ole workeri käsk.

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
5. Leia `application_job_id` ja töötüübi tehnilise identifikaatori abil
   rakenduse enda püsivast olekust autoriteetne töökontekst. Kontrolli enne
   protsessi käivitamist, et töötüüp ja tehniline identifikaator vastavad
   claim'i väärtustele.
6. Saada `/start`, seejärel heartbeat iga 5 minuti järel.
7. Saada lõpus `/complete`.
8. Töötav worker uut tööd ei claim’i.

### 5.1. Claim'itud töö puudub kohalikust rakendusest

Claim on ORDS-i autoriteetne käivitamisluba, kuid rakendus võib olla enne
claim'i kohaliku töö kirje sulgenud, kaotanud või teise versiooniga asendanud.
Worker ei tohi sellisel juhul jääda tõrkelõputult sama tööd proovima ega anda
lihtsalt protsessiviga, sest see blokeeriks kogu ühise järjekorra.

Kui worker ei leia `application_job_id` järgi aktiivset kohalikku töökonteksti,
ei käivita ta protsessi ega saada `/start`. Ta märgib ORDS-is claim'itud töö
lõpetatuks:

```http
POST /worker/jobs/123/complete
```

```json
{
  "application_code": "err_video_to_text",
  "execution_token": "claimi-token",
  "worker_instance_id": "worker-20261103-001",
  "host_id": "ubuntu-main",
  "boot_id": "linux-boot-id",
  "outcome": "INTERRUPTED",
  "exit_code": 0,
  "end_reason": "APPLICATION_OPERATION_NOT_FOUND"
}
```

See on kontrollitud töökatkestus, mitte õnnestumine: ORDS talletab põhjuse ja
saab järgmist tööd edasi pakkuda. Sama põhimõte kehtib ka valede või puuduvate
tehniliste parameetrite ja sobimatu töötüübi puhul, kuid nende korral tuleb
töö lõpetada `FAILED`-olekuga ning selge põhjusega, näiteks
`INVALID_PARAMETERS` või `INVALID_JOB_TYPE`.

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
