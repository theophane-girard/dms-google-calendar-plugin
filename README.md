# Google Calendar — plugin DankMaterialShell

Affiche ton prochain événement Google Calendar dans la barre, avec liste de
l'agenda du jour au survol. Authentification via navigateur web (flux OAuth
"loopback" comme `gcalcli` / `khal`).

## Setup (5 min, à faire une fois)

Comme tout client desktop qui parle à l'API Google, **tu dois créer ton propre
OAuth client** dans Google Cloud Console. Slack a son client OAuth Slack-owned ;
ici on n'a pas de backend, donc c'est le tien qui sert.

1. Va sur https://console.cloud.google.com/ et crée (ou réutilise) un projet.
2. **API & Services → Library** → cherche **Google Calendar API** → **Enable**.
3. **API & Services → OAuth consent screen** :
   - User type : **External**
   - App name : ce que tu veux (ex. `dms-calendar`)
   - User support email : ton email
   - Scopes : tu peux laisser vide (les scopes seront demandés au runtime)
   - Test users : **ajoute ton propre email Google** (sinon l'auth refuse tant
     que l'app n'est pas vérifiée)
4. **API & Services → Credentials → Create credentials → OAuth client ID** :
   - Application type : **Desktop app**
   - Name : `DMS Google Calendar`
   - Copie le **Client ID** et le **Client secret**.
5. Ouvre DMS → Settings → Plugins → Google Calendar → colle Client ID + Secret.
6. Clique **« Se connecter à Google »** → ton navigateur s'ouvre, tu acceptes,
   l'onglet affiche « Compte Google connecté ✓ », retour à DMS, terminé.

> ⚠️ Le client_secret OAuth d'une app "Desktop" n'est pas un vrai secret
> (Google le sait, c'est documenté). Il est stocké en clair dans
> `~/.config/DankMaterialShell/plugin_settings.json`. Ne le commit pas.

## Stockage

- Tokens (access + refresh) : `~/.local/state/DankMaterialShell/plugins/googleCalendar/tokens.json` (chmod 600)
- Events cache : `~/.local/state/DankMaterialShell/plugins/googleCalendar/events.json`

## Hotkeys / interactions

- **Clic gauche** sur le pill → ouvre calendar.google.com
- **Clic droit** sur le pill → refresh immédiat
- **Survol** → tooltip avec les 8 prochains événements

## Refresh

Toutes les `refreshMinutes` (5 par défaut), le widget lance
`python3 auth.py fetch` qui rafraîchit le token si besoin et réécrit
`events.json`. Le widget watche ce fichier et se met à jour tout seul.

## Hot reload après modif

```bash
dms ipc call plugins reload googleCalendar
```

Ou recharge DMS :

```bash
dms restart
```

## Dépannage

- **« Échec — vérifie client_id/secret »** → tu as oublié de coller un des deux
  champs, ou tu n'es pas ajouté en **Test user** dans l'OAuth consent screen.
- **`Access blocked: This app's request is invalid`** → tu as créé un client
  "Web application" au lieu de "Desktop app". Recrée-le.
- **Pas d'événement affiché alors que tu es connecté** → lance manuellement
  `python3 ~/.config/DankMaterialShell/plugins/googleCalendar/auth.py fetch`
  pour voir l'erreur.

## Fichiers du plugin

```
googleCalendar/
├── plugin.json
├── auth.py              # OAuth + fetch (stdlib uniquement)
├── GoogleCalendar.qml   # widget bar
├── Settings.qml         # page de réglages
└── README.md
```
