# ================================
#  Stage 1 — Builder
# ================================
FROM node:20-alpine AS builder
WORKDIR /app

# Install Prisma musl requirements
RUN apk add --no-cache openssl libc6-compat

# Install all dependencies
COPY package*.json ./
RUN npm install

# Copy all project files
COPY . .

# Generate Prisma Client
RUN npx prisma generate

# Build TS → JS
RUN npm run build

# ================================
#  Stage 2 — Runtime
# ================================
FROM node:20-alpine AS runtime
WORKDIR /app

# Install Prisma runtime dependencies
RUN apk add --no-cache openssl libc6-compat

# Copy ONLY production dependencies
COPY package*.json ./
RUN npm ci --only=production

# Copy built output + prisma + generated client
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/tsconfig.json ./tsconfig.json

# Copy production env
COPY .env.production ./.env

EXPOSE 4001
CMD ["npm", "start"]
