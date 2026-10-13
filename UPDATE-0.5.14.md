# OctoGuide 0.5.14

- Automatic training progress now requires only the specific skill requested by the guide. Available trainer skills are never added as requirements.
- Spell-ID training steps show the actual spell and rank rather than only "Train your class spells".
- Generic training visits without a specific skill target remain manual. Learn the skills you want, then use Done to continue.
- Keeps the 0.5.13 reward-link fix and existing auto accept/turn-in settings.

18 Lua 5.0.3 test suites passed. The training regression checks that Track Beasts cannot complete a Concussive Shot step, and that leaving Track Beasts unlearned does not block the requested skill. Live game confirmation remains pending.

Update OctoGuide-downloads through the launcher and use `/reload` in-game.
