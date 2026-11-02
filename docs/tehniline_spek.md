# Tehniline spetsifikatsioon: Jenkinsi-põhine serveriülene tööjärjekord

## 1. Dokumendi päritolu

Koostaja: AI (OpenAI Codex) faili [`lahteylesanne.md`](lahteylesanne.md), kasutajaga 1.11.2026 kinnitatud otsuste ning olemasolevate projektide kontrollitud Google’i autentimise ja Oracle’i ühendusmustrite põhjal. Dokument arvestab ka kinnitatud rakendusepõhiste API-tokenite ja ainult serverisisese rakenduste API-ga. Dokument kirjeldab kavandatavat lahendust; projekti teostust ei ole veel loodud.

## 2. Sisukord

- [3. Dokumendi roll](#3-dokumendi-roll)
- [4. Arhitektuuriotsus](#4-arhitektuuriotsus)
- [5. Komponendid](#5-komponendid)
- [6. Tõeallikad ja vastutuse piirid](#6-tõeallikad-ja-vastutuse-piirid)
- [7. Töö olekumudel](#7-töö-olekumudel)
- [8. Töö esitamine](#8-töö-esitamine)
- [9. Järjekorra järjestamine](#9-järjekorra-järjestamine)
- [10. Hold, taastamine ja eemaldamine](#10-hold-taastamine-ja-eemaldamine)
- [11. Töötava töö katkestamine](#11-töötava-töö-katkestamine)
- [12. Google’i autentimine](#12-googlei-autentimine)
- [13. Rakenduste autentimine](#13-rakenduste-autentimine)
- [14. Oracle’i andmemudel](#14-oraclei-andmemudel)
- [15. API esialgne leping](#15-api-esialgne-leping)
- [16. Jenkinsi seadistus](#16-jenkinsi-seadistus)
- [17. Konteinerid ja võrk](#17-konteinerid-ja-võrk)
- [18. Turvalisus](#18-turvalisus)
- [19. Taaskäivitus ja olekute kooskõlastamine](#19-taaskäivitus-ja-olekute-kooskõlastamine)
- [20. Logid ja jälgitavus](#20-logid-ja-jälgitavus)
- [21. Testimine](#21-testimine)
- [22. Teostusetapid](#22-teostusetapid)
- [23. Avatud tehnilised otsused](#23-avatud-tehnilised-otsused)

## 3. Dokumendi roll

Käesolev dokument kirjeldab lähteülesande tehnilist teostust. See ei anna luba luua Oracle’i kasutajat või objekte, muuta ühise nginx-serveri seadistust, muuta kõrvalprojekte ega käivitada andmeid muutvaid teste. Need tegevused vajavad projekti [`AGENTS.md`](../AGENTS.md) kohaselt kasutaja eraldi kinnitust.

## 4. Arhitektuuriotsus

Lahendus kasutab valmiskomponendina Jenkins LTS-i, kuid ei sunni igapäevast kasutajat Jenkinsi CI/CD-maigulisse üldliidesesse. Jenkinsi ette ehitatakse väike eraldi veebirakendus, mis pakub ainult selle serveri tööjärjekorra jaoks vajalikke vaateid ja toiminguid.

```text
Google'i kasutaja
        │
        ▼
haldus.fun-o.eu ─► nginx ─► Queue API avalikud autentimis- ja haldusendpoint'id
                                │
ttu_loeng ───────┐              │
ERR-i rakendus ──┼─ privaatne ─► Queue API ── privaatne ─► Jenkins LTS ─► töö adapter
muud rakendused ─┘  Docker-võrk     │          Docker-võrk      │
                    + API-token     │                           └── JENKINS_HOME
                                    └──► Oracle JENKINS_APP
```

Põhivalikud:

- Jenkins LTS vastutab tööde käivitamise, executor’i hõivatuse, protsessilogi ja build’i lõppoleku eest.
- FastAPI backend vastutab kasutajaliidese, Google’i sessiooni, rakenduste API-tokenite kontrolli, sisendi valideerimise, hold-loogika ja Oracle’i metaoleku eest.
- Minimalistlik frontend kasutab ainult FastAPI avalikke autentimis- ja haldusendpoint’e; brauser ei suhtle otse Jenkinsi ega Oracle’iga.
- Liidestatud rakendused kasutavad Queue API-d ainult serverisisesest privaatsest Docker-võrgust. Rakenduste endpoint’e nginx ega `haldus.fun-o.eu` ei avalda.
- Raske tööde Jenkins node’i executor’ite arv on esialgu üks.
- Oracle’i kasutatakse olemasolevas andmebaasis eraldi `JENKINS_APP` skeemi/kasutajaga.
- Täiendavat järjekorra- või andmebaasiteenust ei lisata.

## 5. Komponendid

### 5.1. Jenkins LTS

Vastutus:

- ootel ja töötavate build’ide tehniline haldus;
- ühe raske executor’i piirangu jõustamine;
- registreeritud töötüüpide pipeline’ide käivitamine;
- konsoolilogi ja lõppoleku säilitamine;
- protsessipuu lõpetamine katkestamisel Jenkinsi võime piires.

### 5.2. Queue API

Vastutus:

- rakenduste töösoovide vastuvõtmine;
- iga rakenduse API-tokeni kontroll ja selle sidumine rakenduse identiteediga;
- rakendusele lubatud töötüüpide jõustamine;
- töötüübi ja parameetrite valideerimine;
- idempotentsusvõtme kontroll;
- keskse töö kirje loomine Oracle’is;
- töö lisamine Jenkinsi järjekorda;
- järjekorra haldustoimingute vahendamine;
- Jenkinsi ja Oracle’i olekute kooskõlastamine.

### 5.3. Veebiliides

Vastutus:

- Google’iga sisselogimine;
- töötava töö, järjekorra ja hold-tööde kuvamine;
- töö liigutamine üles, alla, lõppu või esimeseks;
- hold, taastamine, eemaldamine ja lubatud katkestamine;
- töö detaili ja logiviite kuvamine.

### 5.4. Oracle

Vastutus:

- haldusrakenduse püsiv keskne töö ID;
- rakenduse metaolek ja hold-tööd;
- seosed Jenkinsi muutuvate queue/build ID-dega;
- idempotentsus;
- toimingute tehniline ajalugu.

### 5.5. Töö adapterid

Iga adapter kirjeldab ühte lubatud töötüüpi:

- rakenduse ja töötüübi kood;
- lubatud parameetrid ja nende valideerimine;
- tegelik käivituskäsk või pipeline;
- töökataloog ja väljundi viide;
- lõppoleku tuvastamine;
- kas katkestamine on toetatud;
- toetatud katkestamise korral täielik koristuskäsk ja kontroll.

## 6. Tõeallikad ja vastutuse piirid

| Andmed | Tõeallikas |
|---|---|
| Käimasoleva build’i tegelik olek | Jenkins |
| Aktiivse Jenkinsi järjekorra tegelik järjestus | Jenkins |
| Hold-tööd | Oracle `JENKINS_APP` |
| Keskne töö identiteet ja päritolu | Oracle `JENKINS_APP` |
| Jenkinsi konfiguratsioon ja konsoolilogid | `JENKINS_HOME` |
| Töö mahukad sisendid, ajutised failid ja väljundid | telliva rakenduse runtime |
| Lubatud Google’i e-posti aadressid | serveri `.env` |
| Rakenduste API-tokenid ja nende serveripoolsed kontrollväärtused | vastava rakenduse ning Queue API saladuste konfiguratsioon |

Oracle’i ei kopeerita pidevalt Jenkinsi järjekorra teiseks konkureerivaks tõeallikaks. Oracle’i järjekorraseos aitab töö identiteeti ja toiminguid jälgida, kuid aktiivne järjestus loetakse Jenkinsist.

## 7. Töö olekumudel

Haldusrakenduse olekud:

- `SUBMITTING` — Oracle’i kirje on loodud ja Jenkinsi lisamine on pooleli;
- `QUEUED` — töö on Jenkinsi aktiivses järjekorras;
- `HELD` — töö ei ole Jenkinsi järjekorras ja ootab kasutaja taastamist;
- `RUNNING` — Jenkins käivitab tööd;
- `SUCCEEDED` — töö lõpetas edukalt;
- `FAILED` — töö lõpetas veaga;
- `CANCELLED` — töötav töö katkestati ja koristus lõpetas edukalt;
- `CANCEL_FAILED` — katkestamine või koristus ei jõudnud kinnitatud lõppseisu;
- `REMOVED` — käivitumata töö eemaldati lõplikult;
- `UNKNOWN` — Jenkinsi ja Oracle’i seost ei õnnestu ajutiselt üheselt taastada.

Lõppolekud on `SUCCEEDED`, `FAILED`, `CANCELLED`, `CANCEL_FAILED` ja `REMOVED`. Olekumuutused peavad olema transaktsiooniliselt salvestatud seal, kus see on Oracle’i ühe toimingu piires võimalik.

## 8. Töö esitamine

Rakendus saadab privaatses Docker-võrgus:

- oma API-tokeni autentimispäises;
- registreeritud `job_type` väärtuse;
- töötüübile lubatud parameetrid;
- unikaalse idempotentsusvõtme.

Serveri toiming:

1. autendi API-token ja määra selle järgi `application_code`;
2. kontrolli, et `job_type` on sellele rakendusele lubatud, ning valideeri parameetrid;
3. leia sama rakenduse ja idempotentsusvõtmega olemasolev töö või loo uus keskne töö;
4. lisa tavatöö Jenkinsi järjekorra lõppu;
5. salvesta Jenkinsi queue ID;
6. tagasta keskne töö ID ja olek.

Järjekorra lõppu lisamine on backend’i vaikereegel ka siis, kui klient järjekorravalikut ei saada. Esimese versiooni tavalisel rakenduse API-l ei ole õigust uut tööd automaatselt järjekorra ette tõsta.

## 9. Järjekorra järjestamine

Jenkinsile paigaldatakse ainult kontrollitud järjekorra käsitsi järjestamise võime. Esialgne kandidaat on tasuta Simple Queue plugin, mille sobivus valitud Jenkins LTS-i versiooni ja vajaliku API-ga tuleb enne lukustamist integratsioonikatses kinnitada.

Haldusrakendus teisendab kasutaja toimingud tegeliku Jenkinsi järjekorra muutusteks:

- `move-up` — vaheta töö eelmise ootel tööga;
- `move-down` — vaheta töö järgmise ootel tööga;
- `move-first` — tõsta esimeseks ootel tööks;
- `move-last` — tõsta järjekorra lõppu.

Eraldi Priority Sorter pluginat esimeses versioonis ei kasutata, sest käsitsi järjestamine ja teine queue sorter ei tohi konkureerida sama järjekorra üle. „Käivita järgmisena” tähendab `move-first` toimingut, mitte püsivat prioriteediklassi.

Kõik järjestustoimingud kasutavad optimistlikku kontrolli: backend loeb enne muutmist värske järjekorra ja lükkab aegunud toimingu konfliktiga tagasi, kui sihttöö enam ootel ei ole või järjekord on vahepeal muutunud viisil, mis muudab toimingu tähendust.

## 10. Hold, taastamine ja eemaldamine

Jenkinsil puudub selle projekti nõuetele vastav üldine üksiku järjekorrakirje tähtajatu hold-olek. Seetõttu teostab hold’i haldusrakendus:

1. kontrollib, et töö on endiselt `QUEUED` ja ei ole käivitunud;
2. eemaldab selle Jenkinsi järjekorrast;
3. märgib Oracle’i kirje `HELD` olekusse ja eemaldab aktiivse queue ID seose;
4. hoiab valideeritud parameetrid hilisemaks taastamiseks.

Taastamisel esitatakse sama keskse töö ID alusel uus Jenkinsi queue-kirje järjekorra lõppu. Uus Jenkinsi queue ID salvestatakse Oracle’is.

Lõplik eemaldamine tühistab ootel Jenkinsi queue-kirje või lõpetab `HELD` kirje olekuga `REMOVED`. Eemaldatud tööd automaatselt taastada ei saa.

Hold’i ja Jenkinsi käivitumise võistlusolukorras on Jenkins autoriteetne: kui töö jõudis juba käivituda, hold ebaõnnestub konfliktiga ja seda ei teisendata katkestamiseks.

## 11. Töötava töö katkestamine

Katkestamine ei ole vaikimisi lubatud. Adapter peab deklareerima `cancel_supported=true` ning sisaldama kontrollitud koristuslepingut.

Katkestamise ahel:

1. lukusta töö katkestamistoiminguks;
2. palu Jenkinsil build katkestada;
3. oota protsessipuu lõppemist määratud piirini;
4. käivita adapteri idempotentne koristus;
5. kontrolli, et töö protsesse, konteinereid ja ajutisi ressursse ei jäänud alles;
6. märgi töö `CANCELLED` või `CANCEL_FAILED` olekusse.

Pelgalt Jenkinsi build’i `ABORTED` olek ei tõenda täielikku koristust. Kui adapteril puudub usaldusväärne koristus ja järelkontroll, ei väljasta backend sellele tööle katkestamistoimingut ning kasutajaliides ei kuva nuppu.

## 12. Google’i autentimine

Autentimine järgib olemasolevas `fun_o` projektis kontrollitud mustrit:

1. frontend laadib Google Identity Services kliendi;
2. backend annab avaliku Google Client ID;
3. frontend saab Google’ilt ID-tokeni;
4. frontend saadab ID-tokeni FastAPI backendile;
5. backend kontrollib tokenit Google’i `tokeninfo` teenuse kaudu ja võrdleb `aud` väärtust seadistatud Client ID-ga;
6. backend normaliseerib kinnitatud e-posti aadressi väiketähtedeks ja kontrollib täpset vastet lubatud aadresside loendis;
7. backend loob HMAC-signeeritud HttpOnly sessiooniküpsised;
8. väljalogimine kustutab sessiooni.

Esialgsed seadistusmuutujad:

```dotenv
GOOGLE_CLIENT_ID=
JENKINS_ALLOWED_GOOGLE_EMAILS=
SESSION_SIGNING_KEY=
```

Lubatud aadressid on komaga eraldatud. Tegelikud aadressid ja võtmed ei kuulu `.env.example` faili. Backend ei loo oma kasutajate tabelit ega parooliräside süsteemi.

## 13. Rakenduste autentimine

Google’i sessioon on ainult inimese veebiliidese jaoks. Rakenduste server-server API vajab sellest eraldi autentimist.

Igal liidestatud rakendusel on eraldi juhuslik API-token. Rakenduse token asub selle rakenduse saladuste konfiguratsioonis ning Queue API saladuste konfiguratsioon sisaldab tokeni kontrollimiseks vajalikku väärtust. Tokenit ei salvestata Oracle’isse, Git-i ega logidesse.

Edukas tokenikontroll määrab serveripoolselt rakenduse `application_code` väärtuse ja sellele lubatud `job_type` loendi. Klient ei saa päringus valida teise rakenduse identiteeti ega käivitada töötüüpi, mis pole tema tokeniga seotud. Vale või puuduv token annab autentimisvea enne töö kirje loomist.

Rakendused ja Queue API töötavad samas serveris eraldi konteinerites. Rakenduste API on kättesaadav ainult nende ühises privaatses Docker-võrgus ning seda ei avaldata nginxi ega `haldus.fun-o.eu` kaudu. Täpne serveripoolse kontrollväärtuse vorming ja tokeni roteerimise kord jäävad enne teostust kinnitatavaks.

Rakenduste API ei tohi kasutada Jenkinsi administraatori kasutajat ega vastu võtta Jenkinsi job’i nime kliendilt kontrollimata kujul.

## 14. Oracle’i andmemudel

Projektile luuakse Oracle’is eraldi `JENKINS_APP` skeem/kasutaja. Jenkins ise Oracle’it oma sisemise andmehoidlana ei kasuta.

Esialgsed tabelid:

### 14.1. `JOBS`

- `ID` — sisemine numbriline primaarvõti;
- `PUBLIC_ID` — kliendile tagastatav juhuslik unikaalne ID;
- `APPLICATION_CODE`;
- `JOB_TYPE`;
- `IDEMPOTENCY_KEY`;
- `PARAMETERS_JSON` — valideeritud parameetrid, Oracle’i JSON-kontrolliga CLOB või natiivne JSON vastavalt olemasoleva Oracle’i versiooni toele;
- `STATUS`;
- `JENKINS_QUEUE_ID`;
- `JENKINS_BUILD_NUMBER`;
- `RESULT_REFERENCE`;
- `CANCEL_SUPPORTED`;
- `CREATED_AT`, `QUEUED_AT`, `STARTED_AT`, `FINISHED_AT`, `UPDATED_AT` UTC-s;
- `VERSION_NO` optimistlikuks lukustamiseks.

Unikaalsus: `(APPLICATION_CODE, IDEMPOTENCY_KEY)`.

### 14.2. `JOB_EVENTS`

- `ID`;
- `JOB_ID`;
- `EVENT_TYPE`;
- `ACTOR_TYPE` (`USER`, `APPLICATION`, `SYSTEM`);
- `ACTOR_ID` — Google’i aadress või rakenduse kood vastavalt sündmusele;
- `DETAILS_JSON` ilma saladusteta;
- `CREATED_AT` UTC-s.

Sündmus ei nõua põhjendust. Tabel on tehniliseks jälgitavuseks ja vea uurimiseks.

Skeemimuudatused tehakse versioonitud migratsioonidega. Rakendus kasutab `python-oracledb` ühenduste pooli ja olemasolevat Oracle Walletit. Brauseril ega Jenkins job’il ei ole otseühendust skeemi tabelitesse, kui selleks puudub eraldi dokumenteeritud vajadus.

## 15. API esialgne leping

Rakenduste privaatne API, mis on kättesaadav ainult serverisisesest rakenduste Docker-võrgust:

- `POST /api/jobs` — esita tavatöö;
- `GET /api/jobs/{public_id}` — loe töö olekut;
- `GET /api/jobs/{public_id}/result` — loe lõpptulemuse viidet või kokkuvõtet.

Neid marsruute ei lisata `haldus.fun-o.eu` nginx-proxy lubatud marsruutide hulka. Rakendused pöörduvad Queue API konteineri võrgualiase poole otse. URL-i täpne hostinimi tuleneb Docker-võrgu aliasest, mitte avalikust DNS-ist.

Autenditud haldusliidese API:

- `GET /api/admin/queue` — töötav, ootel ja hold-tööde vaade;
- `GET /api/admin/jobs/{public_id}` — töö detail;
- `POST /api/admin/jobs/{public_id}/move-up`;
- `POST /api/admin/jobs/{public_id}/move-down`;
- `POST /api/admin/jobs/{public_id}/move-first`;
- `POST /api/admin/jobs/{public_id}/move-last`;
- `POST /api/admin/jobs/{public_id}/hold`;
- `POST /api/admin/jobs/{public_id}/resume`;
- `DELETE /api/admin/jobs/{public_id}` — ainult käivitumata töö;
- `POST /api/admin/jobs/{public_id}/cancel` — ainult toetatud töötav töö.

Autentimise API:

- `GET /api/auth/google/config`;
- `POST /api/auth/google`;
- `GET /api/auth/session`;
- `POST /api/auth/logout`.

Nginx avaldab ainult brauserile vajalikud `/api/auth/` ja `/api/admin/` marsruudid. Jenkinsi API-t, rakenduste `/api/jobs` marsruute ega Queue API muid sisemisi marsruute avaliku virtuaalhosti kaudu ei vahendata.

Kõik muutvad endpoint’id tagastavad konflikti, kui klient tegutseb aegunud oleku põhjal. Täpsed päringu- ja vastuseskeemid lukustatakse enne implementatsiooni OpenAPI lepingus.

## 16. Jenkinsi seadistus

- Kasutatakse ARM64-ga sobivat ametlikku Jenkins LTS konteinerit.
- `JENKINS_HOME` asub eraldi püsikettal või hosti püsikataloogis ja varundatakse.
- Raske tööde node’il on üks executor.
- Sisseehitatud node’i kasutus piiratakse ainult kokkulepitud töödele või luuakse eraldi lokaalne agent; lõplik valik tehakse paigalduskatse järel.
- Pluginad lukustatakse kontrollitud versioonidesse; paigaldatakse ainult vajalik minimaalne komplekt.
- Jenkinsi üldliides ei ole igapäevase haldusliidese asendus.
- FastAPI kasutab piiratud Jenkinsi teenusekontot ja API-tokenit, mitte inimese Google’i identiteeti.
- Pipeline peab ootama tegeliku raske protsessi lõpuni. Taustale lahti ühendatud protsess ei tohi executor’it enneaegselt vabastada.
- Tööskript peab tagastama protsessi tegeliku exit code’i.

Simple Queue plugina täpne API, CSRF crumb’i käitumine, valitud LTS-versiooni ühilduvus ja järjekorra muutuste püsivus kontrollitakse enne rakenduskoodi lukustamist eraldi tehnilises katses.

## 17. Konteinerid ja võrk

Esialgsed teenused:

- `jenkins` — Jenkins LTS;
- `queue-api` — FastAPI backend;
- `queue-web` — staatiline frontend või backendi serveeritav frontend.

Oracle on olemasolev väline teenus ning uut andmebaasikonteinerit ei looda. Oracle Wallet mount’itakse ainult `queue-api` konteinerisse read-only režiimis.

Avalik aadress on `https://haldus.fun-o.eu`. Nginxiga liidestamine järgib ERR-i rakenduse olemasolevat mustrit:

- `haldus.fun-o.eu` saab ühises nginx-konfiguratsioonis eraldi HTTPS serveriploki ja lisatakse HTTP→HTTPS ümbersuunamise hostide hulka;
- frontend serveeritakse ühise nginxi kaudu;
- ainult `/api/auth/` ja `/api/admin/` proxytakse API-konteineri võrgualiasele;
- API-konteiner ühendatakse nginxiga suhtlemiseks olemasoleva välise `funo_net` Docker-võrguga;
- Queue API ning liidestatud rakenduste konteinerid ühendatakse lisaks eraldi serverisisese privaatse Docker-võrguga, mida nginx ei kasuta;
- rakendused kasutavad töö esitamiseks ja oleku lugemiseks Queue API privaatset võrgualiast, mitte `haldus.fun-o.eu` aadressi;
- Queue API ja Jenkins ühendatakse omavahel eraldi privaatses Docker-võrgus;
- Jenkinsit, Jenkinsi API-t ega rakenduste `/api/jobs` endpoint’e ei avaldata internetti.

Enne juurutust tuleb eraldi kontrollida, et olemasolev TLS-sertifikaat katab `haldus.fun-o.eu` nime; vajaduse korral sertifikaadi muutmine ei ole käesoleva dokumendimuudatuse osa.

## 18. Turvalisus

- Kliendi töösoov kaardistatakse allowlist’itud adapterile; suvalist shellikäsku ei käivitata.
- Kõik parameetrid valideeritakse tüübi, pikkuse ja lubatud väärtuste järgi.
- Iga rakenduse API-token seotakse ühe `application_code` väärtuse ja selle rakenduse lubatud töötüüpidega.
- Vale või puuduv rakenduse API-token lükatakse tagasi enne Oracle’i kirjet või Jenkinsi tööd.
- Rakenduste API-tokenid tulevad `.env`-ist või muust saladuste mount’ist ning neid ei logita.
- Rakenduste API pole avalikust võrgust ega `haldus.fun-o.eu` kaudu marsruuditav.
- Google’i ID-token kontrollitakse serveris; frontendilt saadud e-posti aadressi ei usaldata.
- Sessiooniküpsis on `HttpOnly`, `Secure` ja sobiva `SameSite` seadistusega.
- Muutvad veebipäringud saavad CSRF-kaitse vastavalt valitud küpsise- ja päritolumudelile.
- Oracle’i, Jenkinsi, Google’i ja rakenduste saladused tulevad `.env`-ist või eraldi saladuste mount’idest.
- Parameetreid ja logisid puhastatakse enne kuvamist; saladusi ei panda Jenkinsi job’i nimedesse ega URL-i.
- Jenkinsi teenusekonto saab ainult haldusrakenduse vajatavad õigused.
- Oracle’i `JENKINS_APP` kasutaja saab ainult ühenduse ja oma objektide jaoks vajalikud õigused.

## 19. Taaskäivitus ja olekute kooskõlastamine

Queue API käivitumisel ja perioodiliselt:

1. loetakse Oracle’ist kõik mittelõplikud tööd;
2. loetakse Jenkinsist aktiivne järjekord ja build’id;
3. seotakse kirjed keskse töö ID kaudu;
4. parandatakse tuletatavad olekud;
5. ebaselge kirje märgitakse `UNKNOWN`, mitte ei käivitata automaatselt uuesti;
6. `HELD` tööd jäetakse puutumata.

Jenkinsi lisamise võrgukatkestuse korral kasutatakse idempotentsusvõtit ja keskset töö ID-d, et vältida duplikaati. Täpne Jenkinsiga kahe süsteemi vahelise katkestuse taastamisalgoritm tuleb integratsioonitestiga kinnitada.

## 20. Logid ja jälgitavus

- Jenkins säilitab build’i konsoolilogi vastavalt eraldi määratavale retention-reeglile.
- Oracle säilitab töö oleku ja tehnilised sündmused.
- Queue API logib päringu korrelatsiooni-ID, keskse töö ID ja tulemuse, kuid mitte tokenit, küpsist, Oracle’i parooli ega töö tundlikke parameetreid.
- Kasutajaliides näitab logi või turvalist logiviidet ainult autenditud kasutajale.
- Töö adapter vastutab selle eest, et rakenduse enda runtime-väljund on keskse töö ID-ga seostatav.

## 21. Testimine

### 21.1. Võrguvabad testid

- e-posti allowlist’i normaliseerimine ja täpne vaste;
- rakenduse API-tokeni korrektne ja vigane kontroll;
- tokeni järgi `application_code` ja lubatud töötüüpide määramine;
- töö parameetrite valideerimine;
- olekumasina lubatud ja keelatud üleminekud;
- idempotentsus;
- järjekorra liigutuste arvutus;
- katkestamisnupu nähtavuse reegel;
- saladuste eemaldamine logidest.

### 21.2. Integratsioonitestid

- eri konteineris rakendus → privaatne Docker-võrk → Queue API → Jenkins queue → näidistöö;
- korrektse rakenduse API-tokeniga töö esitamine ja oleku lugemine;
- puuduva, vale ning teise rakenduse tokeniga päringu tagasilükkamine;
- rakendusele mittelubatud `job_type` tagasilükkamine;
- kinnitus, et `/api/jobs` pole internetist ega `haldus.fun-o.eu` kaudu kättesaadav;
- kinnitus, et avalikud `/api/auth/` ja `/api/admin/` marsruudid töötavad nginx-proxy kaudu;
- kahe töö järjestikune täitmine ühe executor’iga;
- töö liigutamine üles, alla, esimeseks ja lõppu;
- hold → teenuste taaskäivitus → resume;
- hold’i ja käivitumise võistlusolukord;
- sama idempotentsusvõtmega korduspäring;
- Jenkinsi ajutine kättesaamatus esitamise ajal;
- Google’i õige Client ID ja lubatud/keelatud e-posti aadress;
- Oracle’i ja Jenkinsi olekute taastamine pärast restarti;
- toetatud töö katkestamine koos protsessi, konteineri ja ajutiste failide järelkontrolliga.

Andmebaasi või tegelikke tööfaile muutvad testid vajavad kasutaja eraldi luba ja isoleeritud testandmeid.

## 22. Teostusetapid

### Etapp 1 — tehniline tõendus

- Jenkins LTS ARM64 konteiner;
- üks executor;
- Simple Queue kandidaadi paigaldus ja API-katse;
- kaks ohutut näidistööd;
- järjestamise ja restardi kontroll.

### Etapp 2 — Oracle ja Queue API

- versioonitud skeem;
- rakendusepõhised API-tokenid ja töötüüpide seosed;
- privaatse rakenduste API ning avaliku haldus-API eraldamine;
- serverisisene rakenduste Docker-võrk;
- töö esitamine ja idempotentsus;
- Jenkinsiga sidumine;
- hold, resume, remove ja reconciliation.

### Etapp 3 — autentimine ja minimalistlik UI

- Google Identity Services;
- `.env` e-posti allowlist;
- sessiooniküpsised;
- järjekorra-, hold- ja detailivaated;
- kõik kokkulepitud haldustoimingud.

### Etapp 4 — esimene tegelik rakendusadapter

- ühe `ttu_loeng` või ERR-i töövoo käivitamine;
- rakenduse ühendamine Queue API privaatvõrku ja tema API-tokeni seadistamine;
- töö väljundi ja oleku seostamine;
- ressursi järjestamise kontroll.

### Etapp 5 — kontrollitud katkestamine

- ainult sobiva adapteri katkestus- ja koristusleping;
- protsessi, konteineri ja ajutiste failide järelkontroll;
- katkestamise UI avamine alles pärast katse läbimist.

## 23. Avatud tehnilised otsused

1. Rakenduste API-tokenite serveripoolse kontrollväärtuse täpne vorming ja roteerimise kord.
2. Valitud Jenkins LTS-i ja Simple Queue plugina lukustatud versioonid pärast ühilduvuskatset.
3. Jenkinsi sisseehitatud node või eraldi lokaalne agent.
4. Esimesed tegelikud töö adapterid ja nende parameetrilepingud.
5. Millistele adapteritele on täielik katkestamine reaalselt võimalik.
6. Jenkinsi logide, Oracle’i sündmuste ja lõpetatud tööde säilitusaeg.
7. Oracle’i versioonist sõltuv JSON-andmetüübi valik.
