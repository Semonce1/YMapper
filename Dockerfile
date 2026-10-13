# Build Flutter Web
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY . .
RUN flutter pub get && flutter build web --release

# Serve static files
FROM caddy:2-alpine
COPY --from=build /app/build/web /srv
CMD caddy file-server --root /srv --listen :$PORT
