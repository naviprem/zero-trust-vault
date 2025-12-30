# Build stage
FROM node:20-alpine as build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Production stage
FROM nginx:1.25-alpine
COPY --from=build /app/dist /usr/share/nginx/html
# Copy custom nginx config if needed, or use default
COPY <<EOF /etc/nginx/conf.d/default.conf
server {
    listen 80;
    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
    location /api/ {
        # Proxy to local Envoy sidecar which establishes mTLS to backend
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Authorization \$http_authorization;
    }

    location /realms/ {
        # Proxy to Keycloak
        proxy_pass http://keycloak.zero-trust-infra.svc.cluster.local:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
