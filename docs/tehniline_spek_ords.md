# Tehniline spetsifikatsioon: Oracle’i ja ORDS-i põhine serveriülene tööjärjekord

## 1. Dokumendi päritolu

Koostaja: AI (OpenAI Codex) kasutajaga 2.11.2026 peetud arhitektuuriarutelu, faili [`lahteylesanne.md`](lahteylesanne.md), kõrvale heidetud Jenkinsi variandi [`tehniline_spek.md`](tehniline_spek.md), `fun_o` projekti kontrollitud ORDS-teostuse ning Oracle Autonomous Database’is kasutaja tehtud tehniliste katsete põhjal.

Dokument kirjeldab valitud Oracle’i ja ORDS-i põhist lahendust. MVP1 kasutab perioodilist polling’ut; Oracle’i algatatud wakeup on säilitatud tulevase MVPx laiendusena. Dokument ei anna luba luua Oracle’i kasutajaid või objekte, muuta nginx-serverit, rakendusi või andmeid ega käivitada andmeid muutvaid teste.

## 2. Sisukord

- [3. Dokumendi roll ja staatus](#3-dokumendi-roll-ja-staatus)
- [4. Probleem ja eesmärk](#4-probleem-ja-eesmärk)
- [5. Tehnilise teostatavuse kontrollitud tulemused](#5-tehnilise-teostatavuse-kontrollitud-tulemused)
- [6. Arhitektuuri ülevaade](#6-arhitektuuri-ülevaade)
- [7. Komponendid ja vastutused](#7-komponendid-ja-vastutused)
- [8. Tõeallikad ja vastutuse piirid](#8-tõeallikad-ja-vastutuse-piirid)
- [9. Rakendusepõhine worker ja tööadapter](#9-rakendusepõhine-worker-ja-tööadapter)
- [10. Töö esitamine](#10-töö-esitamine)
- [11. Järjekord ja ühe raske töö piirang](#11-järjekord-ja-ühe-raske-töö-piirang)
- [12. Töö võtmine ja täitmise token](#12-töö-võtmine-ja-täitmise-token)
- [13. Tulevane MVPx wakeup-laiendus](#13-tulevane-mvpx-wakeup-laiendus)
- [14. MVP1 polling](#14-mvp1-polling)
- [15. Heartbeat ja protsessi tegelik olek](#15-heartbeat-ja-protsessi-tegelik-olek)
- [16. Ubuntu restart ja boot ID](#16-ubuntu-restart-ja-boot-id)
- [17. Olekumudel](#17-olekumudel)
- [18. Järjekorra haldustoimingud](#18-järjekorra-haldustoimingud)
- [19. Esimese versiooni ulatusest väljas](#19-esimese-versiooni-ulatusest-väljas)
- [20. Oracle’i loogiline andmemudel](#20-oraclei-loogiline-andmemudel)
- [21. ORDS-i esialgne API](#21-ordsi-esialgne-api)
- [22. Autentimine ja õigused](#22-autentimine-ja-õigused)
- [23. Kasutajaliides](#23-kasutajaliides)
- [24. Võrk ja turvalisus](#24-võrk-ja-turvalisus)
- [25. Tõrkeolukorrad ja taastamine](#25-tõrkeolukorrad-ja-taastamine)
- [26. Logid, tööfailid ja jälgitavus](#26-logid-tööfailid-ja-jälgitavus)
- [27. Testimine](#27-testimine)
- [28. Teostusetapid](#28-teostusetapid)
- [29. Avatud otsused](#29-avatud-otsused)
- [30. Viited](#30-viited)

## 3. Dokumendi roll ja staatus

Käesolev dokument kirjeldab kinnitatud lahendust, milles:

- Jenkinsit ei kasutata;
- Oracle on ühise järjekorra ja selle ärireeglite autoriteetne tõeallikas;
- ORDS on rakenduste ja Oracle’i vaheline HTTPS-liides;
- MVP1 tööde käivitamise algatab rakendusepõhise workeri perioodiline ORDS claim;
- Oracle `DBMS_SCHEDULER` ja `UTL_HTTP` wakeup-teavitus jääb tulevaseks MVPx laienduseks;
- tegelikud pikad tööd käivitatakse Ubuntu serveris rakendusepõhise workeri ja registreeritud adapteri kaudu.

Dokument ei lahenda ühegi liidestatava rakenduse sisemist funktsionaalsust ega otsusta, millised selle rakenduse protsessid ühisesse järjekorda saadetakse. Selle otsuse teeb iga rakendus ise.

[`tehniline_spek.md`](tehniline_spek.md) kirjeldab varasemat Jenkinsi-põhist varianti, mis on kõrvale heidetud ja säilib võrdlus- ning ajaloomaterjalina.

## 4. Probleem ja eesmärk

Mitme rakenduse pikad CPU-, mälu- või kettamahukad protsessid töötavad samal piiratud ressursiga Ubuntu serveril. Rakenduste eraldi sisemised järjekorrad ei takista eri rakenduste raskete tööde samaaegset käivitumist.

Lahenduse eesmärk on:

1. hoida rakendusteülest järjekorda olemasolevas Oracle’i andmebaasis;
2. jõustada esialgu üks samaaegne raske töö;
3. lubada rakendustel esitada töid ja workeritel võtta töid ORDS-i kaudu;
4. käivitada MVP1-s tööd rakendusepõhiste workerite mõõduka perioodilise pollingu kaudu;
5. taastada ohutu olek pärast Ubuntu, workeri, ORDS-i või andmebaasi restarti;
6. säilitada minimalistlik keskne haldusliides;
7. mitte lisada uut andmebaasi, brokerit ega Jenkinsi teenust.

## 5. Tehnilise teostatavuse kontrollitud tulemused

Kasutaja tegi 2.11.2026 Oracle SQL Developeris `ADMIN` kasutajaga järgmised kontrollid:

- teenus on Autonomous OLTP;
- andmebaas on Oracle AI Database 26ai, versioon `23.26.4.1.0`;
- paketid `DBMS_NETWORK_ACL_ADMIN`, `DBMS_SCHEDULER` ja `UTL_HTTP` on olemas ning olekus `VALID`;
- `ADMIN` kasutajal on `CREATE JOB` ja `MANAGE SCHEDULER`;
- hostile `fun-o.eu` lisati `http` võrguõigus;
- otsene `UTL_HTTP` HTTPS `HEAD` päring aadressile `https://fun-o.eu/` tagastas `200 OK`;
- ühekordne `DBMS_SCHEDULER` job `WAKEUP_HTTPS_POC_20261102` lõpetas olekuga `SUCCEEDED` ja veakoodiga `0`.

Katse tõendab tulevase MVPx wakeup-laienduse jaoks järgmise ahela tehnilist toimimist:

```text
Oracle DBMS_SCHEDULER
        │
        ▼
PL/SQL + UTL_HTTP
        │ HTTPS
        ▼
fun-o.eu nginx Ubuntu serveris
```

Katse ei ole MVP1 eeltingimus ega tõenda veel:

- tootmisskeemi õigusi;
- tegeliku wakeup-endpoint’i lepingut ega autentimist;
- `POST`-teavituse vastuvõttu rakenduse workeris;
- ebaõnnestunud wakeup’i korduskatseid;
- terviklikku tööde esitamise, reserveerimise ja lõpetamise voogu.

`ADMIN` kasutajat ei kasutata tootmisrakenduse runtime-kasutajana.

## 6. Arhitektuuri ülevaade

```text
Google’i kasutaja
        │
        ▼
haldus.fun-o.eu ─► nginx ─► haldusveeb ja autentimise backend
                                      │
                                      ▼
                              ORDS haldusendpoint’id
                                      │
                                      ▼
                            Oracle’i järjekorrapaketid

Rakendus A ──► ORDS töö esitamine ────┤
Rakendus B ──► ORDS töö esitamine ────┤
                                      │
                                      ▼
                         Oracle’i autoriteetne järjekord
                   ▲                                     ▲
                   │ ORDS claim iga 5 minuti järel       │ ORDS claim iga 5 minuti järel
                   │                                     │
       Rakenduse A worker                     Rakenduse B worker
                   │                                     │
                   ▼                                     ▼
          registreeritud adapter                registreeritud adapter
                   │                                     │
                   ▼                                     ▼
          tegelik pikk protsess                tegelik pikk protsess
```

Worker ei saa töö käivitamise otsust lokaalselt teha. Perioodiline päring on atomaarne claim: Oracle kontrollib järjekorra esimest käivitatavat tööd ja ühe aktiivse raske töö piirangut ning tagastab töö ainult sobivale workerile.

## 7. Komponendid ja vastutused

### 7.1. Oracle’i rakendusskeem

Vastutab:

- tööde püsiva identiteedi ja oleku eest;
- autoriteetse järjekorra järjestuse eest;
- idempotentsuse eest;
- ühe raske töö piirangu eest;
- töö atomaarse reserveerimise eest;
- täitmise tokenite eest;
- hosti, workeri, heartbeat’i ja `boot_id` metaandmete eest;
- tehnilise sündmusajaloo eest.

`JOBS_APP` on andmete ja äriloogika omanik. Skeem ei ole ORDS-is avaldatav ning tootmisrakendused ei ühendu sellega otse.

### 7.2. ORDS

Vastutab:

- kaitstud REST-endpoint’ide avaldamise eest;
- server-server autentimise ja autoriseerimise eest;
- valideeritud sisendi edastamise eest Oracle’i pakettidele;
- minimaalsete vastuste tagastamise eest.

ORDS ei käivita Ubuntu protsessi ega ole järjekorra teine koopia.

ORDS-is avaldatakse skeem `JOBS_API` base path’iga `jobs`. Rakenduste seadistatav baas-URL on seetõttu kujul `https://<adb-host>/ords/jobs`.

### 7.3. Tulevase MVPx `DBMS_SCHEDULER`

`DBMS_SCHEDULER` ei osale MVP1 tööde käivitamises. Tulevases MVPx wakeup-laienduses võib see vastutada Oracle’i sees ootel wakeup-teavituste asünkroonse saatmise ja kordamise eest.

`DBMS_SCHEDULER` ei käivita Autonomous Database’ist Ubuntu transkribeerimis- või diariseerimisprotsessi. Ta saadab ainult HTTPS-teavituse.

### 7.4. Tulevase MVPx rakenduse wakeup-endpoint

Vastutab:

- Oracle’i saadetud teavituse autentimise eest;
- teavituse unikaalse ID korduskindla vastuvõtu eest;
- sama rakenduse kohaliku workeri äratamise eest.

MVP1-s wakeup-endpoint’e ega nende URL-e ei looda. Tulevases MVPx laienduses on igal liidestatud rakendusel enda wakeup-endpoint ja selle täpne HTTPS URL registreeritakse Oracle’is sama rakenduse kirjes. Keskset rakendusteülest wakeup-vastuvõtjat ei kavandata.

Endpoint’i domeeni, nginx-marsruudi, workeri ja kohaliku äratamise viisi teostab vastava rakenduse projekt. Keskne haldur määrab ainult liidese lepingu ja saadab teavituse registreeritud URL-ile.

Wakeup-endpoint ei võta vastu shellikäsku, adapteri käsku ega usalda teavituses olevat väidet, et töö võib käivituda.

### 7.5. Rakendusepõhine worker

Vastutab:

- oma rakenduse registreeritud töötüüpide teenindamise eest;
- ORDS-ist töö küsimise ja reserveerimise eest;
- rakenduse adapteri käivitamise eest;
- protsessi jälgimise eest;
- heartbeat’i, tulemuse ja lõppoleku teatamise eest;
- sama buudi sees eelmise protsessi olemasolu kontrollimise eest.

### 7.6. Tööadapter

Adapter on rakenduse ja töötüübi leping. See määrab:

- lubatud parameetrid;
- tegeliku käivitusviisi;
- töö runtime-kataloogi ja väljundiviited;
- protsessi lõppoleku tuvastamise;
- logi asukoha.

## 8. Tõeallikad ja vastutuse piirid

| Andmed või otsus | Autoriteetne allikas |
|---|---|
| Ühise järjekorra järjestus | Oracle |
| Töö keskne identiteet ja olek | Oracle |
| Hold-tööd | Oracle |
| Ühe aktiivse raske töö piirang | Oracle |
| Kehtiv täitmise token | Oracle |
| Tegeliku OS-protsessi olemasolu sama buudi sees | vastava rakenduse worker ja adapter |
| Ubuntu buudi identiteet | `/proc/sys/kernel/random/boot_id` |
| Mahukad sisendid, ajutised failid ja väljundid | vastava rakenduse runtime |
| Täielik protsessilogi | vastava rakenduse runtime/logikataloog |
| Google’i lubatud e-posti aadressid | serveri saladuste konfiguratsioon |
| ORDS-i Basic-autentimise kasutajanimi ja parool | vastava kliendi saladuste konfiguratsioon ja ORDS |

Rakendus ei pea hoidma oma ootel tööde kohalikku koopiat. Oracle on ainus autoriteetne allikas selle kohta, millise rakenduse töö on järjekorra ees ja kas seda saab käivitada.

## 9. Rakendusepõhine worker ja tööadapter

Valitud lahendus kasutab iga liidestatud rakenduse juures ühte kerget workerit. Worker võib olla eraldi protsess või rakenduse projekti juurde kuuluv teenus. See ei tähenda uue konteineri loomist iga transkribeerimise või muu töö jaoks.

Rakendusepõhist mudelit eelistatakse kesksele rakendusteülesele täitmisworkerile, sest:

- rakendus tunneb oma sõltuvusi ja runtime-katalooge;
- rakenduse saladusi ei pea koondama kesksesse privilegeeritud teenusesse;
- kesksele workerile ei pea andma Docker socket’it ega ligipääsu kõigi rakenduste keskkondadele;
- tööadapter ja töö runtime’i elutsükkel jäävad rakenduse juurde.

Iga rakendus otsustab ise, millised oma protsessid ta ühisesse järjekorda saadab. Keskne haldur ei juhi ega lahenda rakenduse sisemist töövoogu.

## 10. Töö esitamine

Rakendus esitab ORDS-ile vähemalt:

- registreeritud `application_code` väärtuse;
- registreeritud `job_type` väärtuse;
- kohustusliku `application_job_id` väärtuse, mis seob keskse töö rakenduse enda protsessi või tegevusega;
- töötüübi lepingule vastavad parameetrid;
- unikaalse idempotentsusvõtme.

`application_job_id` ei ole rakenduse kohaliku järjekorra tunnus. Rakenduse sisemist
järjekorda ei peeta; väli võimaldab rakendusel ja workeril siduda Oracle'i keskse
`job_id` rakenduse enda töödeldava protsessi või tegevusega.

Keskne haldusbackend kasutab `JOBS_API` ORDS-i kasutajat. Kui liidestataval rakendusel on oma Oracle'i skeem, kasutab rakendus ja tema worker ORDS-is oma skeemi kasutajat; oma skeemita rakenduse jaoks võib kasutada `JOBS_API` kasutajat. `application_code` tuleb päringu sisust ning praegune ORDS-i moodul ei seo seda autentitud kasutajaga automaatselt. Oracle kontrollib siiski, et kood on registreeritud ja aktiivne ning töötüüp sellele lubatud.

Oracle’i toiming ühe transaktsiooni piires:

1. kontrollib, et kliendi saadetud `application_code` on registreeritud ja aktiivne;
2. kontrollib, et töötüüp on rakendusele lubatud;
3. valideerib parameetrid;
4. leiab sama rakenduse ja idempotentsusvõtmega olemasoleva töö või loob uue;
5. lisab uue tavatöö järjekorra lõppu;
6. tagastab keskse `job_id` ja oleku.

Võrgutõrke järel sama idempotentsusvõtmega korduspäring tagastab olemasoleva töö ega loo duplikaati.

## 11. Järjekord ja ühe raske töö piirang

Oracle hoiab järjekorra tegelikku järjestust. Esialgu võib olla korraga üks aktiivne raske töö.

Ühe aktiivse töö piirang jõustatakse `JOBS.status` alusel Oracle'i unikaalse funktsioonipõhise indeksiga. Indeks annab olekutele `CLAIMED`, `RUNNING` ja `UNKNOWN` sama mittevõtmetu väärtuse ning teistele olekutele `NULL`; seetõttu saab aktiivses olekus olla ainult üks töö.

Claim peab olema atomaarne:

1. kontrollitakse, et ükski töö pole aktiivses olekus;
2. loetakse väikseima `queue_order` väärtusega käivitatav töö, jättes vahele tööd, mille `previous_job_id` viitab tööle, mis pole olekus `SUCCEEDED`;
3. kontrollitakse, et workeri deklareeritud `application_code` vastab leitud tööle ja töötüüp on sellele rakendusele lubatud;
4. luuakse täitmiskatse ja unikaalne täitmise token;
5. töö viiakse olekusse `CLAIMED`;
6. unikaalne indeks välistab teise töö samaaegse aktiivseks muutmise;
7. transaktsioon kinnitatakse;
8. alles seejärel tagastatakse töö workerile.

Kui järjekorra esimene töö kuulub rakendusele, mille worker ei ole kättesaadav, ei tohi teise rakenduse worker sellest vaikimisi mööda minna. Vastasel juhul ei vastaks haldusliideses nähtav järjestus tegelikule täitmisjärjestusele. Blokeeriva töö saab kasutaja panna hold-olekusse või eemaldada.

## 12. Töö võtmine ja täitmise token

Worker saadab claim’is oma `application_code` väärtuse. Oracle ei tagasta tööd, kui järjekorra esimese käivitatava töö rakenduse kood sellega ei ühti. Rakenduse kood on kliendi deklareeritud väärtus; praegune ORDS-i moodul ei seo seda automaatselt autentitud kasutajaga.

Iga reserveerimine saab monotoonselt muutuva või muul viisil üheselt kordumatu täitmise tokeni. Kõik järgnevad teated peavad sisaldama sama tokenit:

- käivitamise kinnitus;
- heartbeat;
- edenemise metaandmed, kui neid kasutatakse;
- edukas või vigane lõpptulemus.

Oracle aktsepteerib teadet ainult siis, kui token kuulub endiselt selle töö aktiivsele täitmiskatsele. See väldib vana workeri või hilinenud võrgupäringu mõju uuemale täitmiskatsele.

Claim peab olema korduskindel. Kui vastus kaob, peab sama worker sama claim’i tunnusega saama tagasi sama reserveeringu, mitte uue töö ega uue täitmiskatse.

## 13. Tulevane MVPx wakeup-laiendus

Käesolev jaotis ei kuulu MVP1 teostusse, andmemudelisse ega vastuvõtukriteeriumidesse. See säilitab kontrollitud PoC tulemuse ja võimaliku hilisema laienduse kavandi.

### 13.1. Põhimõte

Kui Oracle’i transaktsioon muudab järjekorra selliseks, et vaba täitmiskoha jaoks on järgmine töö olemas, luuakse samas transaktsioonis püsiv wakeup’i saatmise kirje.

Wakeup’i vajadus võib tekkida vähemalt siis, kui:

- esimene töö lisatakse tühja järjekorda;
- töötav töö lõpetab ja järgmine töö saab käivitatavaks;
- hold-töö taastatakse olukorras, kus aktiivset rasket tööd ei ole;
- järjekorra ümberjärjestamise järel muutub käivitatav sihtrakendus;
- Ubuntu restardi taastamiskontroll vabastab vana täitmiskoha.

### 13.2. Asünkroonne saatmine

`UTL_HTTP` päringut ei saadeta töö olekut muutva põhitransaktsiooni sees. Vastasel juhul sõltuks järjekorra transaktsiooni kestus ja õnnestumine Ubuntu endpoint’i või võrgu vastusest.

Põhitransaktsioon lisab kirje wakeup’i outbox-tabelisse. `DBMS_SCHEDULER` käivitab eraldi PL/SQL-protseduuri, mis:

1. võtab saatmata teavituse;
2. teeb HTTPS `POST` päringu;
3. märgib eduka saatmise;
4. jätab ebaõnnestunud teavituse kordamiseks ootele;
5. piirab korduskatsete sagedust ja salvestab viimase vea ilma saladusteta.

Wakeup on vähemalt-üks-kord teavitus: sama teavitus võib jõuda endpoint’ini mitu korda. Endpoint peab kasutama unikaalset `notification_id` väärtust ja olema korduskindel.

### 13.3. Teavituse sisu

Teavitus sisaldab minimaalselt:

- `notification_id`;
- sihtrakenduse koodi;
- tehnilist ajatemplimetaandmestikku.

Teavitus ei sisalda:

- shellikäsku;
- adapteri käivituskäsku;
- töö saladusi;
- usaldatavat luba töö käivitamiseks.

Pärast wakeup’i küsib worker ORDS-ist töö. Kui järjekord on vahepeal muutunud, aktiivne raske töö on olemas või workerile sobivat tööd ei ole, ei käivitata midagi.

### 13.4. Wakeup-endpoint’i topoloogia

Iga rakenduse kirjes on selle rakenduse enda täpne HTTPS wakeup-URL. Kui vaba täitmiskoha jaoks leitakse järjekorra esimene töö, lahendab Oracle töö rakenduse kaudu selle registreeritud URL-i ja saadab teavituse otse vastava rakenduse endpoint’ile.

Keskset rakendusteülest wakeup-vastuvõtjat ei kasutata. Rakenduse endpoint äratab ainult sama rakenduse workeri. Worker teeb seejärel ORDS-i kaudu autoriteetse claim’i ega käivita tööd üksnes wakeup’i sisu põhjal.

Wakeup-URL-i registreerimine ja muutmine on haldustoiming. URL peab olema HTTPS-aadress, läbima valideerimise ning vastama lubatud hosti ja Oracle’i võrgu-ACL-i reeglitele. URL-i ennast võib hoida rakenduse kirjes, kuid autentimissaladust ei hoita seal avatekstina.

Iga rakenduse tegeliku domeeni, nginx-konfiguratsiooni, endpoint’i ja workeri loomine jääb vastava rakenduse projekti ülesandeks. Käesolev projekt ei määra nende sisemist teostust.

## 14. MVP1 polling

MVP1 tavarežiimis küsib iga jõude rakenduse worker ORDS-ist tööd iga 5 minuti järel. Intervall on seadistatav, kuid seda ei seata lühemaks kui üks minut. Worker teeb ühe päringu, mis on korraga nii kontroll kui ka atomaarne claim; eraldi „kas tööd on” päringut ei tehta.

Claim sisaldab vähemalt:

- workeri deklareeritud `application_code` väärtust;
- workeri instantsi ID-d;
- `host_id` ja praegust `boot_id` väärtust;
- korduskindlat claim’i tunnust.

Kui aktiivne raske töö on olemas, järjekord on tühi või järjekorra esimene käivitatav töö kuulub teisele rakendusele, tagastab ORDS minimaalse tühja vastuse. Tühja pollingu kohta ei looda töö sündmust ega mahukat rakenduslogi.

Worker teeb claim’i kohe enda käivitumisel ja seejärel 5-minutilise intervalliga. Mitme workeri täpselt samaaegse päringu vältimiseks lisatakse intervallile väike seadistatav juhuslik hajutus.

Töötav worker ei polli uut tööd. Ta saadab aktiivse töö kohta heartbeat’i ja lõppoleku teateid. Kui töö lõpeb, muutub worker taas jõudeolevaks ning järgmine töö käivitub selle rakenduse workeri järgneva eduka claim’i järel.

ORDS-i `429 Too Many Requests`, ajutise 5xx vastuse või võrguvea järel kordab worker sama päringut kasvava ooteajaga ja väikese juhusliku hajutusega. `Retry-After` päise olemasolul kasutatakse vähemalt selles määratud ooteaega. Claim’i kordus kasutab sama claim’i tunnust.

## 15. Heartbeat ja protsessi tegelik olek

Töötav worker saadab MVP1-s heartbeat’i iga 5 minuti järel koos:

- töö ID-ga;
- täitmise tokeniga;
- `host_id` väärtusega;
- `boot_id` väärtusega;
- workeri instantsi ID-ga.

Heartbeat’i aegumine ei tõenda, et protsess on lõppenud. Põhjuseks võib olla ORDS-i, Oracle’i või võrgu tõrge ajal, mil Ubuntu protsess jätkab tööd.

Seetõttu võib aegunud heartbeat muuta töö oleku kontrollimist vajavaks või `UNKNOWN` olekusse, kuid ei vii tööd üksi aktiivsest olekust välja ega luba uut rasket tööd käivitada.

Heartbeat’i intervall on seadistatav. Aegumise piir peab olema intervallist pikem ja ei ole veel kinnitatud. Üks vahele jäänud heartbeat ei muuda tööd lõppenuks ega vii seda aktiivsest olekust välja.

## 16. Ubuntu restart ja boot ID

Töö käivitamisel salvestatakse täitmiskatse juurde Ubuntu väärtus:

```text
/proc/sys/kernel/random/boot_id
```

See identifitseerib konkreetse Linuxi buudi. Worker saadab `host_id` ja praeguse `boot_id` Oracle’ile kohe käivitumisel, enne uue töö küsimist.

### 16.1. Muutunud `boot_id`

Kui sama `host_id` poolelioleva töö salvestatud `boot_id` erineb praegusest, on tõendatud, et vana operatsioonisüsteemi käivitus lõppes ja selle buudi protsess ei saa enam töötada.

Oracle teeb ühe tehinguga:

1. märgib vana täitmiskatse katkestatuks põhjusega `HOST_RESTART`;
2. viib töö kokkulepitud olekusse `INTERRUPTED`, `FAILED` või taastamist vajavasse olekusse;
3. vabastab vana täitmise tokeni ja globaalse täitmiskoha;
4. jätab järgmise töö rakenduse workeri järgneva claim-pollingu jaoks kättesaadavaks.

Katkestatud tööd ei käivitata automaatselt uuesti, kui töötüübi leping ei luba tõendatult korduskindlat automaatset kordust.

### 16.2. Sama `boot_id`

Kui restartis ainult worker või konteiner, kuid `boot_id` ei muutunud, võib vana alamprotsess endiselt töötada. Oracle ei saa selle puudumist ise tõendada.

Vastava rakenduse worker peab kontrollima oma adapteri protsessi, cgroup’i, konteineri või muu usaldusväärse runtime-tunnuse kaudu:

- kui protsess töötab, taastatakse jälgimine;
- kui protsessi puudumine on tõendatud, lõpetatakse vana täitmiskatse;
- kui tulemus on ebaselge, jääb töö `UNKNOWN` olekusse ja uus raske töö ei käivitu.

Pelgalt PID väärtus ei ole piisav, sest PID võib olla taaskasutatud.

## 17. Olekumudel

Kavandatavad olekud:

- `QUEUED` — töö ootab ühises järjekorras;
- `HELD` — töö on säilitatud, kuid ei ole käivitatav;
- `CLAIMED` — töö on workerile reserveeritud, kuid protsessi käivitamine pole veel kinnitatud;
- `RUNNING` — worker kinnitas täitmise alustamise;
- `SUCCEEDED` — töö lõpetas edukalt;
- `FAILED` — töö lõpetas veaga;
- `INTERRUPTED` — töö täitmine katkes näiteks hosti restardi tõttu;
- `REMOVED` — käivitumata töö eemaldati lõplikult;
- `UNKNOWN` — tegelikku täitmisolekut ei saa üheselt tõendada.

Lõppolekute ja `INTERRUPTED` oleku korduskäivituse täpne poliitika tuleb enne andmemudeli lukustamist kinnitada.

`UNKNOWN` jääb aktiivseks olekuks ja takistab uue raske töö claim'i.

## 18. Järjekorra haldustoimingud

Oracle teostab samas autoriteetses järjekorras järgmised toimingud:

- `move-up`;
- `move-down`;
- `move-first`;
- `move-last`;
- `hold`;
- `resume`, mis lisab töö järjekorra lõppu;
- käivitumata töö eemaldamine.

Toiming lukustab mõjutatud read ja kontrollib nende tegelikku hetkeseisu. Kui toiming ei ole enam lubatud, tagastatakse konflikt ja muudatust ei rakendata.

Kui hold- või eemaldamistoiming võistleb claim’iga, otsustab Oracle’i transaktsiooniline lukk, kumb toiming sai esimesena õiguse. Juba `CLAIMED` või `RUNNING` tööd ei muudeta hold-toiminguga töötava töö katkestamiseks.

## 19. Esimese versiooni ulatusest väljas

Töötava `CLAIMED` või `RUNNING` töö kasutaja algatatud katkestamine ei kuulu selle versiooni ulatusse. Keskne haldur ei paku selleks API-t, kasutajaliidese toimingut ega workeri või adapteri katkestamis- ja koristamislepingut.

See piirang ei muuda tõrkejärgset taastamist. Hosti restardi või muu tõendatud ootamatu lõppemise korral viiakse täitmiskatse taastamisreeglite järgi olekusse `INTERRUPTED`, `FAILED` või `UNKNOWN`. Käivitumata `QUEUED` või `HELD` töö eemaldamine jääb järjekorra tavaliseks haldustoiminguks.

## 20. Oracle’i loogiline andmemudel

MVP1 füüsiline andmemudel, tabelite kommentaarid, võtmed ja terviklusreeglid asuvad failis [`db/erd.md`](../db/erd.md). Teostav DDL asub failis [`db/schema/001_core_schema.sql`](../db/schema/001_core_schema.sql).

Loogiliselt on vaja vähemalt järgmisi andmegruppe.

### 20.1. Rakendused

- rakenduse kood;
- lubatud olek;
- rakenduse kirjeldav nimi;
- lubatud töötüüpide seos.

### 20.2. Töötüübid

- rakenduse kood;
- töötüübi kood;
- inimesele kuvatav nimi;
- lubatud olek.

### 20.3. Tööd

- sequence'ist saadav keskne `job_id`;
- rakenduse ja töötüübi kood;
- kohustuslik `application_job_id`, mis seob keskse töö rakenduse enda protsessi või tegevusega;
- valikuline eelmise töö viide;
- idempotentsusvõti;
- tööliigi lepingu järgi valideeritud parameetrid JSON-vormingus;
- olek ja `queue_order`;
- ajatemplid, mille väärtused on UTC-s.

Unikaalsus peab hõlmama vähemalt rakenduse identiteeti ja idempotentsusvõtit.

### 20.4. Täitmiskatsed

- töö ID ja katse number;
- täitmise token;
- workeri instantsi ID;
- `host_id` ja `boot_id`;
- claim’i, käivituse, heartbeat’i ja lõpu ajad;
- exit code ja lõpetamise põhjus.

### 20.5. Ühe aktiivse töö piirang

Eraldi täitmiskohtade tabelit MVP1-s ei ole. Korraga ühe aktiivse raske töö reeglit jõustab `JOBS.status` põhine unikaalne funktsioonipõhine indeks. Oleku `UNKNOWN` korral jääb piirang kehtima ja uut rasket tööd ei saa claim'ida.

### 20.6. Sündmused

- töö ID;
- sündmuse tüüp;
- tegutseja liik ja identiteet;
- tehnilised detailid ilma saladusteta;
- UTC ajatempel.

Tühja pollingu kohta ei looda sündmust.

### 20.7. Tulevase MVPx wakeup outbox

Seda andmegruppi MVP1 skeemi ei lisata. Wakeup-laienduse korral on vaja vähemalt:

- teavituse ID;
- sihtrakendus;
- olek;
- loomise, viimase katse ja eduka saatmise aeg;
- katsete arv;
- järgmise katse aeg;
- viimase vea puhastatud kokkuvõte.

## 21. ORDS-i esialgne API

Teostatud endpoint'ide lakooniline kasutusjuhend asub failis
[`api.md`](api.md). Oracle'i facade-pakett asub failis
[`db/api/002_jobs_api_package.sql`](../db/api/002_jobs_api_package.sql) ja
ORDS-handlerid failis
[`db/ords/004_ords_handlers.sql`](../db/ords/004_ords_handlers.sql).

### 21.1. Rakenduse tööde API

Töö esitamise endpoint on:

```text
POST /ords/jobs/application/jobs
```

JSON-päring sisaldab:

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

`previous_job_id` on valikuline. `parameters` on JSON-objekt, mis salvestatakse
Oracle'i veergu `JOBS.parameters_json`.

Uue töö loomisel tagastatakse `201 Created`:

```json
{
  "job_id": 123,
  "status": "QUEUED"
}
```

Sama rakenduse sama idempotentsusvõtmega korduspäring tagastab olemasoleva töö
tegeliku keskse oleku vastusega `200 OK`. Kui sama idempotentsusvõtmega päringu
`job_type_code`, `application_job_id`, `previous_job_id` või `parameters` erineb
algsest päringust, tagastatakse `409 Conflict`; olemasolevat tööd ei muudeta ja
uut tööd ei looda.

Deklareeritud rakenduse töö oleku endpoint on
`GET /ords/jobs/application/jobs/:job_id`; `application_code` saadetakse
query-parameetrina.

Kõik API veavastused kasutavad kuju:

```json
{
  "error_code": "IDEMPOTENCY_CONFLICT",
  "message": "Idempotency key is already used for a different job.",
  "oracle_error": "ORA-20xxx: idempotency key is already used for a different job"
}
```

`error_code` on stabiilne masinloetav tunnus ja klient ei tee äriloogilisi
otsuseid `oracle_error` teksti põhjal. Oracle'ist pärineva vea korral sisaldab
`oracle_error` tegelikku Oracle'i veateadet. Varem defineerimata Oracle'i viga
tagastatakse HTTP `500 Internal Server Error` vastusega, `error_code` väärtusega
`INTERNAL_ERROR` ja tegeliku Oracle'i veateatega. PL/SQL backtrace'i vastusesse
ei lisata.

Paketi fikseeritud ja andmemudeli veerupikkustega piiratud vastused kasutavad
`VARCHAR2(4000)` tagastustüüpi. `CLOB` on kasutusel ainult vastustes, mille maht
sõltub töö `parameters` JSON-ist või tagastatavate tööde, täitmiskatsete või
sündmuste arvust.

### 21.2. Workeri API

- hosti ja workeri käivituse registreerimine koos `boot_id` väärtusega;
- töö claim;
- käivitamise kinnitamine;
- heartbeat;
- töö lõpetamine.

### 21.3. Haldus-API

- `GET /ords/jobs/admin/queue` — töötava, ootel ja hold-tööde vaade;
- `GET /ords/jobs/admin/jobs/:job_id` — töö detail;
- `POST /ords/jobs/admin/jobs/:job_id/move-up` — ootel töö ühe koha võrra üles;
- `POST /ords/jobs/admin/jobs/:job_id/move-down` — ootel töö ühe koha võrra alla;
- `POST /ords/jobs/admin/jobs/:job_id/move-first` — ootel töö järjekorra algusesse;
- `POST /ords/jobs/admin/jobs/:job_id/move-last` — ootel töö järjekorra lõppu;
- `POST /ords/jobs/admin/jobs/:job_id/hold` — ootel töö hold-olekusse;
- `POST /ords/jobs/admin/jobs/:job_id/resume` — hold-töö järjekorra lõppu;
- `POST /ords/jobs/admin/jobs/:job_id/remove` — ootel või hold-töö lõplik eemaldamine.

Muutva halduspäringu JSON-keha sisaldab välja `actor_id`, mille väärtuseks paneb
haldusbackend Google'iga autenditud kasutaja e-posti aadressi. Eemaldamise
kinnituse küsib kasutajaliides enne ORDS-i väljakutset.

Rakenduse ja workeri päring sisaldab `application_code` väärtust. Endpoint’id tagastavad ainult selle deklareeritud rakenduse jaoks vajaliku minimaalse andmehulga. Praegune ORDS-i Basic-autentimine ei seo kasutajat automaatselt `application_code` väärtusega.

## 22. Autentimine ja õigused

### 22.1. ORDS-i kasutaja

Rakendused, workerid ja haldusbackend kasutavad `fun_o` projektiga sama
põhimustrit: ORDS-i HTTPS URL ning HTTP Basic autentimine. OAuth 2.0
`client_credentials` voogu ei kasutata.

`JOBS_API` on ORDS-i avaldatud fassaadi skeem ning keskse haldusbackendi
ORDS-i kasutaja. Kui liidestataval rakendusel on oma Oracle'i skeem, kasutab
rakendus ja tema worker ORDS-i jaoks oma skeemi kasutajat. Sellel kasutajal
peab olema ORDS-i REST-enable ning õigus moodulile `jobs.api`; praeguses
teostuses annab selle privilege `jobs.api.auth` kaudu ORDS-i roll `SQL Developer`.

Rakenduse oma ORDS-i kasutaja ei vaja `JOBS_APP` tabeli- ega paketiõigusi:
handler käivitub `JOBS_API` skeemis ja kutsub sealt `JOBS_APP` facade-paketti.
Oma skeemita rakenduse jaoks võib kasutada `JOBS_API` kasutajat.

Iga ORDS-i kasutajanimi ja parool:

- asub vastava kliendi saladuste konfiguratsioonis;
- ei kuulu Git-i;
- ei lähe töö parameetritesse ega logidesse;
- peab olema roteeritav.

Rakendus saadab `application_code` väärtuse päringus. Oracle kontrollib, et
kood on aktiivne ja töötüüp sellele lubatud. Praegune ORDS-i moodul ei seo
autenditud kasutajat automaatselt `application_code` väärtusega.

### 22.2. Inimese haldusliides

Google’i autentimine ja `.env`-is lubatud e-posti aadresside loend jäävad inimese
haldusliidese jaoks eraldi mehhanismiks. Google’i identiteeti ei kasutata
rakenduse worker’i autentimiseks. Google'iga autenditud haldusbackend kasutab
ORDS-i kutsumiseks `JOBS_API` Basic-mandaati.

### 22.3. Oracle’i skeemid

Tootmislahendus ei tööta `ADMIN` kasutajana. Kasutatakse kahte skeemi:

1. `JOBS_APP` omab järjekorra tabeleid, sequence’e ja definer-rights PL/SQL-pakette;
2. `JOBS_API` on ORDS-is base path’iga `jobs` avaldatud REST-fassaad.

`JOBS_API` ei saa otseõigusi `JOBS_APP` tabelitele. Ta saab ainult `EXECUTE` õiguse konkreetselt ORDS-i jaoks mõeldud facade-paketile ning kutsub seda täielikult kvalifitseeritud nimega. Synonym ei ole nõutav.

MVP1 ei vaja rakendusskeemile Oracle’ist väljamineva HTTPS-i õigust. Tulevase wakeup-laienduse korral annab `ADMIN` selle ainult täpselt kinnitatud wakeup-hostidele; `DBMS_NETWORK_ACL_ADMIN` haldusõigust rakendusskeemile ei anta.

## 23. Kasutajaliides

Minimalistliku haldusliidese nõuded jäävad samaks:

- Google’iga sisselogimine;
- töötava töö ja tegeliku järjekorra kuvamine;
- hold-tööd;
- töö detail koos päritolurakenduse, töötüübi, oleku ja aegadega;
- järjekorra liigutamine;
- hold, resume ja käivitumata töö eemaldamine.

Brauser ei suhtle Oracle’i tabelitega otse. Haldusveebi backend kontrollib Google’i sessiooni ja kasutab kaitstud ORDS-i haldusendpoint’e.

Teostus asub projekti `backend/` kataloogis ning serveerib samast FastAPI
konteinerist ka staatilise kasutajaliidese. Backend on Docker Compose’is
ühendatud olemasoleva välise `funo_net` võrguga teenusena
`queue_management_api`. Keskse nginx-i `haldus.fun-o.eu` HTTPS-serveriplokk
suunab kogu liikluse sellele teenusele. Let’s Encrypti sertifikaat `fun-o.eu`
katab ka `haldus.fun-o.eu` domeeni.

Google’i lubatud aadresside loend on `GOOGLE_ALLOWED_EMAILS` muutujas ning
Google’i klienditunnus `GOOGLE_CLIENT_ID` muutujas. Eduka Google’i ID-tokeni
kontrolli järel loob backend `SESSION_SECRET`-iga signeeritud `HttpOnly`
sessiooniküpsise. Haldustoimingu sündmuse `actor_id` tuleb sessiooni e-posti
aadressist, mitte brauseri sisendist.

## 24. Võrk ja turvalisus

- Rakenduste tööde esitamine, claim, heartbeat ja olekuteatamine liiguvad rakendusest otse ORDS-i HTTPS API-sse, mitte avaliku `haldus.fun-o.eu` rakenduste API kaudu.
- ORDS-i URL ei ole avalikust internetist kättesaadav; ligipääsu piirab Oracle Cloudi taseme võrgu-ACL.
- ORDS-i Basic-autentimise mandaat on täiendav rakendustaseme kaitse, mitte võrgu-ACL-i asendus.
- Keskne haldusbackend kasutab `JOBS_API` mandaati. Oma Oracle'i skeemiga rakendus võib kasutada oma ORDS-i kasutajat; `application_code` jääb siiski kliendi deklareeritud väärtuseks.
- Kõik töö parameetrid valideeritakse Oracle’i paketis töötüübi lepingu järgi.
- Saladusi ei kirjutata Oracle’i sündmustesse, URL-idesse, rakenduslogidesse ega Git-i.
- Brauser ei suhtle ORDS-i rakenduste või workerite endpoint’idega otse.
- MVP1 ei vaja Oracle’ist Ubuntu serveri suunas avalikku tehnilist endpoint’i.
- Tulevase MVPx wakeup-laienduse korral rakenduvad lisaks jaotises 13 kirjeldatud HTTPS-, autentimis- ja võrgu-ACL-i nõuded.

## 25. Tõrkeolukorrad ja taastamine

### 25.1. Töö esitamise vastus kaob

Rakendus kordab päringut sama idempotentsusvõtmega ja saab olemasoleva töö ID.

### 25.2. ORDS tagastab `429`, ajutise 5xx vastuse või päring ebaõnnestub võrgus

Klient kordab sama loogilist päringut kasvava ooteajaga ja väikese juhusliku hajutusega. `Retry-After` päise olemasolul järgitakse vähemalt seda. Töö esitamisel kasutatakse sama idempotentsusvõtit, claim’il sama claim’i tunnust ning olekuteatel sama täitmise tokenit.

### 25.3. Claim’i vastus kaob

Worker kordab sama claim’i tunnusega päringut. Oracle tagastab sama reserveeringu või selle autoriteetse hetkeseisu.

### 25.4. ORDS või Oracle pole ajutiselt kättesaadav

Juba töötavat protsessi ei lõpetata ainult heartbeat’i saatmise vea tõttu. Worker kordab olekuteadet. Oracle ei väljasta samal ajal uut tööd, kuni vana töö tegelik olek pole tõendatud.

### 25.5. Worker restartis, Ubuntu ei restartinud

`boot_id` on sama. Worker kontrollib oma rakenduse runtime’i. Ebaselgus viib `UNKNOWN` olekusse ja säilitab täitmiskoha blokeeringu.

### 25.6. Ubuntu restartis

Uus `boot_id` tõendab vana buudi protsessi lõppu. Oracle lõpetab vana täitmiskatse ja vabastab koha. Järgmine töö käivitub vastava rakenduse workeri järgneva eduka claim-pollingu järel.

### 25.7. Oracle restartis

Järjekord, aktiivse töö olek ja tokenid taastuvad püsivatest tabelitest. Workerite järgmine heartbeat või claim kooskõlastab runtime’i oleku.

### 25.8. Heartbeat jääb saamata

Kadunud või aegunud heartbeat ei vii tööd aktiivsest olekust välja. See võib tekitada hoiatuse või viia töö kontrollimist vajavasse `UNKNOWN` olekusse. Uue aktiivse töö saab lubada ainult kinnitatud lõpptulemuse või vana protsessi puudumise tõendi alusel.

## 26. Logid, tööfailid ja jälgitavus

- Oracle säilitab töö metaandmed, olekud, täitmiskatsed ja tehnilised sündmused.
- Täielikku transkribeerimis-, diariseerimis- või muud protsessilogi Oracle’isse ei salvestata.
- Mahukad sisendid, ajutised failid ja väljundid jäävad rakenduse runtime-kataloogi.
- Oracle’is hoitakse ainult keskse järjekorra, täitmiskatsete ja sündmuste metaandmeid.
- Rakenduse logi peab olema seostatav keskse töö ID ja täitmise tokeniga.
- Tühja pollingu ja heartbeat’i tavapärane liiklus ei tohi tekitada piiramatut sündmus- ega rakenduslogi.
- Säilitamisajad ei ole veel kinnitatud.

## 27. Testimine

### 27.1. Tulevase wakeup-laienduse juba tehtud tehniline tõendus

- `UTL_HTTP` otsene HTTPS-päring Oracle’ist Ubuntu serverile;
- sama päring `DBMS_SCHEDULER` taustajob’ist;
- mõlemad katsed õnnestusid `ADMIN` kasutajana hostile `fun-o.eu`.

### 27.2. Skeemi- ja ORDS-i PoC

- tootmisele kavandatud piiratud skeemi õigused;
- `JOBS_API` haldusmandaat ning oma skeemiga rakenduse ORDS-i kasutaja;
- Oracle Cloudi võrgu-ACL-i tegelik ligipääsupiirang;
- kliendi saadetud `application_code` ja selle lubatud töötüübi kontroll;
- keelatud töötüübi tagasilükkamine.

### 27.3. Järjekorra integratsioonikatsed

3. novembril 2026 tehtud tegelike ORDS smoke-testide tulemused asuvad failis
[`ords_api_testitulemused.md`](ords_api_testitulemused.md). Järgmised punktid
kirjeldavad veel katmata või korduvat integratsioonikatsete mahtu.

- idempotentne töö esitamine;
- kahe rakenduse tööd ühes järjekorras;
- korraga ainult üks kehtiv täitmise token;
- range järjekorra järjestus;
- hold, resume, eemaldamine ja ümberjärjestamine;
- claim’i vastuse kadumine;
- `429` vastus töö esitamisel, claim’il, heartbeat’il ja lõpetamisel koos korduskindla retry’ga;
- mitme jõude workeri samaaegne claim, millest ainult üks saab globaalse täitmiskoha;
- hilinenud vana tokeniga heartbeat’i tagasilükkamine.

### 27.4. Pollingu ja heartbeat’i integratsioonikatsed

- jõude worker teeb claim’i 5-minutilise seadistatava intervalliga;
- töötav worker ei polli uut tööd;
- töötav worker saadab heartbeat’i 5-minutilise seadistatava intervalliga;
- tühjad pollingud ei loo töö sündmusi ega piiramatut logi;
- kadunud või aegunud heartbeat ei vii tööd aktiivsest olekust välja;
- järjekorra esimese töö rakenduse worker puudub ning teine rakendus ei möödu sellest tööst.

### 27.5. Tulevase MVPx wakeup’i integratsioonikatsed

Neid katseid MVP1-s ei tehta:

- outbox-kirje loomine samas transaktsioonis järjekorra muutusega;
- Scheduler `POST` tegelikule wakeup-endpoint’ile;
- endpoint’i autentimine;
- korduv sama `notification_id`;
- ajutine võrguviga ja korduskatse;
- wakeup’i kadumine ning varupolling.

### 27.6. Taastamiskatsed

- workeri restart sama `boot_id` väärtusega;
- Ubuntu restart uue `boot_id` väärtusega;
- ORDS-i ajutine puudumine töötava töö ajal;
- Oracle’i ajutine puudumine töötava töö ajal;
- ebaselge protsessi olek ja `UNKNOWN` blokeering;
- `HELD` töö säilimine kõigi restartide järel.

Kõik andmebaasi või tegelikke tööfaile muutvad testid vajavad enne eraldi kasutaja luba ja isoleeritud testandmeid.

## 28. Teostusetapid

### Etapp 0 — dokumentatsiooni kooskõlastamine

- märkida ORDS valitud ja Jenkins kõrvale heidetud variandiks;
- eraldada MVP1 polling ja tulevane MVPx wakeup;
- viia lähteülesanne, tööreeglid ja tehniline spetsifikatsioon kooskõlla.

### Etapp 1 — skeemikavand ja API leping

- kinnitada ühe või kahe skeemi mudel ja nimed;
- lukustada tabelite ning olekute leping;
- koostada ja hoida ajakohasena rakenduste ORDS API kasutusleping;
- koostada `JOBS_API` haldusmandaadi, rakenduse oma ORDS-i kasutaja ning `application_code` kontrolli leping;
- kinnitada polling’u, heartbeat’i ja retry seadistus.

### Etapp 2 — Oracle’i järjekorra PoC

- versioonitud skeem;
- idempotentne esitamine;
- autoriteetne järjestus;
- ühe aktiivse raske töö piirang;
- claim ja täitmise token;
- sündmused.

### Etapp 3 — rakenduse worker’i näidis

- üks ohutu näidisworker ja adapter;
- 5-minutiline seadistatav polling;
- heartbeat ja lõpetamine.

### Etapp 4 — haldusliides

- Google’i autentimine;
- järjekorra-, hold- ja detailivaated;
- ümberjärjestamine, hold, resume ja eemaldamine;

### Etapp 5 — esimene tegelik adapter

- adapter valitakse eraldi otsusega;
- rakendus ise otsustab, millised oma protsessid saadetakse kesksesse järjekorda;
- kontrollitakse tööfailide elutsüklit, tulemust ja taastamist.

### Tulevane MVPx — wakeup-laiendus

- wakeup outbox’i skeemimuudatus;
- `DBMS_SCHEDULER` outbox’i saatja;
- turvatud rakendusepõhised wakeup-endpoint’id;
- vähemalt-üks-kord teavituse deduplikeerimine;
- polling jääb taastamise varumehhanismiks.

## 29. Avatud otsused

Enne MVP1 lõpetamist tuleb kinnitada:

1. pollingu ja heartbeat’i 5-minutilise intervalli juhusliku hajutuse piir;
2. heartbeat’i aegumise piir, mis ei vii tööd automaatselt aktiivsest olekust välja;
3. `INTERRUPTED` oleku täpne tähendus ja lubatud korduskäivituse poliitika;
4. claim’i ja protsessi käivitamise vahelise ootamatu tõrke taastamisreegel;
5. `UNKNOWN` olekust kontrollitud väljumise ja operaatori sekkumise kord;
6. kas töötüübipõhine maksimaalne tavapärane kestus on ainult hoiatus või mõjutab olekut;
7. esimesed tegelikud töötüübid ja nende parameetrilepingud;
8. logide, sündmuste ja lõpetatud tööde säilitamisajad;

Tulevase MVPx wakeup-laienduse avatud otsused on:

1. wakeup-päringu autentimise ja saladuse roteerimise viis;
2. rakenduse wakeup-URL-i registreerimise, muutmise, valideerimise ja keelamise reeglid;
3. outbox’i Scheduler job’i käivitusviis, kordusintervall ja lõplikult ebaõnnestunud teavituse käsitlus;
4. wakeup-hostinimede TLS-i ja Oracle’i väljamineva võrgu ACL-i nõuded.

## 30. Viited

- [`lahteylesanne.md`](lahteylesanne.md) — projekti probleem, ulatus ja vastuvõtukriteeriumid.
- [`tehniline_spek.md`](tehniline_spek.md) — kõrvale heidetud Jenkinsi-põhine tehniline variant.
- [Oracle: Call Web Services from Autonomous AI Database](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/call-web-services.html) — `UTL_HTTP`, võrgu-ACL ja avaliku või privaatse sihthosti nõuded.
- [Oracle: PL/SQL Package Notes for Autonomous AI Database](https://docs.oracle.com/en/cloud/paas/autonomous-json-database/ajdug/autonomous-plsql-packages.html) — `DBMS_SCHEDULER` ja `UTL_HTTP` piirangud Autonomous Database’is.
- [Oracle REST Data Services: Developing REST Applications](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.3/orddg/developing-REST-applications.html) — ORDS moodulid, handlerid ja REST-rakenduste teostus.
- `/home/ubuntu/fun_o/backend/app/main.py` — kontrollitud `ORDS_BASE_URL`, `ORDS_USERNAME`, `ORDS_PASSWORD` ja HTTP Basic päringumuster.
- `/home/ubuntu/fun_o/db/oracle/ords/07_ords_handlers.sql` ning `/home/ubuntu/fun_o/db/oracle/security/06_grants_runtime.sql` — kontrollitud ORDS API skeemi ja pakettide `EXECUTE` õiguste muster.
- [Linux kernel documentation: `/proc/sys/kernel/random/boot_id`](https://docs.kernel.org/admin-guide/sysctl/kernel.html#random) — buudi identifikaatori omadus.
