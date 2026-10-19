# ---------- ÉTAPE 1 : la compilation ----------
FROM golang:1.27 AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY main.go ./

# CGO_ENABLED=0 : désactive cgo, donc Go produit un binaire
#   STATIQUE qui embarque tout ce dont il a besoin.
# GOOS=linux : cible explicite, évite les surprises si on build
#   depuis un autre OS.
# -ldflags="-s -w" : supprime la table des symboles et les infos
#   de debug. Quelques Mo de moins. Optionnel mais classique.
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o guestbook .

# ---------- ÉTAPE 2 : l'image finale ----------
FROM scratch

WORKDIR /app

COPY --from=builder /app/guestbook /app/guestbook
COPY public ./public

EXPOSE 3000

CMD ["/app/guestbook"]