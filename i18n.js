.pragma library

// Internationalisation FR/EN du plugin Google Calendar.
// Usage côté QML :
//   import "i18n.js" as I18n
//   readonly property string locale: Qt.locale().name.startsWith("fr") ? "fr" : "en"
//   function tr(key, params) { return I18n.tr(locale, key, params) }

var DICT = {
    fr: {
        "google_calendar": "Google Calendar",
        "keyboard_hint": "h/l ◀▶  j/k ↕  ⏎ activer",
        "not_authenticated": "Compte non connecté.\nOuvre les réglages → Se connecter.",
        "nothing_scheduled": "Rien de prévu",
        "no_title": "(sans titre)",
        "today": "Aujourd'hui",
        "tomorrow": "Demain",
        "yesterday": "Hier",
        "all_day": "Toute la journée",
        "in_min": "dans {n} min",
        "now": "maintenant",
        "ago_min": "il y a {n} min",

        "toast_refresh": "Google Calendar : rafraîchissement…",
        "toast_fetch_fail": "Google Calendar : échec du fetch (code {code})",
        "toast_create_fail": "Google Calendar : échec de création (code {code})",
        "toast_event_created": "Événement créé ✓",
        "toast_account_added": "Compte ajouté",
        "toast_account_removed": "Compte retiré",
        "toast_calendars_refreshed": "Liste des calendriers rafraîchie",
        "toast_login_failed": "Échec de la connexion (code {code})",
        "toast_refresh_failed": "Échec du rafraîchissement (code {code})",
        "toast_title_required": "Titre requis",
        "toast_invalid_date": "Date invalide (AAAA-MM-JJ)",
        "toast_invalid_time": "Heures invalides (HH:MM)",

        "form_title_label": "Titre *",
        "form_title_placeholder": "Réunion équipe…",
        "form_date_label": "Date (AAAA-MM-JJ)",
        "form_date_placeholder": "2026-05-19",
        "form_all_day": "Toute la journée",
        "form_start_label": "Début (HH:MM)",
        "form_end_label": "Fin (HH:MM)",
        "form_location_label": "Lieu (optionnel)",
        "form_location_placeholder": "Salle de réunion, adresse…",
        "form_cancel": "Annuler",
        "form_create": "Créer",

        "details_meet": "Rejoindre Google Meet",
        "details_open_gcal": "Ouvrir dans Google Calendar",
        "details_attendees_one": "1 participant",
        "details_attendees_many": "{n} participants",

        "settings_subtitle": "Multi-compte. Connecte plusieurs comptes Google et active les calendriers de chacun individuellement.",
        "settings_accounts": "Comptes Google",
        "settings_account_count_one": "1 compte",
        "settings_account_count_many": "{n} comptes",
        "settings_no_accounts_help": "Aucun compte connecté. Renseigne d'abord client_id et secret OAuth ci-dessous, puis clique « + Connecter un compte ».",
        "settings_calendars": "Calendriers",
        "settings_remove": "Retirer",
        "settings_add_account": "+ Connecter un compte",
        "settings_add_account_busy": "En attente du navigateur…",
        "settings_refresh_calendars": "Rafraîchir les calendriers",
        "settings_oauth_section": "OAuth Client (Google Cloud)",
        "settings_oauth_help": "Un seul OAuth Client suffit pour plusieurs comptes Google. Crée un client « Desktop app » dans Google Cloud Console (voir README). Tous les comptes que tu ajoutes doivent figurer en « Test users » de cet écran de consentement.",
        "settings_clientid_label": "Client ID",
        "settings_clientsecret_label": "Client Secret",
        "settings_display": "Affichage",
        "settings_refresh_min_label": "Intervalle de rafraîchissement (min)",
        "settings_refresh_min_desc": "Toutes les N minutes, on re-requête l'API Google pour tous les calendriers activés",
        "settings_notif_section": "Notifications",
        "settings_notif_toggle": "Rappels d'événement",
        "settings_notif_desc": "Notifications 15 min, 5 min et à l'heure de chaque event, avec actions Snooze 5 min / Stop",
        "settings_primary": "(primary)"
    },
    en: {
        "google_calendar": "Google Calendar",
        "keyboard_hint": "h/l ◀▶  j/k ↕  ⏎ activate",
        "not_authenticated": "Account not connected.\nOpen settings → Sign in.",
        "nothing_scheduled": "Nothing scheduled",
        "no_title": "(untitled)",
        "today": "Today",
        "tomorrow": "Tomorrow",
        "yesterday": "Yesterday",
        "all_day": "All day",
        "in_min": "in {n} min",
        "now": "now",
        "ago_min": "{n} min ago",

        "toast_refresh": "Google Calendar: refreshing…",
        "toast_fetch_fail": "Google Calendar: fetch failed (code {code})",
        "toast_create_fail": "Google Calendar: create failed (code {code})",
        "toast_event_created": "Event created ✓",
        "toast_account_added": "Account added",
        "toast_account_removed": "Account removed",
        "toast_calendars_refreshed": "Calendar list refreshed",
        "toast_login_failed": "Sign-in failed (code {code})",
        "toast_refresh_failed": "Refresh failed (code {code})",
        "toast_title_required": "Title required",
        "toast_invalid_date": "Invalid date (YYYY-MM-DD)",
        "toast_invalid_time": "Invalid time (HH:MM)",

        "form_title_label": "Title *",
        "form_title_placeholder": "Team meeting…",
        "form_date_label": "Date (YYYY-MM-DD)",
        "form_date_placeholder": "2026-05-19",
        "form_all_day": "All day",
        "form_start_label": "Start (HH:MM)",
        "form_end_label": "End (HH:MM)",
        "form_location_label": "Location (optional)",
        "form_location_placeholder": "Meeting room, address…",
        "form_cancel": "Cancel",
        "form_create": "Create",

        "details_meet": "Join Google Meet",
        "details_open_gcal": "Open in Google Calendar",
        "details_attendees_one": "1 attendee",
        "details_attendees_many": "{n} attendees",

        "settings_subtitle": "Multi-account. Connect several Google accounts and toggle calendars individually.",
        "settings_accounts": "Google Accounts",
        "settings_account_count_one": "1 account",
        "settings_account_count_many": "{n} accounts",
        "settings_no_accounts_help": "No account connected. First set client_id and OAuth secret below, then click \"+ Connect account\".",
        "settings_calendars": "Calendars",
        "settings_remove": "Remove",
        "settings_add_account": "+ Connect account",
        "settings_add_account_busy": "Waiting for browser…",
        "settings_refresh_calendars": "Refresh calendars",
        "settings_oauth_section": "OAuth Client (Google Cloud)",
        "settings_oauth_help": "A single OAuth Client works for all your Google accounts. Create a \"Desktop app\" client in Google Cloud Console (see README). All accounts you add must be listed as \"Test users\" on the consent screen.",
        "settings_clientid_label": "Client ID",
        "settings_clientsecret_label": "Client Secret",
        "settings_display": "Display",
        "settings_refresh_min_label": "Refresh interval (min)",
        "settings_refresh_min_desc": "Every N minutes the plugin re-queries Google API for every enabled calendar",
        "settings_notif_section": "Notifications",
        "settings_notif_toggle": "Event reminders",
        "settings_notif_desc": "Notifications 15 min, 5 min and at start time of each event, with Snooze 5 min / Stop actions",
        "settings_primary": "(primary)"
    }
}

var DAYS = {
    fr: ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"],
    en: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
}

var MONTHS = {
    fr: ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."],
    en: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}

function tr(locale, key, params) {
    var s = (DICT[locale] && DICT[locale][key]) || DICT.en[key] || key
    if (params) {
        for (var k in params) s = s.split("{" + k + "}").join(params[k])
    }
    return s
}

function days(locale) { return DAYS[locale] || DAYS.en }
function months(locale) { return MONTHS[locale] || MONTHS.en }
