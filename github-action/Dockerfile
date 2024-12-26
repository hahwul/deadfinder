# Use the deadfinder base image from GitHub Container Registry
FROM ghcr.io/hahwul/deadfinder:1.5.1

# Install jq for JSON processing
RUN apt-get update && apt-get install -y jq

# Copy the entrypoint script into the container
COPY entrypoint.sh /entrypoint.sh

# Make the entrypoint script executable
RUN chmod 755 /entrypoint.sh

# Set the entrypoint to the script
ENTRYPOINT ["/entrypoint.sh"]