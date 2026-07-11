# ============================================================================
#  AutoBugBounty · Imagen con todas las herramientas preinstaladas
# ============================================================================
FROM golang:1.22-bookworm

LABEL org.opencontainers.image.title="AutoBugBounty" \
      org.opencontainers.image.description="Recon & vulnerability scanner para bug bounty autorizado" \
      org.opencontainers.image.licenses="MIT"

# --- Dependencias del sistema ----------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl jq unzip libpcap-dev ca-certificates \
        python3 python3-pip pipx \
    && rm -rf /var/lib/apt/lists/*

ENV GOBIN=/root/go/bin
ENV PATH="/root/go/bin:/root/.local/bin:${PATH}"

# --- Herramientas en Go -----------------------------------------------------
RUN go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest && \
    go install github.com/projectdiscovery/httpx/cmd/httpx@latest           && \
    go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest             && \
    go install github.com/projectdiscovery/naabu/v2/cmd/naabu@latest        && \
    go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest      && \
    go install github.com/projectdiscovery/katana/cmd/katana@latest         && \
    go install github.com/tomnomnom/assetfinder@latest                      && \
    go install github.com/tomnomnom/waybackurls@latest                      && \
    go install github.com/lc/gau/v2/cmd/gau@latest                          && \
    go install github.com/tomnomnom/gf@latest                               && \
    go install github.com/tomnomnom/anew@latest                             && \
    go install github.com/tomnomnom/qsreplace@latest                        && \
    go install github.com/hahwul/dalfox/v2@latest                           && \
    go install github.com/PentestPad/subzy@latest

# --- Herramientas en Python -------------------------------------------------
RUN pipx install uro && pipx install subdominator && pipx install sublist3r || true

# --- findomain (binario) ----------------------------------------------------
RUN curl -sL https://github.com/findomain/findomain/releases/latest/download/findomain-linux.zip -o /tmp/f.zip && \
    unzip -o /tmp/f.zip -d /usr/local/bin && chmod +x /usr/local/bin/findomain && rm /tmp/f.zip

# --- Patrones gf + plantillas nuclei ---------------------------------------
RUN mkdir -p /root/.gf && \
    git clone -q https://github.com/1ndianl33t/Gf-Patterns /tmp/gfp && cp /tmp/gfp/*.json /root/.gf/ && \
    git clone -q https://github.com/tomnomnom/gf /tmp/gf && cp /tmp/gf/examples/*.json /root/.gf/ && \
    rm -rf /tmp/gfp /tmp/gf && \
    nuclei -update-templates -silent || true

WORKDIR /app
COPY autobb.sh /app/autobb.sh
RUN chmod +x /app/autobb.sh

ENTRYPOINT ["/app/autobb.sh"]
CMD ["--help"]
