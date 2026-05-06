# syntax=docker/dockerfile:1

# --- Stage 1: Build Sonarr from source ---
FROM mcr.microsoft.com/dotnet/sdk:6.0-alpine AS builder

ARG SONARR_REPO="https://github.com/AlexMasson/Sonarr.git"
ARG SONARR_BRANCH="feature/llm-prioritization"

RUN apk add --no-cache git && \
  git clone --depth 1 --branch "${SONARR_BRANCH}" "${SONARR_REPO}" /src

WORKDIR /src

RUN dotnet publish src/NzbDrone.Console/Sonarr.Console.csproj \
      -f net6.0 \
      -c Release \
      -o /build \
      -r linux-musl-x64 \
      --self-contained=false \
      /p:PublishSingleFile=false \
      /p:TreatWarningsAsErrors=false && \
    rm -rf /build/Sonarr.Update

# --- Stage 2: Runtime image (same as upstream linuxserver) ---
FROM ghcr.io/linuxserver/baseimage-alpine:3.23

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

# copy built binaries from builder stage
COPY --from=builder /build/ /app/sonarr/bin/

RUN \
  echo -e "UpdateMethod=docker\nBranch=feature/llm-prioritization\nPackageVersion=${VERSION:-LocalBuild}\nPackageAuthor=AlexMasson (fork)" > /app/sonarr/package_info && \
  printf "Custom build version: ${VERSION}\nBuild-date: ${BUILD_DATE}" > /build_version

# add local files
COPY root/ /

# ports and volumes
EXPOSE 8989

VOLUME /config
