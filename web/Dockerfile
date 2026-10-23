FROM node:20.18.0-alpine AS base

WORKDIR /app

# Install curl for healthcheck and tzdata
RUN apk add --no-cache curl tzdata && rm -rf /var/cache/apk/*
ENV TZ=Asia/Ho_Chi_Minh

# Install dependencies
COPY package*.json ./
RUN npm install --omit=dev --no-audit --no-fund && npm cache clean --force

# Copy application source
COPY --chown=node:node . .

# Ensure upload directory exists and is owned by unprivileged node user
RUN mkdir -p public/uploads && chown -R node:node /app/public/uploads && chmod 755 /app/public/uploads

# Switch to unprivileged user
USER node

EXPOSE 3000
ENV PORT=3000 NODE_ENV=production

CMD ["node", "src/server.js"]
