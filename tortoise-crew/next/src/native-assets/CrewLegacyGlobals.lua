-- Tortoise Crew compatibility for the Vanilla 1.12 glue environment.
-- Turtle patch-9 RealmList.xml uses _G; older clients may not expose it.
if not _G then _G = getfenv(0) end
