---
name: diagnostic-traces
description: Diagnostiquer une latence ECommerce avec mesures comparables, traces Aspire/Grafana et code, puis vérifier un correctif.
argument-hint: "[symptôme ou période UTC]"
allowed-tools: Read, Grep, Glob, Bash, Agent
---
# Diagnostic fondé sur les traces

Demande : $ARGUMENTS

1. Lire CLAUDE.md, la configuration d'export et les ressources en cours. Ne pas lancer
   une deuxième application sur les mêmes ports ; ne jamais afficher l'environnement complet.
2. Depuis la racine de la copie, lancer `bash .claude/skills/diagnostic-traces/mesurer.sh 5`.
   Garder heures UTC, nombre de lignes et médianes dans preuves/lab10. Le script crée
   des commandes de formation ; l'annoncer et garder le même jeu de données après correction.
3. Consulter les ressources et traces avec MCP Aspire ; avec Grafana, choisir Tempo et
   la même période. Demander à `observabilite-analyste` de lire les résultats volumineux.
4. Fournir un trace ID réel, les spans parent/enfant, service, route et durée. Ne pas
   inventer un identifiant ou conclure à une cause sur une seule corrélation.
5. Relier le span lent à un fichier et une ligne. Distinguer durée propre et durée
   d'un enfant : additionner tous les spans compterait deux fois le temps d'attente.
6. Proposer un correctif ciblé, préserver validations/contrats. Après accord dans le
   périmètre demandé, appliquer, construire et redémarrer l'AppHost pour reconstruire.
7. Refaire exactement la mesure et les tests. Présenter avant/après, limites et
   hypothèses restantes. Si un MCP est absent, fournir les étapes manuelles dans Explore
   et signaler la vérification manquante. Aucun chiffre de performance sans mesure.

Ne pas modifier les dashboards ni exécuter de commande de ressource via MCP pendant
une lecture de diagnostic. Les comptes Grafana restent Viewer ; ne jamais lire le jeton.
