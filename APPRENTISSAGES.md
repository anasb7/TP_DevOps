# Apprentissages

## Exercice 0 — Installer Go

Installer Go sur Ubuntu/WSL pour lancer l'application en local.

### Problème rencontré et pourquoi il est survenu

`sudo apt install golang` m'a donné Go 1.22.2, alors que le `go.mod` du projet demande `go 1.27.1`. Depuis Go 1.21, cette ligne est une version minimale exigée, pas une simple indication : avec une version plus ancienne, Go refuse de compiler. Les dépôts Ubuntu figent les versions, ce qui marche mal avec un langage qui sort une version majeure tous les six mois.

Ensuite, après avoir installé la version officielle, la commande `go` restait introuvable. Avec apt le binaire va dans `/usr/bin`, déjà dans le PATH ; l'archive officielle s'installe dans `/usr/local/go/`, et le shell ne cherche pas dans les sous-dossiers.

### Solution appliquée et pourquoi cette solution fonctionne

J'ai désinstallé la version apt, installé l'archive officielle dans `/usr/local/go`, et ajouté `/usr/local/go/bin` au PATH dans `~/.bashrc`.

`/usr/local` est l'endroit prévu pour ce qu'on installe à la main, par opposition à `/usr` qui appartient au gestionnaire de paquets : un `apt upgrade` ne viendra donc jamais l'écraser. J'ai mis le chemin en tête du PATH pour qu'il passe avant d'éventuels restes d'apt.

### Ce que j'ai appris

Qu'une version de langage écrite dans un fichier de projet est une vraie contrainte, pas une info décorative.

Et surtout que je venais de perdre du temps sur un problème d'installation sans écrire une ligne de code. C'est exactement ce que les conteneurs évitent : l'image `golang:1.27` a déjà la bonne version et les bons chemins, pour tout le monde.

---

## Exercice 1 — Conteneuriser le guestbook

Mettre l'application dans une image Docker, la faire passer sous 20 MB, et la lancer avec `docker compose`.

### Problème rencontré et pourquoi il est survenu

**La taille.** Mon premier Dockerfile partait de `golang:1.27` et compilait dedans. Ça marchait, mais l'image faisait **355 MB** pour un binaire de 4 MB : elle contenait le compilateur, la bibliothèque standard et une Debian complète. J'expédiais l'atelier avec l'objet fabriqué.

**Le conteneur qui ne démarre pas.** J'ai donc écrit un Dockerfile en deux étapes avec une image finale `scratch` (vide). L'image est tombée à 8,07 MB, mais au lancement :

```
exec /app/guestbook: no such file or directory
```

Le fichier existait pourtant. Ce n'est pas lui qui manquait, mais l'éditeur de liens dynamique. Go active cgo par défaut, car certains paquets standards comme `net` peuvent appeler du code C : le binaire est donc lié dynamiquement et réclame la libc au démarrage. Elle existe dans `golang:1.27`, qui est une Debian ; dans `scratch` il n'y a rien.

### Solution appliquée et pourquoi cette solution fonctionne

**Le build multi-étapes.** La première étape (`AS builder`) a le compilateur et fabrique le binaire. La seconde part de `scratch` et récupère uniquement ce binaire avec `COPY --from=builder`. Le reste est abandonné en route.

**`CGO_ENABLED=0`.** Désactive cgo, donc Go compile un binaire statique qui embarque tout et ne réclame rien au démarrage. Il peut alors tourner dans une image qui ne contient que lui.

**`-ldflags="-s -w"`.** Enlève les symboles et les infos de debug : 8,07 MB → **4,1 MB**. En échange, une erreur en production affichera une trace moins lisible.

Deux détails qui comptent : `COPY go.mod go.sum` est séparé de `COPY main.go` pour que Docker garde les dépendances en cache quand seul le code change ; et le `WORKDIR` final doit contenir `public/`, sinon le serveur démarre mais l'interface renvoie 404.

**docker compose** remplace enfin la suite `docker build` puis `docker run -p 3000:3000` par un fichier versionné et une seule commande.

### Ce que j'ai appris

Qu'un message d'erreur peut parler d'autre chose que ce qu'il nomme. La bonne question n'était pas « où est passé mon binaire » mais « de quoi a-t-il besoin pour démarrer ». Un `file` dessus l'aurait montré tout de suite.

Que l'idée du multi-stage, c'est de séparer ce qui sert à **fabriquer** de ce qui sert à **exécuter**. Et ça ne joue pas que sur la taille : l'image de départ contenait un shell, `apt` et `curl`, autant d'outils pour quelqu'un qui compromettrait le conteneur.

Que l'ordre des instructions dans un Dockerfile décide de ce que le cache peut réutiliser.

---

## Exercice 2 — Ajouter une base de données

Brancher un Redis sur le guestbook pour qu'il enregistre enfin les messages, au lieu d'afficher « No database connection ».

### Problème rencontré et pourquoi il est survenu

L'application se connecte à Redis comme ceci :

```go
Addr: os.Getenv("REDIS_HOST") + ":6379"
```

Tant que la variable n'est pas définie, l'adresse vaut `":6379"`, c'est-à-dire le localhost du conteneur guestbook. Or ce conteneur ne contient qu'un binaire de 4 MB, rien d'autre. La connexion échoue, le handler part en `panic`, et Negroni le rattrape et renvoie une erreur — d'où le message d'avertissement qui ne bouge pas et le sablier qui tourne quand on soumet un message.

Le réflexe serait de mettre `localhost` dans la variable, mais ça ne change rien : chaque conteneur a sa propre pile réseau, et son localhost ne désigne que lui-même.

### Solution appliquée et pourquoi cette solution fonctionne

J'ai ajouté un second service dans `docker-compose.yaml` et renseigné la variable :

```yaml
services:
  guestbook:
    ...
    environment:
      REDIS_HOST: redis
    depends_on:
      - redis

  redis:
    image: redis:7
    ports:
      - "6379:6379"
```

Compose crée un réseau privé pour le projet, avec un DNS interne où chaque service est joignable **par son nom de service**. Mettre `redis` donne donc l'adresse `redis:6379`, qui est résolue vers le bon conteneur.

Le service Redis n'a pas de `build` : on tire l'image publique officielle telle quelle. J'ai mis le tag `redis:7` et pas `latest`, pour que le comportement reste le même dans six mois.

`depends_on` force Redis à démarrer avant guestbook. À noter qu'il garantit l'ordre de démarrage, pas que Redis soit prêt à répondre — ça passe ici parce que Redis démarre vite, mais avec une base plus lente il faudrait un `healthcheck`.

### Ce que j'ai appris

Que dans un réseau Compose, les services se parlent par leur nom, et que `localhost` dans un conteneur ne désigne que ce conteneur. C'est le genre d'erreur qui donne un message trompeur (« connexion refusée ») alors que le service tourne parfaitement à côté.

Que la configuration par variables d'environnement permet de brancher la même image sur des backends différents sans la recompiler. La même image `guestbook:v0.3.0` fonctionne en local avec ce Redis-là et pourrait pointer ailleurs en production.

Et en testant un `docker compose down` puis `up` : les messages disparaissent. Le système de fichiers d'un conteneur naît et meurt avec lui. Pour garder des données il faut les stocker ailleurs — c'est l'objet de l'exercice suivant.

---

## Exercice 3 — Persistance et hot-reloading

*(à compléter)*

---

## Exercice 4 — Hot-reloading sur d'autres stacks

*(à compléter)*