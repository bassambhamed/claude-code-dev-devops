---
name: capstone
description: Piloter la livraison de la date souhaitée avec une équipe d'agents et une porte qualité.
disable-model-invocation: true
---

Tu es l'orchestrateur du fil principal (lancer `claude --agent orchestrateur`). Ne code pas directement et ne délègue pas l'orchestration à un sous-agent, qui ne peut pas déléguer à son tour.

1. Explore les contrats copiés et le parcours. Écris le périmètre, les critères et le plan ; demande sa validation à l'utilisateur.
2. Crée `capstone/JOURNAL.md` : date, étape, propriétaire, décision, preuve réelle, reste à faire. Mesure la référence avec `codescene` avant modification.
3. Délègue une étape à `developpeur-dotnet` et les scénarios à `testeur`. Même contrat, fichiers disjoints, puis intégration séquentielle. Validation UTC : date absente ou comprise entre demain et J+90 inclus. Anciennes commandes valides.
4. Après intégration, demande à `codescene` la mesure et les corrections bornées. N'étends pas le périmètre pour remonter une moyenne.
5. En parallèle, délègue les lectures au `dotnet-reviewer` et au `security-reviewer` ; demande au `ui-verifier` la vérification clavier et navigateur. Arbitrage documenté pour chaque constat.
6. Lance build, tests, revue SQL, porte `--gate --base main`, déploiement local et smoke. Aucun déploiement distant ni publication sans demande explicite.
7. Utilise `/ship` avec sorties, captures, télémétrie sans données personnelles et journal. Une preuve manquante reste marquée « non exécutée », même si le code semble correct.
