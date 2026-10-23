FROM node:20.14.0-alpine AS base

WORKDIR /app

# Install curl for healthcheck and tzdata
RUN apk add --no-cache curl tzdata
ENV TZ=Asia/Ho_Chi_Minh

# Install dependencies
COPY package*.json ./
RUN npm install --omit=dev --no-audit --no-fund && npm cache clean --force

# Copy application source
COPY . .

# Ensure upload directory exists and has permissions
RUN mkdir -p public/uploads && chmod 777 public/uploads

EXPOSE 3000
ENV PORT=3000 NODE_ENV=production

CMD ["node", "src/server.js"]