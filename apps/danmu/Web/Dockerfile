FROM node:24-bookworm-slim@sha256:d6aa754f16b3197301076f047b5def2f02ea1dbbc2ca920407d46d7ec7f87b20
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && mkdir -p /opt/lark /data && chown node:node /data && chmod 700 /data
RUN curl -fsSL https://registry.npmmirror.com/-/binary/lark-cli/v1.0.96/lark-cli-1.0.96-linux-amd64.tar.gz -o /tmp/lark.tar.gz && echo '5d1fa96832307b13298fdb11c477ab3f31c3e98026fec585b4b2eb7f63960c36  /tmp/lark.tar.gz' | sha256sum -c - && tar -xzf /tmp/lark.tar.gz -C /opt/lark && chmod +x /opt/lark/lark-cli
COPY --chown=node:node . /app
ENV HOME=/data XDG_CONFIG_HOME=/data/.config LARK_BINARY=/opt/lark/lark-cli
USER node
CMD ["node","server.cjs"]
