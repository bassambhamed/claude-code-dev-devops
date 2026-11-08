#!/usr/bin/env bash
# Fail closed for cluster commands outside the training context and namespaces.
set -euo pipefail
commande="$(jq -r '.tool_input.command // ""')"
python3 - "$commande" <<'PYTHON'
import re, shlex, subprocess, sys
command = sys.argv[1]
if not re.search(r"\b(kubectl|helm)\b", command):
    sys.exit(0)
def refuse(message):
    print("garde-kubectl : " + message, file=sys.stderr)
    sys.exit(2)
# A single direct command is reviewable. Shell composition is intentionally rejected.
if any(c in command for c in [';', '&', '|', '$', '`', '\n', '<', '>']):
    refuse("commande composée interdite ; exécutez une commande simple à la fois.")
try:
    args = shlex.split(command)
except ValueError:
    refuse("commande illisible.")
if not args or args[0] not in ('kubectl', 'helm'):
    refuse("appelez directement kubectl ou helm, sans enveloppe shell.")
for i, arg in enumerate(args):
    if arg.startswith(('--context', '--kube-context', '--kubeconfig', '--server', '--token', '--as', '--kube-apiserver', '--kube-token')) or arg in ('-s', '-A', '--all-namespaces'):
        refuse("surcharge de connexion, usurpation ou portée globale interdite.")
    if arg in ('-n', '--namespace'):
        if i + 1 == len(args) or args[i+1] not in ('ecommerce', 'ecommerce-helm'):
            refuse("namespace autorisé : ecommerce ou ecommerce-helm.")
    if arg.startswith('--namespace=') and arg.split('=',1)[1] not in ('ecommerce','ecommerce-helm'):
        refuse("namespace hors formation.")
    if arg.startswith('-n') and arg != '-n':
        refuse("utilisez -n ecommerce ou -n ecommerce-helm.")
if args[0] == 'kubectl':
    if len(args) < 2 or args[1] not in ('get','describe','logs','events','top','apply','rollout','scale','delete','port-forward','config'):
        refuse("verbe kubectl hors du périmètre de formation.")
    if args[1] == 'config' and args[2:] != ['current-context']:
        refuse("seule la lecture du contexte est autorisée.")
    if args[1] == 'delete' and (len(args) < 3 or args[2] not in ('pod','pods')):
        refuse("seule la suppression ciblée d'un pod est prévue.")
    if args[1] == 'delete' and any(a in ('--all', '-l', '--selector') or a.startswith('--selector=') for a in args):
        refuse("suppression collective interdite ; indiquez un nom de pod.")
    if args[1] == 'scale':
        for i, arg in enumerate(args):
            if arg == '--replicas=0' or (arg == '--replicas' and i + 1 < len(args) and args[i+1] == '0'):
                refuse("arrêt par scale interdit ; utilisez une procédure humaine.")
    if args[1] in ('get','describe') and any(a in ('-f','--filename','--raw') or a.startswith(('--filename=','--raw=')) for a in args):
        refuse("lecture indirecte interdite ; indiquez la ressource ciblée.")
    if args[1] in ('get','describe') and any(re.search(r'(^|[,/])(secrets?|namespaces?|ns)([,/]|$)',a) for a in args[2:]):
        refuse("lecture des secrets ou des namespaces hors périmètre.")
    if args[1] != 'config' and '-n' not in args and '--namespace' not in args and not any(a.startswith('--namespace=') for a in args):
        refuse("indiquez explicitement le namespace (-n ecommerce ou -n ecommerce-helm).")
else:
    if len(args)<2 or args[1] not in ('lint','template','list','status','history','upgrade','install','rollback'):
        refuse("verbe Helm hors du périmètre de formation.")
    if args[1] not in ('lint','template') and not any(a in ('-n','--namespace') or a.startswith('--namespace=') for a in args):
        refuse("indiquez explicitement le namespace Helm.")
try:
    current = subprocess.check_output(['kubectl','config','current-context'], text=True, stderr=subprocess.DEVNULL).strip()
except (OSError, subprocess.CalledProcessError):
    refuse("contexte Kubernetes illisible.")
if current != 'k3d-formation':
    refuse("contexte courant « " + current + " » ; contexte requis : k3d-formation.")
sys.exit(0)
PYTHON
