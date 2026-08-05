# Builds libglide_ffi.so against glibc 2.17 (CentOS 7 baseline), so the
# resulting binary loads on anything with glibc >= 2.17 — covers
# amazonlinux:2018.03 (2.17), amazonlinux:2 (2.26), amazonlinux:2023 (2.34).
FROM quay.io/pypa/manylinux2014_x86_64

ARG PROTOC_VERSION=29.1

RUN yum install -y unzip && yum clean all

RUN curl -sSL -o /tmp/protoc.zip \
      "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip" \
    && unzip -q /tmp/protoc.zip -d /usr/local \
    && rm /tmp/protoc.zip

ENV PATH="/root/.cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable

WORKDIR /workspace
