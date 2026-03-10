FROM ubuntu:22.04

# Install Java
RUN apt-get update && apt-get install -y default-jre curl && rm -rf /var/lib/apt/lists/*

# Copy CP Gateway from host
COPY ibkr-cpgw/ /opt/cp-gateway/

WORKDIR /opt/cp-gateway

# Expose port 5000
EXPOSE 5000

# Start CP Gateway
CMD ["./bin/run.sh", "root/conf.yaml"]
