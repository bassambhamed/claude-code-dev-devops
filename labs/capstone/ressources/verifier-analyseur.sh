#!/usr/bin/env bash
# Exercise the real file-based analyzer in a disposable Git repository.
# The first dotnet invocation may restore the pinned Roslyn NuGet package.
set -euo pipefail
formation="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
analyseur="${1:-$formation/labs/capstone/.claude/skills/code-health/codehealth.cs}"
[[ -f "$analyseur" ]] || { echo "Analyseur introuvable : $analyseur" >&2; exit 2; }
analyseur="$(cd "$(dirname "$analyseur")" && pwd)/$(basename "$analyseur")"
for outil in git dotnet jq; do
  command -v "$outil" >/dev/null || { echo "Outil absent : $outil" >&2; exit 2; }
done
dossier="$(mktemp -d "${TMPDIR:-/tmp}/verification-codehealth.XXXXXX")"
trap 'rm -rf "$dossier"' EXIT
cd "$dossier"
mkdir src
git init -q -b main
git config user.name 'Code Health fixtures'
git config user.email 'codehealth@example.invalid'
printf 'public sealed class Clean { public int Value() => 1; }\n' > src/Clean.cs
cp src/Clean.cs clean-original.txt
git add src
git commit -qm baseline
nombre=0
cas() {
  local nom="$1" attendu="$2" code=0
  shift 2
  dotnet run "$analyseur" -- src --format json "$@" > rapport.json 2> erreur.txt || code=$?
  if [[ "$code" != "$attendu" ]]; then
    echo "ÉCHEC $nom : code $code, attendu $attendu" >&2
    cat erreur.txt >&2
    cat rapport.json >&2
    exit 1
  fi
  nombre=$((nombre + 1))
  printf 'OK %s (code %s)\n' "$nom" "$code"
}
verifier() {
  jq -e "$1" rapport.json >/dev/null || { echo "Assertion JSON échouée : $1" >&2; cat rapport.json >&2; exit 1; }
}
cas analyse-propre 0
verifier '.score == 10 and .files[0].lines == 1 and (.files[0].findings | length) == 0'
cas porte-propre 0 --gate --base main
verifier '.gate and (.failures | length) == 0'
printf 'using System; public sealed class Clean { public DateTime Value() => DateTime.Now; }\n' > src/Clean.cs
cas regression-mineure 1 --gate --base main
verifier '.files[0].score == 9.75 and (.files[0].findings | any(.rule == "NET09" and .severity == "minor"))'
cp clean-original.txt src/Clean.cs
printf 'using System; public sealed class New { public DateTime Value() => DateTime.Now; }\n' > src/New.cs
cas nouveau-superieur-neuf 0 --gate --base main
rm src/New.cs
cat > src/New.cs <<'CS'
public sealed class New
{
    public void Work()
    {
        System.Threading.Thread.Sleep(1);
        System.Threading.Thread.Sleep(2);
    }
}
CS
cas nouveau-inferieur-neuf 1 --gate --base main
verifier '(.files[] | select(.path == "src/New.cs") | .score == 8.5) and (.failures | any(contains("new file below 9")))'
rm src/New.cs
printf 'public sealed class New { public async void Work() { await System.Threading.Tasks.Task.CompletedTask; } }\n' > src/New.cs
cas bloquant 1 --gate --base main
verifier '(.files[] | select(.path == "src/New.cs") | .findings | any(.rule == "NET01" and .severity == "blocking"))'
rm src/New.cs
cas base-absente 2 --gate --base reference-inexistante
printf 'public class Invalid {\n' > src/Invalid.cs
cas syntaxe-invalide 2
rm src/Invalid.cs
mkdir src/Migrations
printf 'not valid C#\n' > src/Migrations/Generated.cs
printf 'not valid C#\n' > src/Generated.g.cs
cas sources-generees-exclues 0 --gate --base main
verifier '(.files | length) == 1'
rm src/Migrations/Generated.cs src/Generated.g.cs
rmdir src/Migrations
cat > src/Résumé.cs <<'CS'
public sealed class Resume
{
    public void Work()
    {
        System.Threading.Thread.Sleep(1);
        System.Threading.Thread.Sleep(2);
    }
}
CS
git add src/Résumé.cs
git commit -qm 'baseline with accented path and accepted pre-existing debt'
cas nom-accentue-base 0 --gate --base main
verifier '(.files[] | select(.path == "src/Résumé.cs") | .score == 8.5)'
rm src/Résumé.cs
cat > src/Lambdas.cs <<'CS'
public sealed class Lambdas
{
    public void Work(bool a)
    {
        if (a)
        {
            System.Action first = () => { if (a) System.Console.WriteLine(1); };
        }
        if (a)
        {
            System.Action second = () => { if (a) System.Console.WriteLine(2); };
        }
    }
}
CS
cas lambdas-mesurees-separement 0
verifier '(.files[] | select(.path == "src/Lambdas.cs") | .findings | all(.rule != "CH04"))'
rm src/Lambdas.cs
# The empty line must not make overlapping normalized windows count twice.
for nom in First Second; do
cat > "src/$nom.cs" <<CS
public sealed class $nom
{
    public void Work()
    {
        System.Console.WriteLine("alpha");

        System.Console.WriteLine("bravo");

        System.Console.WriteLine("charlie");

        System.Console.WriteLine("delta");

        System.Console.WriteLine("echo");

        System.Console.WriteLine("foxtrot");

        System.Console.WriteLine("golf");

        System.Console.WriteLine("hotel");
    }
}
CS
done
cas duplication-sans-chevauchement 0
verifier '[.files[] | .findings[] | select(.rule == "CH10")] | length == 4'
echo "ANALYSEUR OK : $nombre cas réels ; codes 0/1/2, scores, exclusions, noms accentués, lambdas et duplication."
