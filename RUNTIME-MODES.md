# Normal og Hardcore

Versjon 0.2.0 har et lagret rutevalg per karakter. Første oppstart bruker Hardcore. Knappen øverst til høyre viser gjeldende valg og bytter mellom Normal og Hardcore. `/octoguide normal` og `/octoguide hardcore` velger direkte. Addonen prøver ikke å gjette serverens karaktermodus.

Vanlige steg deler fremdrift mellom modusene. Steg som bare gjelder én modus, og alternative reiseruter, har egne fremdriftsnøkler. Ved bytte velges den første gjenværende handlingen i den valgte ruten. En snarvei som ble hoppet over i Normal, fullfører ikke den alternative gåturen i Hardcore.

Gamle fremdriftsnøkler for vanlige steg beholdes. Gamle nøkler for modusbetingede steg blir ikke automatisk overført. Dette unngår at en gammel skip-markering skjuler en ny reisehandling.

## Guidedata

En guide kan ha `modes={normal=true,hardcore=true}`. Utelatt modes betyr at felles innhold kan brukes i begge moduser. En guide eller et steg kan også begrenses med `mode='normal'`, `mode='hardcore'`, eller en modes-tabell.

En snarvei som krever dødsfall skal ha `requiresDeath=true`. `action='death'` er også alltid blokkert i Hardcore, uavhengig av feilaktige modes-verdier. Flagget skal også brukes dersom dødsfallet inngår i en handling som ellers heter travel/use.

Eksempel på et alternativ:

```lua
{id='return-normal', branch='return-town', mode='normal', requiresDeath=true,
 action='death', text='Bruk normalrutens døds-snarvei', zone=14,x=.45,y=.55},
{id='return-hardcore', branch='return-town', mode='hardcore',
 action='travel', text='Gå tilbake til byen', zone=14,x=.55,y=.65}
```

Begge steg må ha forskjellige, stabile id-er. `branch` grupperer alternativene; guidedataene må inneholde en faktisk alternativ reiserute. Et filter alene kan ikke lage en manglende reiserute.

`manual=true` gjør en delhandling manuell når et fullført helt oppdrag ikke er riktig mål for steget. Serverbekreftet tidligere innlevering av samme oppdrag lar fortsatt addonen hoppe over kjent gammelt oppdragsinnhold. `risk` og `requiresGroup` viser konkrete egenskaper i fullvisningen, men er ingen garanti for sikkerhet.

`action='level'` kan ha `xpFraction` fra 0 til under 1. Dette måles fra faktisk UnitXP/UnitXPMax når spillerens nivå er likt målnivået. Manglende eller ødelagt XP-API oppfyller ikke porten. Et beregnet forventet nivå i kildematerialet bør normalt være informasjon, ikke en slik port.

## Kontroller

`tests/test-modes.lua` kjører den tidligere runtime-testen med 28 kontroller, deretter 19 kontroller for modus, fremdrift, meny, feilmerking, waypoint, innstillinger, manuelle delmål og XP. Kjør med faktisk Lua 5.0 fra addonmappen. Resultatet ligger i `tests/mode-results.txt`.

Dette er automatisk verifisering med simulerte spillfunksjoner. Det er ikke bevis for at serverens oppdragshendelser eller en gjennomspilt rute er korrekt. Ingen spillfiler eller DLL-er ble endret som del av runtime-arbeidet.
