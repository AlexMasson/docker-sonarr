# syntax=docker/dockerfile:1

# --- Stage 1: Build frontend ---
FROM node:20-alpine AS frontend

ARG SONARR_REPO="https://github.com/AlexMasson/Sonarr.git"
ARG SONARR_BRANCH="feature/llm-prioritization"

RUN apk add --no-cache git && \
  git clone --depth 1 --branch "${SONARR_BRANCH}" "${SONARR_REPO}" /src

WORKDIR /src

RUN yarn install --frozen-lockfile && \
    yarn build

# --- Stage 2: Build backend ---
FROM mcr.microsoft.com/dotnet/sdk:6.0-alpine AS builder

COPY --from=frontend /src /src

WORKDIR /src/src

# Remove global.json version lock so dotnet uses the available SDK
RUN rm /src/global.json

# Build like the official Sonarr release: framework-dependent, then add runtime files separately
RUN dotnet msbuild -restore Sonarr.sln \
      -p:Configuration=Release \
      -p:RuntimeIdentifiers=linux-musl-x64 \
      -t:PublishAllRids \
      /p:TreatWarningsAsErrors=false && \
    mkdir /build && \
    cp -r /src/_output/net6.0/linux-musl-x64/publish/* /build/ && \
    cp -r /src/_output/UI /build/UI && \
    # Copy .NET 6 runtime native libs so the binary can run without dotnet in PATH
    cp /usr/share/dotnet/shared/Microsoft.NETCore.App/6*/libhostfxr.so /build/ && \
    cp /usr/share/dotnet/shared/Microsoft.NETCore.App/6*/libcoreclr.so /build/ && \
    cp /usr/share/dotnet/shared/Microsoft.NETCore.App/6*/lib*.so /build/ 2>/dev/null || true

# --- Stage 3: Runtime image (same as upstream linuxserver) ---
FROM ghcr.io/linuxserver/baseimage-alpine:3.20

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Custom LLM-prioritization build:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="AlexMasson"

# set environment variables
ENV XDG_CONFIG_HOME="/config/xdg" \
  SONARR_CHANNEL="v4-stable" \
  SONARR_BRANCH="main" \
  COMPlus_EnableDiagnostics=0 \
  TMPDIR=/run/sonarr-temp

RUN \
  echo "**** install packages ****" && \
  apk add --no-cache \
    icu-libs \
    sqlite-libs \
    xmlstarlet && \
  mkdir -p /app/sonarr/bin

# copy built binaries and UI from builder stage (UI goes inside bin/)
COPY --from=builder /build/ /app/sonarr/bin/

RUN \
  echo -e "UpdateMethod=docker\nBranch=feature/llm-prioritization\nPackageVersion=${VERSION:-LocalBuild}\nPackageAuthor=AlexMasson (fork)" > /app/sonarr/package_info && \
  printf "Custom build version: ${VERSION}\nBuild-date: ${BUILD_DATE}" > /build_version

# add local files
COPY root/ /

# ports and volumes
EXPOSE 8989

VOLUME /config
