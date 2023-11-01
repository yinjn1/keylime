# The builder stage which uses the latest Fedora image to build the keylime
FROM registry.fedoraproject.org/fedora:38 AS builder

# The following packages are required for building
RUN dnf makecache && \
    dnf -y install python3 python3-jinja2 python3-setuptools python3-wheel

COPY . /src/keylime/
WORKDIR /src/keylime

# Build keylime
RUN python3 setup.py bdist_wheel

#
#
#

FROM registry.fedoraproject.org/fedora:38

LABEL description="TPM-based key bootstrapping and system integrity measurement system for cloud"
LABEL usage="podman run --name NAME --rm --device /dev/tpmrm0 -v /sys/kernel/security:/sys/kernel/security:ro -dt IMAGE"

ENV TPM2TOOLS_TCTI="device:/dev/tpmrm0"

# The following packages are required for running
RUN dnf makecache && \
    dnf -y install efivar-libs expect procps-ng tpm2-tools tpm2-tss python3 python3-gpg python3-pip python3-setuptools python3-wheel && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Copy all keylime install files from the builder image
COPY --from=builder /src/keylime/dist/keylime-*.whl /keylime-install/
COPY --from=builder /src/keylime/requirements.txt /keylime-install/requirements.txt
COPY --from=builder /src/keylime/templates /usr/share/keylime/templates
COPY --from=builder /src/keylime/tpm_cert_store /var/lib/keylime/tpm_cert_store

# Install keylime and python dependencies
RUN pip3 install --no-cache-dir -r /keylime-install/requirements.txt /keylime-install/keylime-*.whl && \
    rm -rf /keylime-install

# Create keylime default config
RUN mkdir -p /etc/keylime && \
    python3 -m keylime.cmd.convert_config --defaults --out /etc/keylime --templates /usr/share/keylime/templates

RUN sed -i 's/127.0.0.1/0.0.0.0/g' /etc/keylime/*.conf
RUN sed -i 's/^num_workers\b.*$/num_workers = 1/' /etc/keylime/verifier.conf
