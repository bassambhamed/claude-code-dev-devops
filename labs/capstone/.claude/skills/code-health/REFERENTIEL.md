# Référentiel pédagogique Code Health

Ce référentiel local est inspiré des concepts de santé du code présentés dans les slides. Il n'est ni l'analyseur ni la note commerciale de CodeScene. Les mesures proviennent de l'arbre syntaxique Roslyn, sans compilation sémantique. Les seuils sont inclusifs. Un constat par règle et ligne ; chaque constat mineur coûte 0,25, majeur 0,75, bloquant 2. Score fichier = max(1, 10 − pénalités). Moyenne pondérée par lignes de code.

| Id | Mesure | Mineur | Majeur | Bloquant |
|---|---|---:|---:|---:|
| CH01 | Complexité : 1 + branches, boucles, catch, ternaires, cases, &&, \|\|, ?? | 9 | 15 | 25 |
| CH02 | Lignes contenant des tokens dans un callable | 50 | 80 | 150 |
| CH03 | Profondeur de contrôles (if, boucles, switch, try) | — | 4 | 5 |
| CH04 | Groupes de contrôles indépendants contenant un contrôle imbriqué | — | 2 | 4 |
| CH05 | && / \|\| dans une condition | 2 | 4 | — |
| CH06 | Paramètres du callable | 5 | 7 | — |
| CH07 | Paramètres du constructeur, y compris primaire | 5 | 8 | — |
| CH08 | CH02 ≥ 60, CH01 ≥ 15 et CH03 ≥ 4 | — | — | oui |
| CH09 | Lignes du fichier contenant des tokens | 600 | 1000 | — |
| CH10 | Six lignes de code normalisées répétées (≥ 60 caractères alphanumériques) | — | oui | — |
| CH11 | Callables dans un fichier, lambdas et accesseurs inclus | 40 | — | — |
| CH12 | Responsabilités mélangées, revue humaine | — | oui | — |
| CH13 | ≥ 4 paramètres, tous de type prédéfini C# | oui | — | — |

| Id | Forme repérée | Gravité |
|---|---|---|
| NET01 | méthode async void | bloquant |
| NET02 | accès .Result, .Wait, .GetResult | bloquant |
| NET03 | new HttpClient | bloquant |
| NET04 | catch sans instruction | bloquant |
| NET05 | throw d'un identifiant | majeur |
| NET06 | Thread.Sleep | majeur |
| NET07 | FromSqlRaw avec chaîne interpolée comme premier argument | bloquant |
| NET08 | chaîne littérale avec clé ecpk ou Password= | bloquant |
| NET09 | DateTime.Now | mineur |
| NET10 | argument interpolé d'un appel Log… | mineur |
| NET11 | catch (Exception) sans throw dans son bloc | majeur |
| NET12 | ToList().Where() | majeur |

## Porte et limites

- Code 0 : analyse réussie / porte franchie ; 1 : porte fermée ; 2 : usage, Git, source invalide ou outil indisponible. Le hook transforme toute erreur en blocage.
- Avec `--gate --base main`, tous les fichiers C# du périmètre sont comparés au commit de référence : aucun bloquant, aucun score existant en baisse, nouveaux fichiers ≥ 9. Fichiers non suivis inclus ; suppressions à relire humainement ; renommages traités comme nouveaux fichiers.
- Les migrations EF, `bin`, `obj`, `.g.cs` et `.Designer.cs` sont exclus : générés, ils ne doivent pas être refactorés à la main. Ils restent soumis aux tests, à la revue SQL et sécurité.
- Les lambdas sont mesurées séparément ; un if/else-if compte comme une imbrication syntaxique. Les commentaires ne sont pas du code. Les lignes de chaînes multilignes ne sont pas toutes comptabilisées.
- CH10 compare les tokens de six lignes non vides, sans analyse des intentions ; faux positifs possibles sur du code déclaratif. NET02 peut repérer une propriété `Result` sans attente, NET03 ne voit pas `new()` typé implicitement ; alias et appels indirects peuvent échapper aux règles. NET08 ne couvre pas tous les formats de secrets.
- CH12 n'entre pas dans la note automatique. Consigner séparément son jugement et les faux positifs argumentés. Une revue humaine ne change pas silencieusement le code de retour : corriger, ou soumettre un changement explicite et revu du référentiel.
- Le JSON, YAML et Razor ne sont pas analysés. Gitleaks, les tests, la compilation, la revue UI et les contrôles CI restent nécessaires.

Référence technique : [applications C# à fichier unique, Microsoft](https://learn.microsoft.com/en-us/dotnet/core/sdk/file-based-apps). Le package Roslyn est épinglé dans `codehealth.cs` ; son premier lancement restaure NuGet.
