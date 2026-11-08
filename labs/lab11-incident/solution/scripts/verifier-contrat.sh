#!/usr/bin/env bash
# verifier-contrat.sh : le JSON réel de Catalog contient-il tous les champs que ses
# consommateurs lisent ?
#
# 1. Lit les champs attendus dans les copies du contrat : CatalogProduct (Ordering) et
#    ProductDto (Web), au commit courant.
# 2. Compile Catalog, le démarre seul contre un PostgreSQL jetable (Docker), puis lit
#    GET /api/products/1.
# 3. Compare : chaque champ attendu doit être présent dans la réponse.
#
# À lancer depuis la racine du dépôt. Utilisable tel quel par git bisect :
#   git bisect run bash scripts/verifier-contrat.sh
# Codes de retour : 0 contrat respecté, 1 contrat rompu, 125 Catalog ne compile pas
# (git bisect ignore le commit), 255 vérification impossible (Docker, démarrage) :
# git bisect s'arrête au lieu de conclure à tort.
set -uo pipefail

IMAGE_POSTGRES="${IMAGE_POSTGRES:-postgres:17}"
PREFIXE_CONTENEUR="${PREFIXE_CONTENEUR:-verifier-contrat}"
CATALOG="src/ECommerce.Catalog.Api"
CONSOMMATEURS=(
  "Ordering|src/ECommerce.Ordering.Api/Services/CatalogServiceClient.cs|CatalogProduct"
  "Web|src/ECommerce.Web/Services/CatalogApiClient.cs|ProductDto"
)

impossible() { echo "VÉRIFICATION IMPOSSIBLE : $*" >&2; exit 255; }

racine="$(git rev-parse --show-toplevel 2>/dev/null)" || impossible "lancez le script dans le dépôt."
cd "$racine" || impossible "dossier $racine inaccessible."
for outil in docker dotnet curl jq; do
  command -v "$outil" >/dev/null 2>&1 || impossible "outil manquant : $outil."
done

conteneur="$PREFIXE_CONTENEUR-$$"
journal="$(mktemp)"
pid_catalog=""
nettoyer() {
  [[ -n "$pid_catalog" ]] && kill "$pid_catalog" 2>/dev/null
  docker rm -f "$conteneur" >/dev/null 2>&1
  rm -f "$journal"
}
trap nettoyer EXIT

# --- 1. Ce que les consommateurs lisent ---------------------------------------------------
# « public record CatalogProduct(int Id, string Name, ..., decimal Price, ...) » donne
# id, name, ..., price : System.Text.Json lit le JSON en camelCase.
noms=()
attendus=()
for c in "${CONSOMMATEURS[@]}"; do
  IFS='|' read -r nom fichier type <<<"$c"
  [[ -f "$fichier" ]] || { echo "($nom : $fichier absent, consommateur ignoré)"; continue; }
  parametres="$(tr '\n' ' ' <"$fichier" | grep -o "record $type *([^)]*)" | head -n 1 | sed -E "s/^record $type *\(//; s/\)$//")"
  [[ -n "$parametres" ]] || { echo "($nom : record $type introuvable, consommateur ignoré)"; continue; }
  champs="$(tr ',' '\n' <<<"$parametres" | sed -E 's/\[[^]]*\]//g' \
    | awk 'NF { n = $NF; print tolower(substr(n, 1, 1)) substr(n, 2) }' | paste -sd ' ' -)"
  noms+=("$nom")
  attendus+=("$champs")
done
((${#noms[@]} > 0)) || impossible "aucune copie du contrat trouvée chez les consommateurs."

# --- 2. Le vrai Catalog, sur un PostgreSQL jetable ------------------------------------------
docker run -d --rm --name "$conteneur" -e POSTGRES_PASSWORD=contrat \
  -p 127.0.0.1::5432 "$IMAGE_POSTGRES" >/dev/null 2>&1 || impossible "PostgreSQL ne démarre pas (Docker tourne-t-il ?)."

if ! DOTNET_CLI_UI_LANGUAGE=en dotnet restore "$CATALOG" -nologo -v q >"$journal" 2>&1; then
  tail -n 15 "$journal" >&2
  impossible "restauration des paquets impossible ; ce n'est pas un verdict sur le commit."
fi
if ! DOTNET_CLI_UI_LANGUAGE=en dotnet build "$CATALOG" --no-restore -nologo -v q >"$journal" 2>&1; then
  echo "Catalog ne compile pas à ce commit : à ignorer (125)."
  exit 125
fi

for _ in $(seq 1 30); do
  docker exec "$conteneur" pg_isready -U postgres >/dev/null 2>&1 && break
  sleep 1
done
docker exec "$conteneur" pg_isready -U postgres >/dev/null 2>&1 || impossible "PostgreSQL n'est pas prêt après 30 s."
port_pg="$(docker port "$conteneur" 5432/tcp | head -n 1 | sed -E 's/.*://')"

port=""
for _ in $(seq 1 20); do
  candidat=$((20000 + RANDOM % 20000))
  if ! (exec 3<>"/dev/tcp/127.0.0.1/$candidat") 2>/dev/null; then port="$candidat"; break; fi
done
[[ -n "$port" ]] || impossible "aucun port libre trouvé."

ConnectionStrings__catalogdb="Host=127.0.0.1;Port=$port_pg;Username=postgres;Password=contrat;Database=catalogdb" \
  ASPNETCORE_URLS="http://127.0.0.1:$port" \
  dotnet "$CATALOG/bin/Debug/net10.0/ECommerce.Catalog.Api.dll" --contentRoot "$racine/$CATALOG" >"$journal" 2>&1 &
pid_catalog=$!

reponse=""
for _ in $(seq 1 60); do
  if reponse="$(curl -s -f --max-time 5 "http://127.0.0.1:$port/api/products/1")"; then break; fi
  reponse=""
  kill -0 "$pid_catalog" 2>/dev/null || break
  sleep 1
done
if [[ -z "$reponse" ]]; then
  tail -n 15 "$journal" >&2
  impossible "Catalog ne répond pas sur GET /api/products/1."
fi

# --- 3. Comparaison ----------------------------------------------------------------------
recus="$(jq -r 'keys_unsorted | join(" ")' <<<"$reponse")"
echo "Catalog renvoie : $recus"
rompu=0
for i in "${!noms[@]}"; do
  nom="${noms[$i]}"
  manquants=""
  for champ in ${attendus[$i]}; do
    jq -e --arg c "$champ" 'has($c)' <<<"$reponse" >/dev/null || manquants+=" $champ"
  done
  if [[ -n "$manquants" ]]; then
    echo "CONTRAT ROMPU pour $nom : champ(s) attendu(s) absent(s) :$manquants"
    rompu=1
  else
    echo "Contrat respecté pour $nom (${attendus[$i]})"
  fi
done
exit "$rompu"
