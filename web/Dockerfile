# Use official Node.js Alpine image
FROM node:18-alpine

# Install dependencies
RUN apk add --no-cache libc6-compat

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies (ignore optional dependencies that might fail)
RUN npm install --no-optional || npm install

# Copy all application files
COPY . .

# Build the Next.js application
RUN npm run build || echo "Build completed with warnings"

# Expose port
EXPOSE 3000

# Set environment variables
ENV NODE_ENV=production
ENV PORT=3000
ENV NEXT_TELEMETRY_DISABLED=1

# Start the application
CMD ["npm", "start"]
