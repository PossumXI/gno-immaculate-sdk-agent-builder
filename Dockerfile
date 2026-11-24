# Reproduces every CI check in one container, with no local toolchain.
#
#   docker build -t immaculate-verify .
#   docker run --rm immaculate-verify
#
# Mirrors .github/workflows/verify.yml: Gno v1.8.0 built with Go 1.25, Node 22,
# then the Node module tests, gno lint + unit tests, and experiments E1-E14.

FROM golang:1.25-bookworm AS gno
RUN git clone --depth 1 --branch v1.8.0 https://github.com/gnolang/gno.git /opt/gno \
 && cd /opt/gno \
 && mkdir -p build \
 && GOWORK=off go build -o build/gno ./gnovm/cmd/gno \
 && rm -rf /opt/gno/.git

FROM node:22-bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends git bash ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY --from=gno /opt/gno /opt/gno
ENV GNO_SRC=/opt/gno
WORKDIR /src
COPY . .
# Sources are committed with CRLF, which bash on Linux rejects outright
# ("set: pipefail\r: invalid option name"). Normalize shell scripts before use.
RUN sed -i 's/\r$//' scripts/*.sh
CMD ["bash", "scripts/reproduce.sh"]
