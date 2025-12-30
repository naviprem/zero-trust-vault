FROM node:20-alpine

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci --only=production

# Copy application and fix permissions
COPY server.js ./
RUN chmod 644 server.js && chown -R node:node /app

# Run as non-root
USER node

EXPOSE 3000

CMD ["node", "server.js"]
