FROM hexpm/elixir:1.13.4-erlang-24.3.4.5-alpine-3.15.6

COPY . .

ENV MIX_ENV=prod

RUN apk add git gcc g++ musl-dev make cmake file-dev &&\
	echo "import Mix.Config" > config/prod.secret.exs &&\
	mix local.hex --force &&\
	mix local.rebar --force &&\
	mix deps.get --only prod &&\
	mkdir release &&\
	mix release --path release

FROM alpine:3.14

ARG BUILD_DATE
ARG VCS_REF

LABEL maintainer="ops@akkoma.social" \
    org.opencontainers.image.title="akkoma" \
    org.opencontainers.image.description="akkoma for Docker" \
    org.opencontainers.image.authors="ops@akkoma.social" \
    org.opencontainers.image.vendor="akkoma.social" \
    org.opencontainers.image.documentation="https://git.akkoma.social/akkoma/akkoma" \
    org.opencontainers.image.licenses="AGPL-3.0" \
    org.opencontainers.image.url="https://akkoma.social" \
    org.opencontainers.image.revision=$VCS_REF \
    org.opencontainers.image.created=$BUILD_DATE

ARG HOME=/opt/akkoma
ARG DATA=/var/lib/akkoma

RUN echo "http://nl.alpinelinux.org/alpine/latest-stable/community" >> /etc/apk/repositories &&\
	apk update &&\
	apk add exiftool ffmpeg imagemagick libmagic ncurses postgresql-client curl unzip &&\
	adduser --system --shell /bin/false --home ${HOME} akkoma &&\
	mkdir -p ${DATA}/uploads &&\
	mkdir -p ${DATA}/static &&\
	chown -R akkoma ${DATA} &&\
	mkdir -p /etc/akkoma &&\
	chown -R akkoma /etc/akkoma

USER akkoma
 
RUN curl -L https://github.com/Cl0v1s/mangane/releases/latest/download/static.zip > ${DATA}/static.zip &&\
	mkdir -p ${DATA}/static/frontends/mangane/vendor/ &&\
    unzip ${DATA}/static.zip -d ${DATA}/static/frontends/mangane/vendor/

COPY --from=build --chown=akkoma:0 /release ${HOME}

COPY ./config/docker.exs /etc/akkoma/config.exs
COPY ./docker-entrypoint.sh ${HOME}

EXPOSE 4000

ENTRYPOINT ["/opt/akkoma/docker-entrypoint.sh"]
