# CI ProVDesk — Windows x64

[English](README.en.md)

Compilation complète du client Windows depuis **le commit du checkout Bitbucket**,
avec signature par le **framework WanPulse**. Le pipeline manuel
`provdesk-build-sign-package` compile, signe et publie le seul EXE final signé
sur le partage produit. Aucun push ne lance automatiquement ce pipeline.
Les sources et la CI sont versionnées ensemble. Le pipeline compile directement
dans le checkout Bitbucket. `Prepare-Source` initialise ses sous-modules et
enregistre le commit ; il refuse les modifications non commitées et les sorties
d'un ancien build avant l'application des patches de compilation. Le build modifie
ce checkout jetable : chaque exécution doit partir d'un checkout propre.
La variable `GITHUB_REVISION` ne doit pas être définie.
Le périmètre de livraison est le client x64 et son EXE autoextractible, pas les
MSI/templates, ARM64, Sciter ou autres plateformes du workflow multiplateforme.

## Configuration du build

La configuration et les patches sont versionnés avec les sources du produit.

| Élément | Adaptation de cette CI |
| --- | --- |
| Script ProVDesk | Branding, patch hbb_common, WebSocket forcé et notices conservés |
| Features Windows du workflow | `flutter,hwcodec,vram` via patch explicite du script |
| Rust | 1.91.1, version indiquée par PROVDESK.md |
| Flutter | 3.24.5, commit figé ; patch dropdown du fork et moteur x64 RustDesk vérifié par SHA256 |
| Bridge | Régénération par le script ProVDesk avec codegen 1.80.1, sans réutiliser l'artefact GitHub généré sous un autre SDK |
| vcpkg | Baseline du manifeste, overlays du fork, triplet x64-windows-static et installation explicite |
| Utilitaire | Compilation de WindowInjection.dll au commit ecd8d6a139eee76845ea66423fb739af450fda90, licence incluse |
| Affichage / impression | Ajout des paquets du workflow, sans suppression silencieuse en cas d'échec |
| Wrapper | Adaptation DPI identique au workflow ; branding du build.rs ProVDesk conservé |
| Updater / désinstallation | Implémentés dans le client (`src/updater.rs`, argument `--uninstall` dans `src/core_main.rs`) ; pas d'EXE autonome construit par ce workflow. Les EXE/DLL supplémentaires présents sont inventoriés récursivement |

Les adaptations sont conservées dans `patches/` et archivées avec les artefacts.
Une adaptation supplémentaire protège le test Git « patch déjà appliqué » des
particularités stderr de Windows PowerShell 5.1. Aucun code métier Rust/Dart n'est
modifié par ces patches CI. Pour intégrer une évolution amont, revoir les patches
et `dependencies.json` ; leur applicabilité est vérifiée avant la compilation.

## Build Tools 2026 (18.x)

Aucune installation de Visual Studio 2022 n'est nécessaire. `MSBUILD_PATH` doit
pointer vers le MSBuild de l'instance **18.x**, par exemple :
`C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\MSBuild.exe`.
Le précontrôle vérifie les fichiers des compilateurs **v143 et v142**, les headers
et bibliothèques x64, ainsi que **CMake 4.2+** et son générateur VS2026. Les fichiers
du compilateur ne suffisent pas : chaque toolset doit aussi disposer de ses fichiers
MSBuild x64 `Toolset.props` / `Toolset.targets` et des imports C++ communs. La CI
cherche dans `MSBuild/Microsoft/VC/v180`, puis `v170`, puis `v160`, **dans l'instance
VS2026 sélectionnée**, séparément pour v143 et v142. Elle retient la première
intégration complète. Si l'intégration v143 est absente mais le compilateur installé,
`Test-Runner` restaure quatre paquets Microsoft officiels MSBuild v170 (17.14.36109.1,
moins de 1 Mo compressés), verrouillés par URL et SHA256 dans `msbuild-tools.json`,
sous `work/msbuild-integration/<hash du verrou>`. Seul l'arbre d'intégration est extrait ;
son inventaire SHA256 est vérifié à chaque réutilisation. v142 utilise son intégration
installée. Aucun fichier n'est copié dans Visual Studio ; aucune autre installation VS
ni aucun compilateur n'est ajouté. CMake reçoit explicitement le chemin réel de VS2026
pour que les imports privés retrouvent les compilateurs existants.

La CI initialise VsDevCmd avec la version exacte de v143 sélectionnée ; Rust et
vcpkg utilisent cette instance et ce compilateur. Un triplet overlay conserve le
CRT statique et impose v143 à vcpkg. WindowInjection reçoit explicitement v142
et sa version via MSBuild, même si l'environnement principal utilise v143. CMake
reçoit `VCTargetsPath=<chemin validé>` dans `-T` ; WindowInjection reçoit le
`/p:VCTargetsPath=...` correspondant. Cela évite MSB8020 lorsque `v180` ne contient
pas l'intégration v143/v142 mais qu'elle existe dans un ancien répertoire de schéma
de la même installation.

L'overlay libvpx appelle MSBuild directement, sans passer par les options CMake.
`patches/libvpx-msbuild.patch` transmet à cet appel le `VCTargetsPath` validé,
le véritable `VSInstallDir` et la version exacte `VCToolsVersion`.
Un fichier séparé `build-tools/msbuild-selection.cmake` conserve le triplet commun
inchangé : ce correctif n'invalide donc pas les caches des autres bibliothèques natives.
Avant les longues compilations des dépendances, `Test-Toolchain` compile et exécute
aussi un programme par appel direct à MSBuild avec les mêmes options que libvpx,
en complément des deux essais CMake. Le fichier de sélection et le patch sont
inclus dans les diagnostics.

Le port Opus 1.5.2 impose par défaut un CRT dynamique malgré le triplet statique.
`patches/opus-static-runtime.patch` active explicitement `OPUS_STATIC_RUNTIME`.
Après installation vcpkg, `dumpbin /directives` doit retrouver `LIBCMT` en Release
et `LIBCMTD` en Debug, sans CRT dynamique ; sinon le build s'arrête avant le client.
Ce correctif invalide uniquement le cache Opus, sans modifier le triplet commun.

La génération du pont transmet aussi le chemin complet de `libclang.dll` à
`flutter_rust_bridge_codegen --llvm-path` : ffigen ne lit pas `LIBCLANG_PATH` et
ne recherche pas automatiquement le répertoire LLVM de Build Tools 2026.
La variable reste configurée sur Windows ; le pipeline la réutilise explicitement.

Tous les scripts CI sont non interactifs : ils ne demandent jamais d'élévation UAC.
Les privilèges nécessaires doivent être disponibles dans le jeton du service runner
avant son démarrage. Un prérequis manquant provoque un échec explicite du précontrôle.

Le patch `patches/flutter-vs2026.patch` adapte uniquement le SDK Flutter privé :
sélection de la même instance, générateur VS2026, toolset v143 et CMake contrôlé.
Il est appliqué **avant le premier appel Flutter**, pour que le snapshot de l'outil
contienne le correctif. Le patch, le triplet et la configuration retenue sont archivés.
Les variables internes `PROVDESK_VS_ROOT`, `PROVDESK_MSVC_VERSION` et
`PROVDESK_CMAKE_PATH`, `PROVDESK_CMAKE_TOOLSET` et `PROVDESK_VS_GLOBALS` sont calculées ; ne pas les renseigner
dans Bitbucket. `PROVDESK_CMAKE_TOOLSET` contient la sélection complète du toolset CMake v143.

## Liste des dépendances à vérifier sur le runner

À vérifier **sous le compte Windows qui exécute le service runner**, pas seulement
sous un compte administrateur interactif.

### À installer/configurer sur Windows

| Dépendance | Exigence |
| --- | --- |
| Runner Bitbucket | Windows x64, accessible à ce dépôt, labels `self.hosted`, `windows`, `capability.build`, `capability.sign` |
| Windows PowerShell | **5.1 x64**, `powershell.exe` ; aucune installation système de PowerShell 7 requise ; copie interne vcpkg ci-dessous |
| Politique PowerShell | Doit autoriser les scripts locaux de la CI, par exemple `RemoteSigned` selon votre politique ; la CI ne modifie pas la stratégie machine |
| Git for Windows | 2.35+ recommandé, dans PATH ; HTTPS et sous-modules accessibles |
| Rustup | Installé pour le compte du runner, shims `rustup` et `cargo` dans PATH ; la CI installe Rust 1.91.1 |
| Python x64 | 3.15.x requis (x64) ; modules standard `venv`, `ssl`, pip/ensurepip disponibles, commande `python` fonctionnelle, pas seulement l'alias Microsoft Store |
| Visual Studio Build Tools 2026 | Charge de travail C++ desktop, MSBuild, **MSVC v143 x64/x86** pour Flutter/client |
| Outils MSVC supplémentaires | **v142 x64/x86** : requis par le projet WindowInjection x64 figé |
| Windows SDK | SDK Windows 10/11 compatible avec VS2026 : headers, bibliothèques x64, compilateur de ressources `rc.exe`, `mt.exe`, outils de signature dont `signtool.exe` |
| CMake | **4.2 minimum**, générateur `Visual Studio 18 2026` présent. Détection dans Build Tools 2026 puis dans PATH ; la CI ne remplace pas le CMake système ; vcpkg peut télécharger sa propre version |
| LLVM x64 | `libclang.dll` et ses dépendances ; `LIBCLANG_PATH` vers son dossier. Workflow : 15.0.6 ; guide local : 22.1.8. Choisir et valider une version, conserver son inventaire |
| Framework WanPulse | Exécutable, fournisseur cryptographique, middleware/token éventuel et accès effectif à la clé par le compte du runner |
| Confiance Windows | Chaînes de certificats et accès aux services de révocation/horodatage ; SignTool SDK sert uniquement à vérifier, jamais à signer |
| Liens symboliques de dossiers | Le compte de build doit pouvoir créer les liens des plugins Flutter : processus élevé disposant de ce privilège, ou mode développeur Windows. `Test-Toolchain` teste une création réelle avant les compilations des dépendances ; la CI ne modifie pas les paramètres de sécurité Windows |

Un SDK .NET seul ne remplace pas les outils C++. Ni WDK ni WiX/NuGet MSI ne sont
requis par cette livraison EXE. Le runner dispose de 8 vCPU et 8 Gio de RAM,
avec un seul pipeline actif et le fichier d'échange Windows automatique. L'ordre
des étapes et la concurrence des pipelines restent inchangés (délai : 240 minutes).

Le parallélisme interne utilise les mécanismes natifs, sans plafond numérique
imposé par les scripts et sans écraser les variables fournies par l'opérateur :

| Outil | Mode automatique | Limite volontaire |
|---|---|---|
| Cargo | Nombre de processeurs logiques, sous réserve de sa configuration native | `CARGO_BUILD_JOBS` ou configuration Cargo `build.jobs` |
| vcpkg | Concurrence choisie par vcpkg pour ses systèmes de build (processeurs logiques + 1 selon sa documentation) | `VCPKG_MAX_CONCURRENCY` |
| Flutter / CMake Visual Studio | `--parallel` sans nombre, donc choix natif du générateur | `CMAKE_BUILD_PARALLEL_LEVEL`, entier positif |
| MSBuild direct (WindowInjection et probes) | `/m` sans nombre | `CMAKE_BUILD_PARALLEL_LEVEL`, transmis explicitement à `/m:N` et `MultiProcMaxCount=N` |

Le choix de reprendre `CMAKE_BUILD_PARALLEL_LEVEL` pour MSBuild direct est une
convention de ces scripts, pas une variable native MSBuild. Flutter laisse CMake
lire cette variable lorsqu'elle est définie et transmet la même limite au scheduler
C++. Variable absente ou vide : aucun nombre calculé ou fixe n'est injecté.
Cargo et vcpkg gardent leurs limites indépendantes : cette variable CMake ne les
plafonne pas. Les réglages MSVC fournis volontairement, dont `CL_MPCount`, ne sont
ni supprimés ni réécrits ; une limite CMake explicite est prioritaire pour le
`MultiProcMaxCount` des appels MSBuild que nous contrôlons.

MSBuild active `UseMultiToolTask=true` et `EnforceProcessCountAcrossBuilds=true` pour
coordonner les compilateurs C++ entre projets plutôt que multiplier `/m` par `/MP`.
Sans limite explicite, MSVC choisit sa concurrence ; cette coordination ne plafonne
ni Cargo ni tous les outils annexes. Le helper vcpkg conserve ses options natives
`/m:${VCPKG_CONCURRENCY}`, `-maxCpuCount:${VCPKG_CONCURRENCY}` et
`MultiProcMaxCount=${VCPKG_CONCURRENCY}` : elles sont dynamiques, pas fixées à 2.
Le `DISABLE_PARALLEL_CONFIGURE` du port libyuv est conservé : il sérialise ses
configurations CMake Debug/Release, pas les jobs de compilation.

L'automatisme dépend surtout des CPU, pas de la mémoire disponible. Sur le runner
de 8 Gio, les compilations Release/LTO simultanées peuvent saturer la RAM, paginer
ou échouer ; un seul pipeline simultané n'empêche pas cela. Aucun plafond mémoire
adaptatif n'est ajouté. En cas de pression mémoire, l'opérateur peut fixer les
variables ci-dessus. Les profils Rust Release, LTO et codegen-units sont inchangés.
Le contrôle d'espace disque n'est pas un contrôle mémoire.

`Set-FlutterVs2026Patch` applique le patch maintenu et peut mettre à jour un SDK
local déjà patché à partir de son reçu. Il refuse les changements non reconnus,
restaure l'ancien patch si le nouveau est inapplicable et invalide uniquement le
snapshot/stamp de flutter_tools devenu obsolète. La prochaine invocation Flutter
autorisée le reconstruira ; la synchronisation seule ne lance aucune compilation.

Les tests sans compilation couvrent le mode automatique, les limites explicites,
leur préservation et les mises à jour du patch. Le parallélisme automatique a été validé le 10 novembre 2026 par le build local
propre décrit ci-dessous ; sa consommation mémoire sur le runner de 8 Gio reste à mesurer.

`MIN_FREE_DISK_GB` est une variable Bitbucket facultative : entier positif, **10 Gio**
par défaut. Le contrôle vérifie les volumes locaux du checkout, de TEMP, du profil
et des caches Cargo/Rustup/LocalAppData avant chaque script, avant les grosses
installations et avant l'archive finale. Les chemins doivent utiliser une lettre
de lecteur locale (pas de partage UNC ni de redirection vers un autre volume).
Sous le seuil, le pipeline s'arrête sans supprimer de fichiers. Ce sont des contrôles
ponctuels, pas une réservation d'espace ni une garantie de place pour le build complet.
Avec 36,3 Go libres au départ, la consommation du premier build doit être observée.

### Préparées automatiquement par la CI

| Dépendance | Version / emplacement |
| --- | --- |
| Complément d'intégration MSBuild v143 | Paquets Microsoft v170 base, ressources anglaises, plateforme x64 et enregistrement v143 x64, tous en 17.14.36109.1, uniquement si absents de VS2026 ; `work/msbuild-integration`, SHA256 figés dans `msbuild-tools.json` |
| Flutter + Dart | Flutter 3.24.5 / Dart associé 3.5.4 dans `build-tools/flutter`, moteur et patch appliqués uniquement à cette copie |
| Rust | Toolchain 1.91.1 + rustfmt + cible x86_64-pc-windows-msvc dans le rustup du compte ; aucun changement de toolchain par défaut |
| cargo-expand | 1.0.95, cache local versionné, puis copie contrôlée dans `build-tools/rust` |
| flutter_rust_bridge_codegen | 1.80.1, feature uuid, cache local versionné, puis copie contrôlée dans `build-tools/rust` |
| Brotli Python | 1.2.1 (wheel uniquement) dans le venv `build-tools/python` |
| vcpkg | Commit 9e593bb18ea69cc5095e012465dcd675a822ed0d dans `build-tools/vcpkg`, aucun changement d'installation partagée |
| Outils internes vcpkg | Téléchargements observés : CMake **4.4.0**, PowerShell Core **7.6.3**, Python embarqué **3.14.2**, 7-Zip **26.02**, NASM **3.01**, Meson **1.9.0** et Strawberry Perl **5.42.2.1** ; outils conservés sous `build-tools/vcpkg/downloads/tools`, sans remplacer les installations système |
| Bibliothèques natives | Manifeste complet du fork : aom, libjpeg-turbo, opus, libvpx, libyuv, mfx-dispatch, FFmpeg et leurs dépendances ; overlays inclus, contraintes ffnvcodec 12.1.14.0 et amd-amf 1.4.35 |
| Dépendances Cargo/Dart | Cargo.lock et flutter/pubspec.lock du fork ; résolutions réellement utilisées archivées |
| Moteur et pilotes | Les quatre archives sont verrouillées par SHA256 dans `dependencies.json` |
| WindowInjection | Sources au commit figé, compilation locale en Release/x64/v142 |

vcpkg gère ses outils internes selon ses métadonnées et les ports : CMake,
PowerShell Core, Ninja, NASM, outils MSYS et autres selon les dépendances.
Les versions ci-dessus ont été observées dans les logs de build ; elles ne sont
pas à installer manuellement. Le Python interne sert à vcpkg/Meson ; le packaging
applicatif utilise toujours Python 3.15 et Brotli 1.2.1. Les scripts CI restent sous
Windows PowerShell 5.1. `vcpkg-packages.txt` inventorie les paquets installés,
pas l'ensemble des exécutables auxiliaires téléchargés. Les versions des
bibliothèques suivent le baseline et les overlays ; le premier build complet
reste à valider. `cpu-features` Android et `libsodium` Windows ARM64, présents
dans le manifeste multiplateforme, ne sont pas requis par cette cible x64.

### Variables et réseau

Variables requises : `WP_SIGNTOOL_PATH`, `SIGNING_CONTAINER`, `SIGNING_PASSWORD`,
`SIGNING_THUMBPRINT`, `MSBUILD_PATH`, `LIBCLANG_PATH`. Le conteneur et le mot de passe
doivent être des variables sécurisées. `MSBUILD_PATH` doit viser le MSBuild de
l'installation VS2026 disposant des deux toolsets.

`SIGNTOOL_VERIFY_PATH` est **facultatif** : détection automatique du SignTool x64 du
SDK Windows, surcharge seulement si nécessaire. `SIGNING_TIMESTAMP_URL` est aussi
facultatif, avec `http://timestamp.digicert.com` par défaut pour le framework.
Aucun certificat privé n'est exporté. Le framework reçoit le mot de passe en
argument comme son interface l'exige ; la CI n'affiche pas cette commande/sortie.

Réseau : GitHub, raw/release assets et sous-modules ; crates.io/static.crates.io et
les dépendances Git de Cargo ; static.rust-lang.org ; pub.dev et
storage.googleapis.com pour Flutter/Dart ; pypi.org/files.pythonhosted.org ; sources
et outils téléchargés par les ports vcpkg ; download.visualstudio.microsoft.com pour
l'intégration MSBuild manquante ; horodatage et CRL/OCSP des certificats.
Une liste exhaustive d'hôtes transitifs dépend du baseline et des redirections :
à établir depuis les logs du premier provisionnement, pas par supposition.

## Exécution et vérification

```powershell
powershell -NoProfile -File ci/Test-Runner.ps1
```

Ce précontrôle teste d'abord l'accès SMB avec des fichiers temporaires, puis peut
télécharger l'intégration MSBuild privée verrouillée ; il ne
compile rien, ne signe rien et n'utilise pas la clé privée.
Il contrôle outils, configuration et composants VS détectables ; il ne remplace
pas le build pour valider l'accès à la clé, tous les composants SDK ou le réseau.

Ordre : `Test-Runner` → `Test-Ci` → `Prepare-Source` → `Test-Toolchain` → `Prepare-BuildEnvironment` →
`Build-Payload` → `Complete-Payload` → `Sign-Payload` → `Package-Installer` →
`Sign-Installer` → `Publish-Installer`. Une seule étape Bitbucket garde la même machine Windows et la clé.
Un checkout propre est obligatoire ; aucune ancienne sortie n'est réutilisée.

Politique de signature : EXE/DLL non signés → framework WanPulse ; signatures
 tierces valides → conservation octet pour octet ; signature existante invalide →
 échec. Un binaire principal ProVDesk signé par un tiers est refusé. Les paquets
 pilotes sont conservés et vérifiés avec leurs catalogues (`/kp /c`), y compris
 INF/DLL/données déclarées. Pas d'horodatage ajouté aux signatures tierces.

Avant et après signature finale, `Verify-Package.py` décompresse `data.bin`, compare
chaque fichier au manifeste signé et vérifie que le blob est embarqué dans l'EXE.
Les manifestes, rapports, patches, lockfiles, ZIP signé et EXE final sont dans `out/`.

### Publication SMB

Après `Sign-Installer`, `Publish-Installer.ps1` publie exclusivement
`out/ProVDesk.exe` vers `\\<ARTIFACTS_SHARING_HOST>\builds\WanPulse\ProVDesk\ProVDesk-<version>.exe`.
Le serveur vient de la variable obligatoire `ARTIFACTS_SHARING_HOST` (par exemple
`wp-cloudstorage`, sans `\\` ni chemin). Le partage `builds` et le sous-dossier
`WanPulse\ProVDesk` restent fixes ; `WANPULSE_OEM_PUBLISHER` ne les modifie pas. La version est lue dans `ProductVersion` de l'EXE final signé, enregistrée dans
`build.json` puis revérifiée avant publication. Par exemple : `ProVDesk-1.5.0.exe`.
Une version absente, incohérente ou impropre à un nom de fichier bloque la publication.
Chaque build manuel réussi remplace uniquement le fichier de
la même version ; les EXE des autres versions sont conservés dans le même dossier.

Variables Bitbucket requises :

| Variable | Valeur | Sécurisée |
|---|---|---|
| `ARTIFACTS_SHARING_HOST` | Nom du serveur, par exemple `wp-cloudstorage` | Non |
| `ARTIFACTS_SHARING_USER` | Compte local, `DOMAINE\compte` ou UPN | Facultatif |
| `ARTIFACTS_SHARING_PASSWORD` | Mot de passe du compte | Oui |

Un compte non qualifié devient `<ARTIFACTS_SHARING_HOST>\<compte>` ; un compte
`DOMAINE\compte` ou UPN est conservé. Dès le début de `Test-Runner`, avant les
téléchargements et les compilations, le précontrôle monte le partage avec ces
identifiants et teste le dossier `WanPulse\ProVDesk` : création si nécessaire,
écriture, lecture, renommage avec remplacement et suppression. Il n'utilise que
deux fichiers `.provdesk-preflight-<GUID>-*.tmp`, nettoyés ensuite, sans toucher
aux EXE existants. Le lecteur temporaire est démonté à la fin du contrôle.
Une erreur de configuration, connexion, authentification ou droit arrête le
pipeline avant le build et indique l'opération échouée. Une coupure réseau peut
empêcher le nettoyage ; le nom unique permet d'identifier les fichiers concernés.

Le runner doit résoudre le serveur configuré, accéder à SMB (TCP 445) et disposer
des droits nécessaires sur ce dossier. Ce précontrôle vérifie les droits au moment
du test ; il ne garantit pas que le serveur restera disponible jusqu'à la publication.
Aucune interaction ni élévation UAC n'est nécessaire.

La publication exige le manifeste du build Bitbucket courant, une signature
WanPulse valide et horodatée, et un SHA256 identique à `build.json`. L'EXE est copié
sous un nom temporaire unique, relu pour vérifier son SHA256 puis renommé en
`ProVDesk-<version>.exe`. Le fichier local `out/ProVDesk.exe` reste inchangé. Une erreur fait échouer le pipeline ; le fichier temporaire est
nettoyé si possible et le lecteur SMB démonté. Une coupure réseau peut empêcher
ce nettoyage. Aucun autre fichier de `out/` n'est copié. Le harness local sans
signature n'appelle pas cette étape et n'exige pas les identifiants SMB.

À conserver comme artefacts Bitbucket :

- `ProVDesk.exe.sha256` : empreinte du fichier final après signature.
- `build.json` : version de l’EXE final, commits, numéro de build, signataire et empreinte finale.
- `signatures.json`, `payload-signed.json` : rapport des signatures et inventaire
  des fichiers embarqués avec leurs empreintes.
- `payload-signed.zip` et son SHA256 : payload décompressé pour analyse ou support ;
  ce ZIP ne remplace pas l'exécutable de distribution.
- Patches, versions et logs de précontrôle : traçabilité technique.

Le lecteur PowerShell temporaire établit la connexion SMB avec les identifiants.
Les opérations de fichiers utilisent ensuite le chemin UNC absolu, pas
`ProVDeskPreflight...:\` ou `ProVDeskPublish...:\` : sous Windows PowerShell 5.1,
ces lecteurs virtuels peuvent faire répéter la racine UNC lors des opérations de
contenu. Le problème a été reproduit avec l'ancien helper puis corrigé pour le
précontrôle **et** la publication.

`Test-Publication.ps1` couvre les erreurs avec des fixtures locales.
`Test-PublicationUnc.ps1` est un test d'intégration explicite sur un **vrai SMB** :
il crée un sous-dossier unique dans le partage de test, exécute le précontrôle,
vérifie la copie et le remplacement d'un fichier, puis supprime son sous-dossier
et les lecteurs temporaires. Il ne simule aucune commande de fichiers ou de montage ;
seule la politique de signature du faux EXE est substituée. Utiliser un partage de
test dédié, jamais le dossier des livrables :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ci/tests/Test-PublicationUnc.ps1 -TestShareRoot '\\serveur-test\partage-test'
```

Le test utilise l'identité Windows courante par défaut ; `-TestCredential` accepte
un `PSCredential` lorsqu'il est appelé dans une session PowerShell. Validation
locale effectuée sous **Windows PowerShell 5.1.26100.9711** via `\\localhost\C$`
et `\\127.0.0.1\C$`, dans un dossier jetable du dépôt. L'ancien helper reproduit la
racine répétée ; le helper corrigé passe le précontrôle, la publication/remplacement
et le nettoyage sur les deux adresses. Cela ne valide pas les identifiants ni les
permissions du compte Bitbucket sur le serveur de production.


## Build local propre du 10 novembre 2026

Le client et le wrapper final ont été reconstruits depuis un nouveau workspace,
avec les scripts CI courants, les toolsets VS2026 v143/v142 et le parallélisme
automatique. Les opérations de signature WanPulse et de publication ont été
exclues ; les catalogues des pilotes tiers ont été vérifiés normalement.
Les liens symboliques Flutter ont été créés à neuf après activation du mode
développeur Windows sur le poste local.

Résultat : EXE final **1.5.0**, non signé, **24,61 Mio** ; les **107 fichiers**
embarqués correspondent exactement au manifeste. Le client répond `1.5.0` à
`--version` avec un code de sortie 0. Temps observés : Rust principal **10 min 18 s**,
affichage virtuel **2 min 13 s**, Flutter Windows **88,4 s**, ensemble du client
avec génération **15 min 26 s**, assemblage final **3 min 20 s**. Environ **24 min**
au total, correction et reprise du précontrôle comprises.

Les deux utilitaires Rust ont été repris du cache persistant ; **16 paquets vcpkg**
ont été restaurés depuis son cache binaire. Aucun ancien `source/target` ou build
Flutter du client n'a été réutilisé. Ces mesures concernent le poste local de
16 processeurs logiques / 31,5 Gio et ne prédisent pas la durée ou la RAM du runner.

Le test a détecté que `vcpkg env` supprime la politique PowerShell héritée :
l'appel au probe précise maintenant `-ExecutionPolicy Bypass` pour ce seul
sous-processus, sans modifier la politique Windows globale. Le contrôle a ensuite
réussi, puis le build a repris. La signature réelle, la publication SMB et les
scénarios d'installation/usage restent hors de cette validation locale.

## État de validation

Comparaison effectuée sur les sources exactes et inspection des archives tierces.
Les catalogues des pilotes et tous leurs membres déclarés ont passé la vérification
réelle SignTool, y compris `/kp /c`, sur le poste local avec le SDK 10.0.26100.0.
Les essais CMake v143/v142 et MSBuild direct ont compilé et exécuté leurs programmes
avec Build Tools 2026. Les tests locaux couvrent aussi PowerShell 5.1/YAML,
la signature simulée, les caches, les diagnostics, SUBST et le packer avec
Python 3.15.2/Brotli 1.2.1. Le pipeline #13 a validé une signature WanPulse réelle
avec horodatage sur le programme de précontrôle, avant son échec dans libvpx.
Cela ne valide pas encore un livrable complet signé ni son installation.
Valider ensuite en VM installation, upgrade, désinstallation, accès distant,
affichage/impression et Defender. Publier les sources correspondantes et patches
avec la release ; le transfert SMB décrit ci-dessous ne publie que l’EXE signé.

La signature est obligatoire : `SKIP_SIGNATURE` hérité du workspace est forcé à `false` dans ce pipeline. Les variables de signature restent requises.

Le pipeline crée un lecteur `subst` libre (de Z: à D:) vers le checkout existant,
puis lance tous les scripts via ce chemin court. Aucun fichier n'est déplacé et
les ACL restent celles du workspace. Les artefacts restent dans `out/` du checkout.
Le lecteur est retiré dans un bloc `finally`, y compris après un échec ;
`after-script` réessaie le nettoyage à partir du fichier local `.ci-subst.json`.
Le nettoyage vérifie la cible et ne retire jamais volontairement un lecteur occupé
par un autre chemin. Un arrêt brutal du service ou de Windows peut empêcher les
deux nettoyages : vérifier alors les mappings `subst` dans le contexte du runner.

Le triplet inclut les fichiers via `CMAKE_CURRENT_LIST_DIR`. La version exacte
v143 et le chemin VS2026 validés sont écrits dans `build-tools/vcpkg-selection.cmake`,
puis archivés. Ils ne dépendent pas de variables d'environnement que vcpkg efface.
Une lecture du triplet par `cmake -P` vérifie les inclusions avant l'installation.

## Contrôles et diagnostics après audit

`Test-Ci.ps1` exécute les tests rapides avant le clonage et les compilations longues :
politique de signature, appel natif avec stderr et code retour, catalogues pilotes,
ressources, choix VS2026, cache Rust, collecte des diagnostics, triplet vcpkg
et transmission des options MSBuild avec des chemins contenant des espaces.
Chaque test est isolé dans un processus PowerShell 5.1. Les tests de packaging Python
s'exécutent après l'installation de Brotli. Les tests SUBST restent disponibles pour
une validation locale séparée afin de ne pas créer de lecteurs imbriqués en CI.

Le framework de signature peut écrire sur stderr sans provoquer à lui seul un échec.
Un code retour non nul reste fatal ; un code zéro doit être suivi d'une signature
Authenticode valide, du signataire attendu et d'un horodatage. Aucune sortie brute
du framework n'est exportée. L'exemption des pilotes est limitée aux membres vérifiés
des catalogues ; un fichier inattendu dans leurs dossiers fait échouer le pipeline.

Flutter reçoit `-T v143,host=x64,version=<version validée>,VCTargetsPath=<chemin validé>` : la même version exacte
que Rust/vcpkg, y compris si plusieurs versions v143 sont installées. `vcpkg list`
utilise le même `--x-install-root` que l'installation et contrôle la présence des
sept bibliothèques natives principales avant d'archiver l'inventaire.

`diagnostics/**` est un artefact distinct de `out/**`, collecté dans le `finally`
avant retrait du lecteur, avec reprise dans `after-script` si nécessaire. Sont admis
les fichiers `.log` de vcpkg/buildtrees et du build Flutter Windows, ainsi qu'une
liste explicite d'inventaires/configurations. Limites : 5 Mio par fichier, 50 Mio
au total avant masquage ; les fichiers ignorés sont signalés dans `index.txt`.
Les valeurs des variables PASSWORD/SECRET/TOKEN/SIGNING_CONTAINER et les identifiants
dans les URL HTTP sont masqués. Ce filtre ne garantit pas de détecter un secret inconnu
ou transformé : garder les artefacts dans le dépôt privé. Une interruption brutale
peut empêcher la collecte. Les livrables signés restent réservés à `out/**` après succès.

## Cache des utilitaires Rust

Le cache persistant est propre au compte du runner :
`%LOCALAPPDATA%/WanPulse/ProVDesk/ci-tools/<clé>`. La clé inclut `ci/rust-tools.json`
(versions, features, cible et Rust), la version MSVC exacte et le code du gestionnaire
de cache. Seuls cargo-expand et flutter_rust_bridge_codegen sont réutilisés ; ni le
payload, ni les signatures, ni les secrets n'y sont placés. Chaque utilisation contrôle
le SHA256 enregistré, la version de l'exécutable et l'intégrité de sa copie dans
`build-tools/rust/bin`. Un cache absent ou altéré déclenche une réinstallation `--locked`.
Un verrou exclusif interdit la mise à jour simultanée d'une même entrée.

Le cache est publié après chaque outil installé, même si le build échoue ensuite.
Les anciennes clés ne sont pas supprimées automatiquement : surveiller ce dossier
sur le petit runner et supprimer les entrées devenues inutiles hors exécution de CI.
Le contrôle d'espace disque inclut déjà le volume de LOCALAPPDATA. Le cache ne rend
pas les exécutables fiables face à une modification malveillante par le compte du
runner lui-même ; ses droits doivent rester limités au compte et aux administrateurs.

`Test-PipelineLifecycle.ps1` teste localement le lanceur et le nettoyage sur des étapes factices, en réussite et en échec, sans compiler ni signer.

Le chemin VS2026 généré conserve exactement les séparateurs Windows et la casse renvoyés par vswhere : vcpkg compare le chemin de sélection à celui de l'instance détectée. Les arguments CMake entre crochets préservent les antislashs.

## Vérification des interactions avant compilation

Après le checkout source, `Test-Toolchain.ps1` vérifie l'applicabilité des patches et
charge réellement libclang et vérifie la création de liens symboliques pour Flutter.
Il lance d'abord les sondes de compilation ci-dessous,
avant de télécharger vcpkg et ses outils internes. Il prépare ensuite vcpkg et appelle
**`vcpkg env`**, avec le vrai triplet et le vrai répertoire d'installation, puis vérifie
le compilateur résolu et VCToolsVersion dans cet environnement isolé. Cette étape
précède Flutter et les outils Rust.

Deux petits projets CMake exécutent réellement compilation C++, ressources Windows,
édition de liens et lancement en v143 puis v142, avec la même sélection explicite
des fichiers MSBuild que l'application. Une assertion à la compilation refuse une
version mineure MSVC différente de celle sélectionnée. Un troisième essai utilise
directement MSBuild avec les propriétés transmises au port libvpx.
Le probe CMake v143 est signé et horodaté
par le framework WanPulse, puis vérifié ; cet essai utilise donc la clé du runner
avant le build applicatif. Les exécutables de probe sont supprimés et ne sont pas
des livrables. Les résultats et logs non secrets sont ajoutés aux diagnostics.

Le test `Test-SigningPipeline.ps1` traverse le vrai script Sign-Payload avec plusieurs
fichiers, de faux outils natifs et une vérification cryptographique simulée. Il vérifie
les manifestes JSON, le rapport et la conservation des octets tiers. Les lectures de
tableaux JSON sont explicitement déroulées pour Windows PowerShell 5.1.
`Test-ForkPackage.py` appelle le générateur Python exact du fork avec Brotli 1.2.1,
puis vérifie les fichiers imbriqués, accents, fichier vide et point d'entrée ; il ne
compile pas le wrapper et ne valide pas son exécution Windows.

Les tests locaux ne remplacent pas une exécution complète du pipeline signé.
Valider en VM l'installation, la mise à niveau, la session distante,
la désinstallation et les détections Defender avec l'installateur signé.
