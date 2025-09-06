FROM alpine:latest

# Install required packages
RUN apk add --no-cache \
    git \
    docker-cli \
    docker-compose \
    bash \
    curl \
    jq

# Create working directory
WORKDIR /updater

# Copy update script
COPY update-service.sh /updater/update-service.sh
RUN chmod +x /updater/update-service.sh

# Run the update service
CMD ["/updater/update-service.sh"]
