# ORDS API smoke-testi tulemused

## 1. Dokumendi päritolu

Koostaja: AI (OpenAI Codex) 3. novembril 2026 Oracle'i juurutatud ORDS API
tegelike päringute tulemuste põhjal.

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

Testide lõpus oli järjekord tühi. Testandmetena lisati rakendus
`api_smoke_test`, töötüüp `smoke_test_job` ja tööd ID-dega `1` kuni `6`.

Smoke-test ei katnud tegeliku adapteri OS-protsessi, hosti restarti,
heartbeat'i aegumist, 429 vastust ega samaaegsete workerite claim'i.
