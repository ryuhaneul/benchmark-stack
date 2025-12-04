FROM nginx:alpine

# Install certbot and dependencies
RUN apk add --no-cache \
    certbot \
    certbot-nginx \
    bash \
    curl \
    openssl

# Create directories
RUN mkdir -p /etc/nginx/certs /var/log/nginx

# Copy configuration template
COPY nginx.conf.template /etc/nginx/templates/nginx.conf.template
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
