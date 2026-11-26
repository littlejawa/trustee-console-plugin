# UBI 9 minimal build image — node/npm plus awk/bash/tar is all the yarn build needs.
FROM registry.access.redhat.com/ubi9/nodejs-22-minimal:latest AS build-main
USER root
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
WORKDIR /usr/src/app
COPY package.json yarn.lock .yarnrc.yml ./
COPY .yarn .yarn
RUN LOCAL_YARN="node $(awk '/yarnPath:/{print $2}' .yarnrc.yml)" && \
    $LOCAL_YARN install --immutable
COPY console-extensions.json LICENSE tsconfig.json webpack.config.ts .swcrc ./
COPY locales ./locales
COPY src ./src
RUN LOCAL_YARN="node $(awk '/yarnPath:/{print $2}' .yarnrc.yml)" && \
    $LOCAL_YARN build

# RHEL 9 nginx with OpenSSL 3.5 (ML-KEM), so the chart's PQC ssl_ecdh_curve defaults work.
FROM registry.access.redhat.com/ubi9/nginx-126:latest
# The Trustee operator (and this repo's Helm chart) render nginx.conf with
# `root /usr/share/nginx/html`, a directory owned by the nginx RPM. Serve the
# build from there by adding files only: deleting or replacing RPM-installed
# files (e.g. turning the directory into a symlink) fails the Konflux
# ecosystem-cert-preflight-checks HasModifiedFiles check, which EC enforces.
COPY --from=build-main /usr/src/app/dist /usr/share/nginx/html/
# /builds keeps the per-release layout the entrypoint selects via OCP_VERSION.
COPY --from=build-main /usr/src/app/dist /builds/main
COPY entrypoint.sh /entrypoint.sh
# EC certification requires licensing information in /licenses.
COPY LICENSE /licenses/LICENSE

USER root
RUN chmod +x /entrypoint.sh && \
    mkdir -p /tmp/nginx && \
    chgrp -R 0 /tmp/nginx /builds && \
    chmod -R g=u /tmp/nginx /builds
USER 1001
ENTRYPOINT ["/entrypoint.sh"]

# Red Hat labels. The release pipeline rejects a component whose image omits
# them, and `name` has to match the repository this image publishes to.
#
# Spell the values out rather than referencing ARGs: the nginx base image sets
# ENV NAME, SUMMARY and DESCRIPTION, and ENV wins over ARG when a label
# expands $NAME, so an ARG-based block silently inherits nginx's text.

LABEL com.redhat.component="trustee-console-plugin"
LABEL description="The Trustee attestation console plugin."
LABEL io.k8s.description="The Trustee attestation console plugin."
LABEL io.k8s.display-name="Trustee attestation console plugin"
LABEL name="build-of-trustee/trustee-console-plugin-rhel9"
LABEL summary="The Trustee attestation console plugin."
LABEL distribution-scope=public
LABEL release="1"
LABEL url="https://access.redhat.com/"
LABEL vendor="Red Hat, Inc."
LABEL version="1.3.0"
LABEL maintainer="Red Hat"
LABEL io.openshift.tags=""
LABEL cpe="cpe:/a:redhat:confidential_compute_attestation:1.140::el9"
