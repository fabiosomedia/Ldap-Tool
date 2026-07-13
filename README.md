# AD Console

A web-based Active Directory management tool built by **Somedia IT**.  
Manage users, computers, groups, and passwords directly in your browser — no additional software required.

---

## 🇩🇪 Einrichtung (Deutsch)

### Voraussetzungen
- Windows-Server oder Windows-PC (64-bit)
- Netzwerkzugriff auf euren Active Directory Server (LDAP, Port 636 mit SSL empfohlen)
- Ein AD-Service-Account mit Leserechten (für die Suche) und Schreibrechten (für Änderungen)

### Installation

**1. Repository klonen**
```
git clone https://github.com/fabiosomedia/Ldap-Tool.git
cd Ldap-Tool
```

**2. Dart SDK installieren**  
→ https://dart.dev/get-dart  
Danach prüfen ob es funktioniert:
```
dart --version
```

**3. Abhängigkeiten installieren**
```
dart pub get
```

**4. Konfigurationsdatei erstellen**  
Die Datei `bin/env.example` als `bin/.env` kopieren und mit euren AD-Daten ausfüllen:
```
copy bin\env.example bin\.env
```

Inhalt der `.env`:
```
AD_SERVER=192.168.1.10          # IP oder Hostname eures AD-Servers
AD_PORT=636                     # 636 = SSL (empfohlen), 389 = ohne SSL
AD_SSL=true
AD_USER=CN=svc_ldap,OU=...      # DN des Service-Accounts
AD_PASSWORD=...                 # Passwort des Service-Accounts
BASE_DN=DC=example,DC=com       # Basis-DN eurer Domain

ADMIN_OU=                       # Name der OU, deren Mitglieder sich anmelden dürfen
                                # Leer lassen = alle AD-User dürfen sich anmelden

LAGER_OU=                       # Vollständiger DN der Ziel-OU für deaktivierte Geräte
                                # Leer lassen = Schnell-Aktion wird nicht angezeigt

COMPUTER_PREFIX=nb,mb           # CN-Präfixe für Computer-Objekte (kommagetrennt)
                                # Leer lassen = Schnell-Aktion wird nie angezeigt
```

**5. Anwendung kompilieren**
```
dart compile exe bin/ldap_tool.dart -o bin/ldap_tool.exe
```

**6. Starten**
```
bin\ldap_tool.exe
```
Die Anwendung läuft danach unter `http://localhost:5000`.  
Für Netzwerkzugriff (andere Geräte im selben Netz) ist der Server bereits auf `0.0.0.0:5000` konfiguriert — stellt sicher, dass Port 5000 in der Windows-Firewall freigegeben ist.

### Anmelden
Meldet euch mit einem AD-Account an, der sich in der konfigurierten `ADMIN_OU` befindet (oder mit einem beliebigen AD-Account, wenn `ADMIN_OU` leer ist).

---

## 🇬🇧 Setup (English)

### Requirements
- Windows server or Windows PC (64-bit)
- Network access to your Active Directory server (LDAP, port 636 with SSL recommended)
- An AD service account with read permissions (for search) and write permissions (for changes)

### Installation

**1. Clone the repository**
```
git clone https://github.com/fabiosomedia/Ldap-Tool.git
cd Ldap-Tool
```

**2. Install the Dart SDK**  
→ https://dart.dev/get-dart  
Verify the installation:
```
dart --version
```

**3. Install dependencies**
```
dart pub get
```

**4. Create the configuration file**  
Copy `bin/env.example` to `bin/.env` and fill in your AD details:
```
copy bin\env.example bin\.env
```

Contents of `.env`:
```
AD_SERVER=192.168.1.10          # IP or hostname of your AD server
AD_PORT=636                     # 636 = SSL (recommended), 389 = without SSL
AD_SSL=true
AD_USER=CN=svc_ldap,OU=...      # DN of the service account
AD_PASSWORD=...                 # Password of the service account
BASE_DN=DC=example,DC=com       # Base DN of your domain

ADMIN_OU=                       # Name of the OU whose members are allowed to log in
                                # Leave empty = all AD users can log in

LAGER_OU=                       # Full DN of the target OU for deactivated devices
                                # Leave empty = quick action will not be shown

COMPUTER_PREFIX=nb,mb           # CN prefixes for computer objects (comma-separated)
                                # Leave empty = quick action is never shown
```

**5. Compile the application**
```
dart compile exe bin/ldap_tool.dart -o bin/ldap_tool.exe
```

**6. Start**
```
bin\ldap_tool.exe
```
The application will then be available at `http://localhost:5000`.  
For network access (other devices on the same network) the server is already configured to listen on `0.0.0.0:5000` — make sure port 5000 is allowed in the Windows Firewall.

### Login
Log in with an AD account that is a member of the configured `ADMIN_OU` (or any AD account if `ADMIN_OU` is left empty).

---

## Features

- User search by name, username or email
- View and edit all AD attributes inline
- Profile photo: view, upload, delete
- Group management: add, remove, copy between users
- Password reset
- Enable / disable / unlock accounts
- Computer browser with quick-move to storage OU
- CSV export
- Audit log of all changes
- Dark mode

---

*Built by [Somedia IT](https://www.somedia.ch)*
