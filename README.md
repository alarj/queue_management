Ühes Oracle Cloudi Ubuntu serveris töötavad mitu sõltumatut rakendust. 
Rakendused võivad iseseisvalt käivitada pikki ning CPU-, mälu- või kettamahukaid taustaprotsesse. 
Kui mitu sellist protsessi käivituvad samal ajal, konkureerivad need serveri piiratud ressursside pärast ning võivad aeglustada või häirida nii üksteist kui ka serveri muid teenuseid.

Probleemi ei lahenda ainult ühe rakenduse sisemine järjekord. 
Järjekord peab olema rakendusteülene ja kõigile liidestatud rakendustele ühine.

Probleemi lahendamiseks sai loodud lihtne Oracle ORDS api, kuhu kõik rakendused saavad oma taustatööd registreerida ja mis siis lubab rakendustel neid õigel ajal käivitada. 
Haldusvahend annab ülevaate tööde hetkeseisust ja lubab veel alustamata tööde järjekorda muuta.

Esimene eelistus oli kasutada mõnda "karbitoodet" kuid plaanides selgus, et olemasoleva probleemi lahendab kõige lihtsamalt paarist andmebaasi tabelist ja lihtsast kasutajaliidesest koosnev kodukootud süsteem.
ORDS sai valitud seetõttu, et paistab rakendusele välja kui tavaline OAuth kaudu autenditav REST api, seda kunagi välja vahetades pole vaja eraldi andmebaasiühendusi jms muutma hakata. 
Haldusliidesele saab ligi end Google kaudu autentides.
