# Start from a base Ubuntu image
FROM ubuntu:22.04

# Set non-interactive mode
ENV DEBIAN_FRONTEND=noninteractive

# Update Ubuntu and install Nginx
RUN apt-get update && \
    apt-get install -y nginx

# Remove the default Nginx welcome page
RUN rm /var/www/html/index.nginx-debian.html

# Copy your application files to the Nginx web root
COPY . /var/www/html/

# Run Nginx in the foreground
CMD ["nginx", "-g", "daemon off;"]