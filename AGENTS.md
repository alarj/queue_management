# Projekti tööreeglid

## 1. Dokumendi päritolu

Koostaja: AI (OpenAI Codex), kasutaja juhiste järgi. Esimene versioon kopeeriti projekti `ttu_loeng` tööjuhendist ning kohandati algselt Jenkinsi-põhise serveriülese tööjärjekorra projektile. Hiljem valiti Oracle’i ja ORDS-i põhine lahendus ning Jenkinsi variant jäeti võrdlusmaterjaliks.

## 2. Sisukord

- [3. Charset ja failivorming](#3-charset-ja-failivorming)
- [4. Peamine tööreegel: enne vastamist tutvu olemasoleva olukorraga](#4-peamine-tööreegel-enne-vastamist-tutvu-olemasoleva-olukorraga)
- [5. Tööpõhimõtted](#5-tööpõhimõtted)
- [6. Projekti dokumentide koostamine](#6-projekti-dokumentide-koostamine)
- [7. Vea käsitlemise juhis](#7-vea-käsitlemise-juhis)
- [8. Mittefunktsionaalsed ootused](#8-mittefunktsionaalsed-ootused)
- [9. Dokumentatsiooni ja tõeallikate register](#9-dokumentatsiooni-ja-tõeallikate-register)
- [10. Millal mida kindlasti lugeda](#10-millal-mida-kindlasti-lugeda)
- [11. Väljundi ootused](#11-väljundi-ootused)

## 3. Charset ja failivorming

- Kõik kood, konfiguratsioon ja dokumentatsioon peavad olema UTF-8 kodeeringus.
- Uute failide loomisel ja olemasolevate failide muutmisel tuleb säilitada UTF-8.
- Kui failis esineb kodeeringuprobleem, tuleb see käsitleda veana ja parandada juurpõhjus, mitte peita sümptomit.

## 4. Peamine tööreegel: enne vastamist tutvu olemasoleva olukorraga

- Enne igat sisulist vastust, hinnangut, kavandamist või muudatust tuleb tutvuda ülesandega seotud olemasoleva dokumentatsiooni, koodi ja andmetega.
- Seda nõuet tuleb järgida ka siis, kui kasutaja küsib ainult selgitust või plaani: vastus peab põhinema projekti tegelikul olukorral, mitte üldisel oletusel.
- Enne muudatuste kavandamist tuleb läbi lugeda kõik dokumendid ja koodiosad, mis puudutavad muudetavat ala. Vajaduse korral tuleb kontrollida ka olemasolevaid tööartefakte, logisid, konfiguratsiooni ja näidisandmeid.
- Olemasolev dokumentatsioon, kood, konfiguratsioon, logid ja andmed ei ole iseenesest õiged ega valed. Iga allikas kirjeldab seda, mis projektis on kirjas, teostatud või vaadeldav; selle olemasolu ei tõenda veel väite õigsust ega allika ülimuslikkust.
- Dokumentatsiooni olemasolu ei vabasta koodi ja tegelike andmete kontrollimisest. Samuti ei tohi toimivat koodi või olemasolevaid andmeid automaatselt pidada dokumentatsioonist õigemaks.
- Kui dokumentide eneste, dokumentatsiooni ja koodi, dokumentatsiooni ja andmete, koodi ja andmete või muude allikate vahel esineb vastuolu, ei tohi iseseisvalt otsustada, milline allikas on õigem või ajakohasem.
- Vastuolu avastamisel tuleb sisuline töö selles küsimuses peatada, kirjeldada kasutajale täpselt vastuolus olevad väited või vaatlused ning küsida enne jätkamist kasutaja otsust. Ka näiliselt ilmset vastuolu ei tohi vaikimisi lahendada.
- Kui vajalik allikas puudub või töö käigus tekib kahtlus, ei tohi lünka oletusega peita. Kontrolli olemasolevat materjali ning kui kontroll ei anna üheselt kooskõlalist tulemust, peatu ja küsi üle.

## 5. Tööpõhimõtted

- Ülesannet ei tohi iseseisvalt laiendada ega kitsendada. Kui ülesande laiendamine või kitsendamine tundub vajalik, tuleb enne muudatuse tegemist kasutajalt küsida.
- Kasutusele ei tohi võtta enda välja mõeldud mõisteid ega termineid, mille sisu ei ole inimesele arusaadavalt lahti seletatud.
- Kasutada ei tohi mõõtühikuid, mida ei ole kasutajaga kokku lepitud ja mille olemus ei ole inimesele üheselt arusaadav.
- Ärireeglid peavad elama võimalikult tsentraalselt ja järjekindlalt; väldi reeglite dubleerimist eri kihtides.
- Muudatused peavad olema minimaalsed, sihitud ja kooskõlas olemasoleva arhitektuuriga.
- Töötavat koodi ei tohi igaks juhuks muuta ega ennetavalt parandada. Kui mingi osa töötab ja ei ole uuritava vea tõendatud juurpõhjus, siis seda ei muudeta.
- Ära muuda kõrvalisi faile ega paranda mitteseotud probleeme.
- Kõrge mõjuga otsuste puhul eelista juurpõhjuse parandamist, mitte lokaalseid ümberkäike.
- Pikad protsessid tuleb käivitada asünkroonselt nii, et vestlusaken jääb kasutajale vabaks. Protsessil peab olema hiljem kontrollitav olek, logi ja väljund; pelgalt terminaliseansi elus püsimisele ei tohi tugineda.
- Tavatöö vaikekäitumine on serveripoolselt ühise järjekorra lõppu lisamine.
- Brauser ega liidestatud rakendus ei tohi anda suvalist shellikäsku. Käivitada võib ainult registreeritud ja valideeritud tööadaptereid.
- Töötava töö katkestamist ei lisata enne, kui kogu protsessipuu, konteinerite ja ajutiste ressursside koristamine on teostatud ning kontrollitud.

### Dokumentatsiooni ajakohastamine

- Pärast iga muudatust tuleb alati uuendada ka muudatuse piirkonda kirjeldavat dokumentatsiooni.
- Eraldi tuleb kontrollida kõiki projekti dokumente, mida muudatus võib mõjutada, ning veenduda, et muudatuse otsene ja kaudne mõju on neis arvesse võetud.
- Muudatust ei loeta lõpetatuks enne, kui see dokumentatsiooni mõjukontroll on tehtud ja vajalikud dokumendimuudatused on rakendatud.

### Git ja juurutus

- `git commit` vajab kasutaja iga töökorra jaoks eraldi luba.
- `git push` vajab kasutaja iga töökorra jaoks eraldi luba.
- Kuna rakendus töötab samas serveris, piisab testimiseks koodi muutmisest ning
  vajaliku konteineri ehitamisest ja taaskäivitamisest; commit'i ega push'i ei
  tohi eeldada juurutuse eeltingimusena.

### Testimine ja andmete muutmine

- Ilma kasutaja eraldi loata ei tohi käivitada teste ega kontrollskripte, mis
  kirjutavad andmebaasi või muudavad olemasolevaid andmeid.
- Ilma sellise loata on lubatud ainult dry-run'id, lugemispäringud ja muud
  mitte-muteerivad kontrollid.
- Mistahes andmeid või andmestruktuuri muutvat tegevust ei tohi teha ilma
  kasutaja eelneva eraldi loata — mitte kunagi. See hõlmab nii andmeridade
  lisamist, muutmist ja kustutamist kui ka tabeli, veeru, indeksi, piirangu või
  sequence'i lisamist, muutmist või kustutamist ning migratsiooni rakendamist.
- Kui kontroll eeldab andmete muutmist, tuleb enne peatuda ja küsida kasutajalt
  eraldi luba.

## 6. Projekti dokumentide koostamine

- Projekti dokumentide vaikevorming on Markdown (`.md`), kui kasutaja ei ole sõnaselgelt nõudnud teistsugust vormingut.
- Dokumendi esimene jaotis peab alati olema „Dokumendi päritolu“. Selles tuleb märkida, kas dokumendi koostas inimene või AI; vajaduse korral kirjeldatakse lühidalt ka alusmaterjale ja inimese panust.
- Dokumendi teine jaotis on üldjuhul „Sisukord“.
- Sisukorra võib ära jätta ainult siis, kui dokument sisaldab alla kolme sisulise punkti ja on lühem kui neli lehekülge. Muudel juhtudel on sisukord kohustuslik.
- Dokumendi päritolu jaotist sisukorda ei lisata.

## 7. Vea käsitlemise juhis

- Vea või regressiooni korral uuri esmalt juurpõhjust.
- Uuri kogu ahelat, mitte ainult vea esinemise kohta.
- Ära piirdu ainult sümptomit eemaldava parandusega, kui juurpõhjus jääb alles.
- Tee veast, selle põhjustest ja võimalikest parandusvariantidest kokkuvõte ning küsi nõusolek parandamiseks.
- Vastuses või töö kokkuvõttes kirjelda võimalusel lühidalt:
  1. mis oli juurpõhjus;
  2. miks viga tekkis;
  3. kuidas tehtud parandus selle kõrvaldab;
  4. milline jääkrisk või eeldus alles jääb.
- Kui loogiline koht on olemas, lisa või uuenda test, mis kinnitab parandust.

## 8. Mittefunktsionaalsed ootused

- Hoia API, andmemudeli, tööartefaktide ja ärireeglite käitumine eri klientide jaoks järjekindel.
- Väldi lahendusi, mis suurendavad põhjendamatult CPU-, mälu-, ketta-, võrgu- või andmebaasikoormust.
- Serveri jagatud CPU-ressursi tõttu töötab esialgu korraga üks raske töö.
- API teenused peavad tagastama konkreetse kasutusjuhtumi jaoks vajaliku minimaalse andmehulga.
- Oracle’is on autoriteetne aeg UTC ning kasutajaliides kuvab aja kasutaja lokaalses ajavööndis.
- Kasutajaliidese tekstid peavad olema tõlgetest, mitte kõvakodeeritud.
- Eelista korduvate väärtuste puhul eeldefineeritud konstante ja ühist äriloogikat.
- Saladused, Google’i lubatud e-posti aadressid, ORDS-i mandaat ja autentimisküpsised tulevad `.env`-ist või muust saladuste hoidlast ning neid ei tohi kirjutada Git-i, logidesse ega väljunditesse.
- Mahukaid tööfaile ei salvestata Git-repositooriumi ega Oracle’isse. Andmebaasis hoitakse ainult töö metaandmeid ja viiteid.
- Oracle’i järjekorra metaandmed ja rakenduste runtime-kataloogid peavad jääma eraldi vastutusega püsikihtideks.
- Kõik olulised ORDS-i, API ja skeemi versioonid peavad olema auditeeritavad.

## 9. Dokumentatsiooni ja tõeallikate register

### Projekti põhidokumendid

- [`AGENTS.md`](../AGENTS.md) — projekti siduvad tööreeglid.
- [`docs/lahteylesanne.md`](lahteylesanne.md) — probleem, eesmärk, ulatus ja vastuvõtukriteeriumid.
- [`docs/tehniline_spek_ords.md`](tehniline_spek_ords.md) — valitud Oracle’i ja ORDS-i põhine arhitektuur, olekumudel, andmemudel, API, etapistus ning tulevase wakeup-laienduse kontrollitud PoC.
- [`docs/api.md`](api.md) — lakooniline ORDS API kasutusjuhend liidestatavatele rakendustele ja workeritele.
- [`docs/ords_api_testitulemused.md`](ords_api_testitulemused.md) — 3. novembri 2026 ORDS API tegelike smoke-testide tulemused.
- [`.env.example`](.env.example) — ORDS-i ühenduse konfiguratsiooni mittesalajane näidis kõigi nõutud parameetritega.
- [`docker-compose.yml`](../docker-compose.yml) — haldusveebi FastAPI teenus ja selle ühendus olemasoleva `funo_net` Docker-võrguga.
- [`backend/app/main.py`](../backend/app/main.py) — Google’i sessiooni, haldus-API ja ORDS-i vahendav FastAPI backend.
- [`backend/frontend/`](../backend/frontend/) — haldusliidese staatilised failid, mida backend samast konteinerist serveerib.
- [`db/erd.md`](db/erd.md) — MVP1 Oracle'i füüsiline andmemudel, tabelite ja veergude kommentaarid ning terviklusreeglid.
- [`db/schema/001_core_schema.sql`](db/schema/001_core_schema.sql) — `JOBS_APP` skeemi tabelite, sequence'ite, piirangute, indeksite ja kommentaaride loomise skript.
- [`db/api/002_jobs_api_package.sql`](db/api/002_jobs_api_package.sql) — `JOBS_APP.PKG_JOBS_API` facade-pakett ja järjekorra äriloogika.
- [`db/security/003_grant_jobs_api.sql`](db/security/003_grant_jobs_api.sql) — facade-paketi `EXECUTE` õigus `JOBS_API` skeemile.
- [`db/ords/004_ords_handlers.sql`](db/ords/004_ords_handlers.sql) — `JOBS_API` skeemi ORDS endpoint’id.
- [`db/ords/005_oauth_authentication.sql`](db/ords/005_oauth_authentication.sql) — juba avaldatud `jobs.api` mooduli OAuth-kaitseks migreerimise skript.
- [`db/ords/006_create_oauth_client.sql`](db/ords/006_create_oauth_client.sql) — ühe rakenduse või haldusbackendi OAuth-kliendi loomise skript.
- [`docs/tehniline_spek.md`](tehniline_spek.md) — kõrvale heidetud Jenkinsi-põhine variant, mis säilib võrdlus- ja ajaloomaterjalina.

### Lähte- ja võrdlusmaterjalid

- `/home/ubuntu/fun_o/backend/app/main.py` — olemasoleva Google’i autentimise, sessiooni ning `ORDS_BASE_URL` + HTTP Basic ORDS-integratsiooni teostus; kasutada võrdlusmustrina, mitte pimesi kopeerida.
- `/home/ubuntu/fun_o/db/oracle/ords/07_ords_handlers.sql` ja `/home/ubuntu/fun_o/db/oracle/security/06_grants_runtime.sql` — olemasoleva ORDS API skeemi, handlerite ja piiratud paketiõiguste näide.
- `/home/ubuntu/fun_o/nginx/default.conf` ja `/home/ubuntu/fun_o/docker-compose.yml` — ühise nginx-serveri või Docker-võrguga liidestamise tegelik konfiguratsioon.
- `/home/ubuntu/projektid/err_video_to_text/frontend_dist/assets/app.css` — haldusliidese CSS-i värvide, tüpograafia ja põhiliste komponentide võrdlus- ning lähtemuster.

Registrit tuleb täiendada kohe, kui projektile lisandub README, lähtekood, andmeskeem, API leping, konteinerite kirjeldus või muu asjakohane allikas. Registrisse kuulumine ei anna allikale teiste ees ülimuslikkust.

## 10. Millal mida kindlasti lugeda

- Enne igat sisulist vastust loe vähemalt käesolev juhend ja ülesandega seotud põhidokumendi osad; koodi olemasolul kontrolli vastavat teostust.
- Kui muudad rakenduse eesmärki, ulatust, väljundeid või vastuvõtukriteeriume, loe `docs/lahteylesanne.md` ja `docs/tehniline_spek_ords.md`.
- Kui muudad arhitektuuri, andmemudelit, tööde järjekorda, konteinerite vastutusi või ressursikasutust, loe `docs/tehniline_spek_ords.md`, asjakohane konfiguratsioon ja kogu mõjutatud töötlusahel.
- Kui muudad avalikku hostinime, TLS-i, pöördproksit, veebiliidese serveerimist või ühise Docker-võrgu kasutust, loe enne `/home/ubuntu/fun_o/nginx/default.conf`, `/home/ubuntu/fun_o/docker-compose.yml` ja mõlema mõjutatud projekti juurutusdokumentatsioon.
- Google’i autentimise muutmisel kontrolli projekti teostust ja võrdluseks kasutatud `fun_o` tegelikku voogu.
- Oracle’i skeemi või ORDS-i muutmisel kontrolli migratsioone, Oracle’i versiooni, ORDS-i handler’eid ja õigusi; tegelikke saladusi ära loe.
- Kui hinnatakse uuesti kõrvale heidetud Jenkinsi varianti, kontrolli tegelikku Jenkinsi ja pluginate versiooni, ametlikku dokumentatsiooni ning integratsioonikatset.
- Tööadapteri lisamisel loe telliva rakenduse dokumentatsioon, käivitusahel, tööfailide elutsükkel ning puhastusloogika tervikuna.

## 11. Väljundi ootused

- Kui töö sisaldab vea parandust, too kokkuvõttes eraldi välja juurpõhjus ja paranduse loogika.
- Kui töö tugineb oletusele, nimeta oletus selgelt ning küsi enne muudatuse tegemist luba.
- Kui avastad allikate vahel lahknevuse, peata seda küsimust puudutav sisuline töö kohe, too vastuolu välja ja küsi enne jätkamist täiendavaid juhtnööre. Vastuolu ei tohi jätta ainult töö lõpu kokkuvõttesse.
