# ORDS API ja haldusliidese testitulemused

## 1. Dokumendi päritolu

Koostaja: AI (OpenAI Codex) 3. novembril 2026 Oracle'i juurutatud ORDS API
ja Dockeris töötava haldusliidese tegelike päringute tulemuste põhjal.

## 2. Tulemused

| Kontroll | Tulemus |
|---|---|
| Autentimata `GET /admin/queue` | `401 Unauthorized` |
| Autenditud `GET /admin/queue` | `200 OK`, tühi järjekord |
| Tühi POST-keha töö esitamisel, startup'il ja claim'il | `400 INVALID_REQUEST` |
| Olematu töö detail ja haldustoiming | `404 JOB_NOT_FOUND` |
| Tundmatu `application_code` | `404 APPLICATION_NOT_FOUND` |
| Töö esitamine ja sama idempotentsusvõtme kordus | `201`, seejärel sama tööga `200` |
| Sama võtme konfliktne töö | `409 IDEMPOTENCY_CONFLICT` |
| Claim, claim'i kordus, start, heartbeat ja complete | õnnestusid |
| Lõpetatud töö detail | üks täitmiskatse; sündmused `JOB_CREATED`, `JOB_CLAIMED`, `JOB_STARTED`, `JOB_SUCCEEDED` |
| Haldustoimingud | `move-up`, `hold`, `resume` ja `remove` õnnestusid |
| Sõltuvusreegel | sõltuvat tööd ei saa eelmise ette liigutada ega eelmist sõltuva taha liigutada |
| Eelmise töö nurjumine | sõltuv töö jäi käivitamata; seostumatu töö käivitus ja lõpetas edukalt |
| Haldusliidese konteiner | käivitus teenusena `queue_management_api` olemasolevas `funo_net` võrgus |
| Haldusliidese staatilised failid | `/`, `/styles.css` ja `/app.js` tagastasid `200 OK` |
| Haldusliidese autentimata piir | `/api/admin/queue` tagastas `401 Unauthorized` |
| Signeeritud haldussessioon | `/api/auth/session` tagastas testkasutaja autentitud oleku |
| Haldusbackend → ORDS → Oracle | järjekorra lugemine ja töö detail tagastasid `200 OK` |
| Järjekorra haldustoimingud backend'i kaudu | `move-first`, `move-last`, `move-up`, `move-down`, `hold`, `resume` ja `remove` õnnestusid |
| Sõltuvustöö liigutamine backend'i kaudu | `move-first` tagastas oodatult `409 DEPENDENCY_CONFLICT` |
| Haldusliidese testandmete koristus | viis testtööd ID-dega `7` kuni `11` eemaldati testi lõpus |
| Nginx suunamine | `haldus.fun-o.eu` suunab liikluse teenusele `queue_management_api` |
| ACME webroot | `http://haldus.fun-o.eu/.well-known/acme-challenge/...` tagastas kontrollfaili |
| TLS-sertifikaat | `haldus.fun-o.eu` on sertifikaadis; kehtib kuni 1.02.2027 11:45 UTC |
| Avalik HTTPS | `https://haldus.fun-o.eu/` ja `/styles.css` tagastasid `200 OK` |
| Google'i konfiguratsioon | `/api/auth/google/config` tagastas aktiivse klienditunnuse |
| OAuth-backendi simulatsioon | tokeni küsimine, Bearer-päring ja `401` järel tokeni uuendamine õnnestusid ajutises Docker-konteineris |
| ORDS OAuth token | `client_credentials` tokenipäring õnnestus; `expires_in=3600` |
| ORDS OAuth Bearer-päring | `GET /admin/queue` tagastas `200 OK` |
| Haldusbackend OAuth-ahel | konteineri `/api/admin/queue` tagastas ajutise kohaliku sessiooniga `200 OK` |
| TTÜ OAuth-klient | `ttu_loeng` klient sai 3600-sekundilise tokeni ning `GET /admin/queue` tagastas `200 OK` |

Esimese ORDS smoke-testi lõpus oli järjekord tühi. Selle käigus lisati
rakendus `api_smoke_test`, töötüüp `smoke_test_job` ja tööd ID-dega `1` kuni
`6`. Haldusliidese integratsioonitestis eemaldati ainult selle testi tööd
ID-dega `7` kuni `11`; muid võimalikke järjekorrakirjeid test ei muutnud.

Smoke-test ei katnud tegeliku adapteri OS-protsessi, hosti restarti,
heartbeat'i aegumist, 429 vastust ega samaaegsete workerite claim'i.

OAuth-testiks käivitati `JOBS_API` skeemis käsitsi
`005_oauth_authentication.sql`, loodi haldusbackendi klient skriptiga
`006_create_oauth_client.sql` ning selle tunnused lisati haldusbackendi `.env`-i.

Google'i välise sisselogimise testi ei tehtud, sest serveri `.env`-is puuduvad
veel `GOOGLE_CLIENT_ID` ja `SESSION_SECRET`. Haldusbackend'i autenditud
endpoint'e kontrolliti ajutise, ainult testiprotsessis kehtinud signeeritud
sessiooniga; püsivat saladust ega testkonfiguratsiooni ei lisatud.
