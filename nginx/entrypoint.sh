#!/bin/bash
set -e

DOMAIN="${DOMAIN:-localhost}"
ACME_EMAIL="${ACME_EMAIL:-admin@example.com}"
USE_LETSENCRYPT="${USE_LETSENCRYPT:-false}"
USE_ACME_DNS="${USE_ACME_DNS:-false}"

echo "🔧 Starting Nginx configuration..."
echo "📋 Domain: $DOMAIN"
echo "📧 ACME Email: $ACME_EMAIL"
echo "🔐 Let's Encrypt: $USE_LETSENCRYPT"

# Create necessary directories
mkdir -p /etc/nginx/certs
mkdir -p /var/www/certbot

# Replace environment variables in nginx config
envsubst '${DOMAIN}' < /etc/nginx/templates/nginx.conf.template > /etc/nginx/nginx.conf

# Check if certificates exist
if [ -f "/etc/nginx/certs/fullchain.pem" ] && [ -f "/etc/nginx/certs/privkey.pem" ]; then
    echo "✅ SSL certificates already exist"
else
    echo "⚠️  No SSL certificates found"
    
    # 기본적으로 자체 서명 인증서 생성
    if [ "$USE_LETSENCRYPT" != "true" ]; then
        echo "🔐 Generating self-signed certificate..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/nginx/certs/privkey.pem \
            -out /etc/nginx/certs/fullchain.pem \
            -subj "/C=US/ST=State/L=City/O=Development/CN=$DOMAIN"
        echo "✅ Self-signed certificate created for $DOMAIN"
    else
        # Let's Encrypt 인증서 발급 시도
        echo "🌐 Attempting to obtain Let's Encrypt certificate for $DOMAIN..."
        
        if [ "$USE_ACME_DNS" = "true" ]; then
            echo "⚠️  DNS-01 challenge requires manual configuration"
            echo "   1. Register at acme-dns service"
            echo "   2. Add CNAME record: _acme-challenge.$DOMAIN -> <acme-dns-subdomain>"
            echo "   3. Set ACME_DNS_API_URL and ACME_DNS_USERNAME/PASSWORD in .env"
            echo ""
            echo "🔐 Using self-signed certificate for now..."
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /etc/nginx/certs/privkey.pem \
                -out /etc/nginx/certs/fullchain.pem \
                -subj "/C=US/ST=State/L=City/O=Development/CN=$DOMAIN"
        else
            # HTTP-01 challenge
            echo "🌐 Using HTTP-01 challenge"
            
            # Start nginx temporarily for challenge
            nginx
            sleep 2
            
            # Try to obtain certificate
            certbot certonly --webroot -w /var/www/certbot \
                --email $ACME_EMAIL \
                --agree-tos \
                --no-eff-email \
                --non-interactive \
                -d $DOMAIN && {
                    # Stop temporary nginx
                    nginx -s stop || true
                    sleep 1
                    
                    # Link Let's Encrypt certificates
                    if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
                        ln -sf /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/nginx/certs/fullchain.pem
                        ln -sf /etc/letsencrypt/live/$DOMAIN/privkey.pem /etc/nginx/certs/privkey.pem
                        echo "✅ Let's Encrypt certificate obtained and linked"
                    fi
                } || {
                    # Failed to obtain certificate
                    echo "❌ Failed to obtain Let's Encrypt certificate"
                    echo "🔐 Falling back to self-signed certificate..."
                    
                    # Stop temporary nginx
                    nginx -s stop || true
                    sleep 1
                    
                    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                        -keyout /etc/nginx/certs/privkey.pem \
                        -out /etc/nginx/certs/fullchain.pem \
                        -subj "/C=US/ST=State/L=City/O=Development/CN=$DOMAIN"
                    echo "✅ Self-signed certificate created"
                }
        fi
    fi
fi

# Test nginx configuration
echo "🧪 Testing Nginx configuration..."
nginx -t

echo "✅ Nginx configuration complete"
echo "🚀 Starting Nginx..."

# Execute the main command
exec "$@"
