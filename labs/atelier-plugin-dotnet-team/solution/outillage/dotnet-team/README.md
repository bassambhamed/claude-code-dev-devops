# dotnet-team 1.0.0

Plugin Claude Code pour les dépôts ECommerce .NET 10. Il ajoute les skills `/dotnet-team:smoke-test`, `/dotnet-team:ship`, `/dotnet-team:test-integration`, `/dotnet-team:review-migration`, `/dotnet-team:verifier-ui`, la commande `/dotnet-team:revue-diff`, trois agents et les hooks Git, format, tests et secrets.

Depuis la racine d’une copie de l’application :

```bash
claude --plugin-dir /chemin/absolu/outillage/dotnet-team
```

Ou en CLI, après validation :

```bash
claude plugin validate /chemin/absolu/outillage/dotnet-team
claude plugin validate /chemin/absolu/outillage
claude plugin marketplace add /chemin/absolu/outillage
claude plugin install dotnet-team@formation-dotnet
```

Relancez Claude. Vérifiez `/help`, `/agents`, `/hooks` et `/plugin`. Les permissions spécifiques, `CLAUDE.md` et `.mcp.json` restent dans le dépôt. Les scripts des skills utilisent `${CLAUDE_SKILL_DIR}` ; les hooks utilisent `${CLAUDE_PLUGIN_ROOT}` et travaillent dans `${CLAUDE_PROJECT_DIR}`. Ne déplacez pas les composants dans `.claude-plugin/`.

Testez dans une copie sans hooks ni skills locaux : les hooks locaux et ceux du plugin s’exécuteraient sinon deux fois. Le lab principal conserve son dispositif local pour permettre les labs suivants ; n’y activez pas ce plugin en parallèle. La copie de test garde seulement les permissions et les variables d’environnement du projet dans `.claude/settings.json`.

Dépendances : Git, .NET, jq ; gh pour ship, Docker et dotnet-ef pour PostgreSQL, MCP Playwright pour la recette UI. Le hook Stop peut être désactivé pour une phase rouge avec `CLAUDE_SKIP_STOP_TESTS=1` ; ce choix n’ouvre pas la gate CI.

## Évolution

Modifiez le plugin source, ajoutez une entrée au changelog, incrémentez la version, validez puis distribuez. Les utilisateurs mettent à jour la marketplace puis le plugin avec les commandes affichées par `claude plugin --help`. Les fichiers du cache installé ne sont pas la source de vérité.

## Changelog

- 1.0.0 : extraction des composants des labs 0 à 5, sans secrets ni permissions propres à un poste.
