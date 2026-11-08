---
name: code-health
description: Mesurer les sources C# et examiner la santé du code avant livraison.
disable-model-invocation: true
argument-hint: "[src]"
---

1. Lire `REFERENTIEL.md` à côté de ce skill. Ce référentiel pédagogique ne produit pas un score CodeScene officiel.
2. Depuis la copie, lancer `dotnet run .claude/skills/code-health/codehealth.cs -- src --format md --sortie preuves/capstone/code-health.md`.
3. Examiner manuellement CH12, Razor, configuration, secrets, types ambigus et suppressions. Les constats syntaxiques sont des indices expliqués avec fichier et ligne.
4. Pour corriger, demander au sous-agent `codescene` un changement à la fois, puis build et tests. Ne jamais modifier le référentiel pour obtenir un score.
5. Lancer la porte : `dotnet run .claude/skills/code-health/codehealth.cs -- src --gate --base main`. Un défaut bloquant ou une régression ferme la porte même si la moyenne monte.
6. Restituer scores avant/après, constats retenus/écartés avec preuve, sortie réelle et limites. Pas de résultats d'outils inventés.
