# Bouge

Une petite app macOS native qui rappelle de bouger sur sa chaise et de changer de position **toutes les 20 minutes**.

Bouge reste dans la barre de menus et affiche une notification macOS dans un coin de l’écran. Swift + AppKit, Apple Silicon (`arm64`), macOS 13 ou plus. Gratuit, sous licence MIT, sans compte, abonnement, dépendance externe ni connexion réseau. Les sources utiles tiennent dans **~28 Ko**.

## Pourquoi pas une app lourde

Je ne vois pas pourquoi télécharger une grosse appli du Store alors qu’on peut faire la sienne en Swift en un instant. **Ne clone pas forcément Bouge.** Inspire ton agent : regarde ce qui existe, ce qu’il y a dedans, et fais la tienne. Au moins tu sauras exactement ce qui tourne sur ta machine — et ce sera light à mort.

https://github.com/user-attachments/assets/28739b3b-d825-489a-af44-315eaa63f9e8

## Compiler et installer

Les outils en ligne de commande Apple suffisent ; Xcode complet n’est pas nécessaire. Si besoin, installe-les avec `xcode-select --install`.

Si tu veux compiler celle-ci (optionnel — le but, c’est surtout de t’inspirer) :

```bash
git clone https://github.com/maax6/bouge.git
cd bouge
./scripts/build.sh
open build/Bouge.app
```

Le script compile pour Apple Silicon, génère une icône, assemble `build/Bouge.app` et signe l’app localement avec une signature ad hoc. Il vérifie la signature, Info.plist et l’architecture. Cette signature locale n’est pas une notarisation Apple pour distribuer un binaire sur d’autres Macs ; la compilation depuis les sources est le mode d’installation prévu.

Pour un usage quotidien, quitte Bouge puis déplace `build/Bouge.app` dans `~/Applications` ou `/Applications`. Garde une seule copie lancée. Une recompilation met à jour le build ; remplace ensuite la copie installée, après l’avoir quittée.

## Voir les notifications

Au premier lancement, autorise les notifications de Bouge. Un petit guide explique aussi comment rendre les bannières visibles. Tu peux le retrouver à tout moment dans le menu **Notifications et Concentration…**.

1. Dans **Réglages Système → Notifications → Bouge**, active **Autoriser les notifications** et l’affichage sur le **Bureau**.
2. Si **Ne pas déranger** ou un autre mode **Concentration** est actif, désactive ce mode dans le Centre de contrôle, ou garde-le actif et autorise Bouge dans **Réglages Système → Concentration → ton mode → Apps autorisées → Autoriser certaines apps**.
3. Clique sur le petit personnage dans la barre de menus, puis sur **Tester la notification**.

Le guide propose un bouton qui ouvre directement les réglages Concentration. Il explique ce réglage à tous les utilisateurs ; Bouge ne prétend pas détecter le mode actif et ne modifie pas les préférences système.

Une notification peut arriver dans le centre de notifications sans afficher de pop-up si Concentration la masque. L’autorisation de notifications seule ne suffit donc pas. Pour garder une bannière jusqu’à sa fermeture, choisis le style **Persistante** (ou **Alertes**, selon macOS). Le son dépend du réglage de Bouge, des réglages système et du volume.

Voir les [instructions Apple sur Concentration](https://support.apple.com/fr-fr/guide/mac-help/mchl613dc43f/mac).

## Utiliser Bouge

Le premier rappel arrive 20 minutes après le lancement ou la reprise. La notification invite à changer de position sur sa chaise.

| Commande | Effet |
| --- | --- |
| **J’ai bougé — repartir sur 20 min** | Démarre un nouveau cycle à partir de maintenant. |
| **Mettre en pause / Reprendre** | Suspend les rappels jusqu’à une reprise manuelle. La pause est conservée après réouverture. |
| **Tester la notification** | Envoie une nouvelle notification après une seconde, sans modifier le cycle régulier. Supprime l’ancien test pour éviter d’encombrer le centre de notifications. |
| **Son des notifications** | Active ou coupe le son ; le choix est conservé. |
| **Ouvrir à la connexion** | Demande le démarrage automatique via l’API macOS. Désactivé par défaut. |
| **Notifications et Concentration…** | Rouvre le guide de présentation des notifications. |
| **Quitter Bouge** | Annule les rappels programmés et ferme l’app. |

« J’ai bougé » et « Mettre en pause » sont aussi disponibles dans les options de la notification, selon la présentation de macOS.

Au passage en veille, les rappels sont annulés. Au réveil, un nouveau cycle de 20 minutes commence ; une pause manuelle reste en pause. Il n’y a pas de rattrapage de plusieurs rappels, de détection de posture ou de suivi d’activité au clavier.

Si l’ouverture à la connexion échoue, ajoute l’app manuellement dans **Réglages Système → Général → Ouverture et extensions → Ouvrir à la connexion**.

## Raccourcis et commandes locales

L’action **Ouvrir les URL** de Raccourcis peut commander Bouge. L’app assure elle-même la récurrence.

| URL | Commande |
| --- | --- |
| `bouge://test` | Tester la notification |
| `bouge://pause` | Mettre en pause |
| `bouge://resume` | Reprendre |
| `bouge://reset` | Repartir sur 20 minutes |
| `bouge://help` | Ouvrir le guide Notifications et Concentration |
| `bouge://quit` | Quitter |

## Architecture et préférences

- `Sources/Bouge.swift` : app, menu, notifications, pause, veille/réveil et ouverture à la connexion.
- `Sources/NotificationGuide.swift` : petit guide natif et lien vers Concentration.
- `Info.plist` : identité et URL locales ; `LSUIElement` garde l’app dans la barre de menus.
- `scripts/build.sh` : compilation sans paquet externe.
- `scripts/Icon.swift` : génération de l’icône avec AppKit.
- `scripts/check-test-notification.py` : contrôle des notifications réellement délivrées et des journaux macOS.

Les préférences sont stockées localement dans le domaine `fr.m4ks.bouge` : pause, son et version du guide déjà présenté. Un seul rappel récurrent est programmé avec `UNTimeIntervalNotificationTrigger(timeInterval: 1200, repeats: true)`. Les changements sont sérialisés pour éviter qu’une ancienne programmation asynchrone réactive les rappels après une pause. Chaque notification de test a un identifiant distinct.

Un arrêt forcé ou un crash peut laisser le rappel récurrent programmé. Relance l’app puis utilise **Quitter Bouge** pour l’annuler proprement.

## Vérifier

Le diagnostic lit l’état enregistré auprès de macOS, sans le modifier :

```bash
build/Bouge.app/Contents/MacOS/Bouge --diagnostics
```

Après autorisation et lancement, `authorization` vaut `2` et une seule demande `position-reminder` a `interval: 1200` et `repeats: true`. En pause ou après une fermeture normale, cette demande doit être absente.

Le contrôle de régression envoie deux notifications de test via le même gestionnaire que le bouton. Il vérifie des identifiants distincts, les enregistrements de présentation et l’absence de masquage par Concentration. Il vérifie aussi que les tests préservent le cycle régulier et la pause :

```bash
python3 scripts/check-test-notification.py ~/Applications/Bouge.app
```

Ce contrôle nécessite Python 3 et un terminal avec accès normal aux services et journaux macOS. Une entrée de journal « as banner » ne suffit pas si une autre entrée signale `interruptionSuppression`. Une observation visuelle reste nécessaire pour confirmer le pop-up. Le contrôle signale un échec si Concentration masque les bannières.

La compilation locale vérifie Swift 6 sans avertissement, l’architecture `arm64`, la signature et Info.plist. Le diagnostic, la délivrance des tests, la pause/reprise et la fermeture ont été contrôlés sur macOS. La veille/réveil et l’ouverture à la connexion restent à vérifier en conditions réelles.

## Licence

[MIT](LICENSE). Aucun service distant n’est nécessaire au fonctionnement de Bouge.
