# Stage 1 - Compile needed python dependencies
FROM python:3.7-buster AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY ./requirements /app/requirements
RUN pip install pip setuptools -U
RUN pip install -r requirements/production.txt


# Stage 2 - build frontend
FROM mhart/alpine-node:10 AS frontend-build

WORKDIR /app

COPY ./*.json /app/
RUN npm ci

COPY ./gulpfile.js ./webpack.config.js ./.babelrc /app/
COPY ./build /app/build/

COPY src/objecttypes/sass/ /app/src/objecttypes/sass/
COPY src/objecttypes/js/ /app/src/objecttypes/js/
RUN npm run build


# Stage 3 - Build docker image suitable for execution and deployment
FROM python:3.7-buster AS production

# Stage 3.1 - Set up the needed production dependencies
# install all the dependencies for GeoDjango
RUN apt-get update && apt-get install -y --no-install-recommends \
        postgresql-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/lib/python3.7 /usr/local/lib/python3.7
COPY --from=build /usr/local/bin/uwsgi /usr/local/bin/uwsgi

# Stage 3.2 - Copy source code
WORKDIR /app
COPY ./bin/docker_start.sh /start.sh
RUN mkdir /app/log /app/config

COPY --from=frontend-build /app/src/objecttypes/static/css /app/src/objecttypes/static/css
COPY --from=frontend-build /app/src/objecttypes/static/js /app/src/objecttypes/static/js
COPY ./src /app/src

RUN useradd -M -u 1000 user
RUN chown -R user /app

# drop privileges
USER user

ARG COMMIT_HASH
ARG RELEASE
ENV GIT_SHA=${COMMIT_HASH}
ENV RELEASE=${RELEASE}

ENV DJANGO_SETTINGS_MODULE=objecttypes.conf.docker

ARG SECRET_KEY=dummy

# Run collectstatic, so the result is already included in the image
RUN python src/manage.py collectstatic --noinput

LABEL org.label-schema.vcs-ref=$COMMIT_HASH \
      org.label-schema.vcs-url="https://github.com/maykinmedia/objecttypes-api" \
      org.label-schema.version=$RELEASE \
      org.label-schema.name="Objecttypes API"

EXPOSE 8000
CMD ["/start.sh"]
