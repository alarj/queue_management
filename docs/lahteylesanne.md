# Lähteülesanne: serveriülene taustatööde järjekord

## 1. Dokumendi päritolu

Koostaja: AI (OpenAI Codex) kasutajaga 1.–2.11.2026 peetud arhitektuuriarutelude põhjal. Dokument koondab kokkulepitud probleemi, ulatuse, kasutusjuhud ja arhitektuuriotsused. Valitud tehniline lahendus on kirjeldatud failis [`tehniline_spek_ords.md`](tehniline_spek_ords.md).

Esialgne Jenkinsi-põhine variant on säilitatud failis [`tehniline_spek.md`](tehniline_spek.md), kuid see on käesoleva lähteülesande jaoks kõrvale heidetud. Jenkins võib olla tulevikus eraldi CI/CD teema, kuid seda ei lisata praeguse tööjärjekorra lahendusse.

## 2. Sisukord

- [3. Probleem](#3-probleem)
- [4. Arhitektuuriotsus ja eesmärk](#4-arhitektuuriotsus-ja-eesmärk)
- [5. Põhimõisted](#5-põhimõisted)
- [6. Kasutajad ja autentimine](#6-kasutajad-ja-autentimine)
- [7. Põhikasutusjuht](#7-põhikasutusjuht)
- [8. Järjekorra haldamine](#8-järjekorra-haldamine)
- [9. Töö katkestamine](#9-töö-katkestamine)
- [10. Kasutajaliides](#10-kasutajaliides)
- [11. Rakenduste liidestamine](#11-rakenduste-liidestamine)
- [12. Andmete hoidmine](#12-andmete-hoidmine)
- [13. Mittefunktsionaalsed nõuded](#13-mittefunktsionaalsed-nõuded)
- [14. Ulatusest välja jääv](#14-ulatusest-välja-jääv)
- [15. Vastuvõtukriteeriumid](#15-vastuvõtukriteeriumid)
- [16. Avatud küsimused](#16-avatud-küsimused)
- [17. Kõrvale heidetud ja tulevased variandid](#17-kõrvale-heidetud-ja-tulevased-variandid)

## 3. Probleem

Ühes Oracle Cloudi Ubuntu serveris töötavad mitu rakendust, näiteks `ttu_loeng` ja ERR-i töötlusrakendus. Rakendused võivad iseseisvalt käivitada pikki ning CPU-, mälu- või kettamahukaid taustaprotsesse. Kui mitu sellist protsessi käivituvad samal ajal, konkureerivad need serveri piiratud ressursside pärast ning võivad aeglustada või häirida nii üksteist kui ka serveri muid teenuseid.

Probleemi ei lahenda ainult ühe rakenduse sisemine järjekord. Järjekord peab olema rakendusteülene ja kõigile liidestatud rakendustele ühine.

## 4. Arhitektuuriotsus ja eesmärk

Luua Oracle’i ja ORDS-i põhine rakendusteülene tööjärjekord koos minimalistliku haldusrakendusega. Oracle on järjekorra, täitmiskoha ja töö oleku autoriteetne tõeallikas. ORDS on rakenduste, workerite ja Oracle’i vaheline HTTPS-liides. Pikad protsessid käivitab iga liidestatud rakenduse enda worker registreeritud tööadapteri kaudu.

ORDS-i kasutamise peamised põhjused on:

- liidestatud rakendus ei vaja Oracle’i otseühendust, Walletit, andmebaasidraiverit ega ühenduste pooli;
- järjekorra tabelid, lukustamine, claim’i loogika ja sisemine struktuur jäävad rakenduse eest peitu;
- rakendus sõltub versioonitud HTTP- ja JSON-lepingust, mitte Oracle’i skeemist;
- sisemist teostust saab muuta rakendust muutmata, kui API leping säilib; teenuse asukoha muutumisel piisab üldjuhul URL-i konfiguratsiooni muutmisest;
- lahendus järgib olemasolevas `fun_o` projektis kasutatud FastAPI → ORDS → PL/SQL-pakettide eraldusmustrit.

Lahendus peab:

1. võtma eri rakendustelt vastu taustatöid;
2. lisama tavapärase töö vaikimisi ühise järjekorra lõppu;
3. tagama, et korraga töötab ainult kokkulepitud arv raskeid töid, esialgu üks;
4. näitama järjekorda ühest veebiliidesest;
5. võimaldama ootel töid ümber järjestada, ootele panna ja eemaldada;
6. võimaldama taastada ohutu oleku pärast workeri, Ubuntu serveri, ORDS-i või Oracle’i katkestust;
7. kasutama olemasolevat Oracle’i andmebaasi, mitte lisama uut andmebaasitehnoloogiat;
8. vältima Jenkinsi, eraldi brokeri või muu uue järjekorrateenuse lisamist.

## 5. Põhimõisted

- **Töö** — ühe rakenduse tellitud taustaprotsess koos tüübi ja parameetritega.
- **Tavatöö** — töö, mis lisatakse ilma erikorralduseta järjekorra lõppu. See on süsteemi kõige tavalisem kasutusjuht.
- **Järgmine töö** — ootel töö, mis tõstetakse järjekorra esimeseks ja käivitub pärast parajasti töötava töö lõppu.
- **Hold** — töö eemaldatakse Oracle’i aktiivsest käivitatavast järjekorrast, kuid säilitatakse hilisemaks taastamiseks.
- **Eemaldamine** — veel käivitumata töö kustutatakse järjekorrast lõplikult.
- **Worker** — rakenduse juurde kuuluv kerge taustakomponent, mis küsib ORDS-ist oma rakendusele sobivat tööd, käivitab adapteri ning teatab töö olekust.
- **Claim** — Oracle’i atomaarne toiming, millega üks worker reserveerib järjekorra esimese sobiva töö ja globaalse täitmiskoha.
- **Täitmise token** — ühe täitmiskatse unikaalne tunnus, mis peab kaasas olema käivitamise, heartbeat’i ja lõpetamise teadetes.
- **Heartbeat** — töötava workeri perioodiline teade, et konkreetne täitmiskatse on endiselt jälgimisel.
- **Tööadapter** — rakenduse- ja töötüübipõhine leping, mis määrab lubatud parameetrid, käivitamise, oleku, väljundid ja logiviite.

## 6. Kasutajad ja autentimine

### 6.1. Haldusliidese kasutajad

- Kasutajaliides nõuab Google’iga autentimist.
- Oma kasutajanime ja parooli süsteemi ei tehta.
- Lubatud Google’i e-posti aadresse võib olla üks või mitu.
- Lubatud aadresside loend asub esialgu serveri `.env`-failis.
- Kõigil lubatud kasutajatel on samad õigused; rolle ega õigustasemeid ei ole.
- Järjekorratoimingu tegemisel ei nõuta kasutajalt põhjendust.

### 6.2. Rakendused ja workerid

- Rakendused ja workerid kasutavad ORDS-i kutsumiseks ühist HTTP Basic autentimise kasutajat, samal põhimõttel nagu `fun_o` projektis.
- ORDS-i baas-URL, kasutajanimi ja parool tulevad `.env`-ist või muust saladuste hoidlast.
- OAuth 2.0 `client_credentials` voogu ei kasutata.
- Rakendus saadab igas asjakohases päringus oma registreeritud `application_code` tunnuse.
- `application_code` on kliendi deklareeritud tunnus, mitte autentimisega tõendatud identiteet. Teadlikult aktsepteeritakse riski, et üks sama ORDS-i mandaati omav rakendus võib esineda teise rakendusena.
- Oracle kontrollib siiski, et `application_code` on registreeritud ja aktiivne ning esitatud `job_type` on sellele rakendusele lubatud.

## 7. Põhikasutusjuht

1. Liidestatud rakendus saadab uue töö kesksele API-le.
2. Kui rakendus ei anna eraldi järjekorrakorraldust, käsitletakse tööd tavatööna.
3. ORDS-i taga olev Oracle’i pakett valideerib rakenduse tunnuse, töötüübi, parameetrid ja idempotentsusvõtme ning lisab tavatöö ühise järjekorra lõppu.
4. Kui mõni teine raske töö juba töötab, jääb uus töö ootama.
5. Iga rakenduse worker pollib ORDS-i kokkulepitud intervalliga ja teeb ühe atomaarse claim-päringu.
6. Oracle annab töö ainult siis, kui muud aktiivset rasket tööd ei ole ja järjekorra esimene käivitatav töö kuulub küsiva workeri deklareeritud rakendusele.
7. Worker käivitab registreeritud adapteri, kinnitab käivitumise, saadab töö ajal heartbeat’i ning teatab lõpptulemuse.
8. Telliv rakendus saab keskse töö identifikaatori ning võib selle abil keskset olekut pärida.

## 8. Järjekorra haldamine

Autenditud kasutaja peab saama:

- näha töötavat tööd ja kõiki ootel töid nende tegelikus järjekorras;
- tõsta ootel töö ühe koha võrra üles või alla;
- tõsta ootel töö järjekorra lõppu;
- tõsta ootel töö esimeseks ehk määrata see järgmisena käivituvaks;
- panna ootel töö `hold`-olekusse;
- taastada `hold`-olekus töö järjekorra lõppu;
- eemaldada ootel või `hold`-olekus töö lõplikult.

Eraldi mitmetasemelist prioriteedisüsteemi ei ole esimeses versioonis vaja. Prioriteet väljendub töö tegelikus asukohas järjekorras. Juba töötavat tööd järjekorra muutmine ei katkesta.

## 9. Töö katkestamine

Töötava `CLAIMED` või `RUNNING` töö kasutaja algatatud katkestamine ei kuulu MVP1 ulatusse. Haldur ei paku selleks API-t ega kasutajaliidese nuppu.

See ei välista tõrkejärgset taastamist. Ubuntu restardi või muu tõendatud ootamatu lõppemise korral viiakse töö tehnilise taastamisreegli järgi aktiivsest olekust välja ainult siis, kui vana protsessi puudumine on tõendatud. Ootel või `hold`-olekus töö eemaldamine ei ole töötava protsessi katkestamine.

## 10. Kasutajaliides

Haldusrakenduse kasutajaliides on teadlikult minimalistlik ega kuva Oracle’i või ORDS-i tehnilist haldusliidest.

Kasutajaliidese kinnitatud avalik aadress on `https://haldus.fun-o.eu`.

Esimese versiooni põhivaated:

- Google’i sisselogimine;
- järjekord koos töötava ja ootel töödega;
- `hold`-olekus tööd;
- töö detail koos oleku, päritolurakenduse ja ajatemplitega.

Põhitoimingud peavad olema järjekorravaates otse kättesaadavad. Kasutajaliides peab küsima kinnitust pöördumatule eemaldamisele, kuid ei küsi põhjendust.

## 11. Rakenduste liidestamine

- Rakendused esitavad töid ja workerid suhtlevad järjekorraga ORDS-i HTTPS API kaudu.
- ORDS-i URL ei ole avalikust internetist kättesaadav; ligipääsu piirab Oracle Cloudi taseme võrgu-ACL.
- ORDS on rakenduse jaoks ainus andmebaasiliides. Rakendus ei loo selle projekti jaoks Oracle’i otseühendust.
- Iga toetatud töötüüp on Oracle’is eelnevalt registreeritud. Klient ei saa saata suvalist shellikäsku.
- Päring sisaldab kliendi deklareeritud `application_code` väärtust; selle teadlik turvarisk on kirjeldatud jaotises 6.2.
- Töö parameetrid valideeritakse Oracle’i paketis töötüübi lepingu järgi.
- Töö esitamisel saadab rakendus kohustusliku `application_job_id` väärtuse, mis seob keskse töö rakenduse enda protsessi või tegevusega; see ei ole kohaliku järjekorra tunnus.
- Töö esitamine sisaldab idempotentsusvõtit, et võrgutõrke või `429` vastuse järel sama päringu kordamine ei looks duplikaati.
- Telliv rakendus saab vähemalt keskse töö ID ja oleku.
- Iga rakendus otsustab ise, millised oma protsessid ta ühisesse järjekorda saadab. Keskne haldur ei lahenda rakenduse sisemist töövoogu.

## 12. Andmete hoidmine

Lahendus kasutab olemasolevat Oracle Autonomous Database’i ning kahte eraldi skeemi. `JOBS_APP` omab tabeleid ja järjekorra PL/SQL-loogikat. ORDS-is base path’iga `jobs` avaldatud `JOBS_API` omab REST-handler’eid ning saab `JOBS_APP` skeemis ainult kokkulepitud facade-paketi `EXECUTE` õiguse. `JOBS_API` ei saa otseõigusi `JOBS_APP` tabelitele. Tootmislahendus ei tööta `ADMIN` kasutajana.

Oracle’is hoitakse haldusrakenduse metaolekut, sealhulgas:

- keskne töö ID ja päritolurakendus;
- töötüüp ja valideeritud parameetrid;
- töö olek, järjekorra järjestus ja UTC ajatemplid;
- `hold`-olekus tööd;
- täitmiskatsed, täitmise token, `host_id`, `boot_id` ja heartbeat’i metaandmed;
- korraga ühe aktiivse raske töö piirang;
- järjekorratoimingute sündmused ilma kohustusliku põhjenduseta.

Rakenduste mahukad tööfailid, ajutised failid, täielikud protsessilogid ja väljundid jäävad vastavate rakenduste runtime-kataloogidesse. Oracle’is hoitakse ainult keskse järjekorra ja täitmiskatsete metaandmeid.

## 13. Mittefunktsionaalsed nõuded

- Lahendus peab töötama olemasoleval ARM64 Ubuntu serveril konteinerites.
- Kasutatakse tasuta ja avatud lähtekoodiga komponente; tasuline teenus ei tohi olla töö eeltingimus.
- Esialgne raske tööde paralleelsus on üks.
- Järjekorra tõeallikas peab olema üheselt määratud ja pärast taaskäivitust taastatav.
- Töö esitamine peab olema korduskindel, et võrgukatse kordamine ei looks tahtmatult duplikaattööd.
- Ajad salvestatakse UTC-s ja kuvatakse kasutaja lokaalses ajavööndis.
- Saladusi, Google’i lubatud aadresse, ORDS-i kasutajanime ega parooli ega küpsiste signeerimisvõtmeid ei salvestata Git-i või logidesse.
- `.env.example` võib sisaldada ainult muutuja nimesid ja mittesalajasi näidisväärtusi.
- Taaskäivitus ei tohi muuta `hold`-olekus tööd automaatselt käivitatavaks.
- Kasutajaliides ei tohi lubada toimingut, mida backend ei suuda ohutult lõpuni viia.
- Jõude worker küsib MVP1-s uut tööd seadistatava 5-minutilise intervalliga; intervalli ei seata lühemaks kui üks minut.
- Töötav worker saadab MVP1-s heartbeat’i seadistatava 5-minutilise intervalliga.
- Töötav worker ei polli uut tööd, vaid saadab ainult oma aktiivse töö heartbeat’i ja lõppoleku teateid.
- ORDS-i `429 Too Many Requests`, ajutise 5xx vastuse või võrguvea järel korratakse päringut kasvava ooteajaga ja väikese juhusliku hajutusega. Kui vastus sisaldab `Retry-After` päist, eelistatakse seda.
- Muutva päringu kordus kasutab sama idempotentsusvõtit, claim’i kordus sama claim’i tunnust ja olekuteade sama täitmise tokenit.
- Heartbeat’i aegumine üksi ei tõenda protsessi lõppu ega vii tööd aktiivsest olekust välja.
- Avalik aadress on `https://haldus.fun-o.eu`.
- Nginx avaldab ainult brauserile vajalikud autentimis- ja haldusliidese endpoint’id. ORDS-i rakenduste ja workerite API-d ei vahendata `haldus.fun-o.eu` kaudu.

## 14. Ulatusest välja jääv

Esimesse versiooni ei kuulu:

- üldotstarbeline CI/CD haldusliides;
- oma kasutajanime ja parooli süsteem;
- kasutajarollid ja mitmetasemelised õigused;
- tasuline järjekorra- või autentimisteenus;
- uus PostgreSQL-i, MySQL-i, SQLite’i või Redise instants;
- suvaliste shellikäskude sisestamine veebiliidesest;
- töötava töö peatamine ja hilisem jätkamine protsessi samast kohast;
- töötava töö kasutaja algatatud katkestamine;
- mahukate tööartefaktide hoidmine Oracle’is;
- rakenduste tööde esitamise API avaldamine internetti või `haldus.fun-o.eu` domeeni kaudu;
- Oracle’i algatatud wakeup-teavitus, wakeup-endpoint’id ja wakeup outbox;
- Jenkins või muu eraldi järjekorra- või brokeriteenus.

## 15. Vastuvõtukriteeriumid

Esimene versioon loetakse vastuvõetuks, kui:

1. vähemalt kaks näidisrakendust saavad Oracle Cloudi võrgu-ACL-iga piiratud ORDS API kaudu tavatöö esitada;
2. tavatöö lisatakse vaikimisi järjekorra lõppu;
3. kaks rasket tööd ei tööta korraga;
4. Google’iga saab sisse logida ainult `.env`-is lubatud aadressiga;
5. kõik lubatud kasutajad näevad sama järjekorda ja saavad teha samu toiminguid;
6. järjekorras olevat tööd saab liigutada üles, alla, lõppu ja esimeseks;
7. ootel töö saab panna `hold`-olekusse ja hiljem järjekorra lõppu taastada;
8. ootel või `hold`-olekus töö saab lõplikult eemaldada;
9. järjekorra ja `hold`-tööde olek taastub teenuste taaskäivituse järel;
10. töö detailist on näha päritolurakendus, töötüüp, olek ja ajad;
11. iga rakenduse jõude worker pollib ORDS-i seadistatava 5-minutilise intervalliga ning claim on atomaarne ja korduskindel;
12. töötav worker saadab heartbeat’i ega polli samal ajal uut tööd;
13. Ubuntu restardi järel tõendab muutunud `boot_id`, et vana protsess ei tööta, vana täitmiskatse lõpetatakse ja globaalne koht vabastatakse;
14. heartbeat’i aegumine või ebaselge sama buudi olukord ei käivita teist rasket tööd;
15. `429` või ajutise võrgutõrke järel kordab klient päringut kasvava ooteajaga ega loo duplikaattööd või uut täitmiskatset;
16. rakendus ei saa saata suvalist käivitatavat käsku;
17. ORDS-i Basic-autentimine töötab ühise mandaadiga ning Oracle valideerib kliendi saadetud `application_code` ja selle lubatud töötüübi;
18. ORDS-i rakenduste ja workerite API ei ole avalikust internetist ega `haldus.fun-o.eu` kaudu kättesaadav;
19. saladusi ega lubatud Google’i e-posti aadresse ei leidu repositooriumi jälgitavates failides.

## 16. Avatud küsimused

Enne esimese töötava versiooni teostamist tuleb kinnitada:

1. pollingu ja heartbeat’i 5-minutilise intervalli juhusliku hajutuse piir;
2. heartbeat’i aegumise piir, mis ei vii tööd automaatselt aktiivsest olekust välja;
3. `CLAIMED` oleku taastamisreegel olukorras, kus protsessi käivitamise kinnitus kaob;
4. `INTERRUPTED` töö korduskäivituse poliitika;
5. `UNKNOWN` olekust kontrollitud väljumise ja operaatori sekkumise kord;
6. kas töötüübipõhine maksimaalne tavapärane kestus on ainult hoiatus või mõjutab olekut;
7. logide, sündmuste ja lõpetatud tööde säilitamise kestus.

## 17. Kõrvale heidetud ja tulevased variandid

### 17.1. Jenkinsi-põhine variant

Jenkinsi-põhine lahendus on käesoleva projekti jaoks kõrvale heidetud kui ebavajalikult raskekaaluline. Jenkins lisaks eraldi teenuse, püsikihi, pluginate halduse ja Oracle’iga kooskõlastatava tehnilise oleku. Võimalik tulevane CI/CD vajadus ei õigusta Jenkinsi lisamist praeguse serveriülese tööjärjekorra lahendusse.

Kõrvale heidetud variant säilib võrdlus- ja ajaloomaterjalina failis [`tehniline_spek.md`](tehniline_spek.md).

### 17.2. Oracle’i algatatud wakeup

MVP1 kasutab workeri perioodilist polling’ut. Oracle’i `DBMS_SCHEDULER`-i ja `UTL_HTTP`-i põhine wakeup jääb tulevase MVPx laiendusvõimalusena tehnilisse spetsifikatsiooni. Tehtud tehnilise PoC tulemused säilitatakse, kuid MVP1 skeem, API ja vastuvõtukriteeriumid ei sõltu wakeup’ist.
