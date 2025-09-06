/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  swcMinify: true,
  experimental: {
    appDir: true,
  },
  env: {
    MQTT_BROKER_URL: process.env.MQTT_BROKER_URL || 'ws://localhost:9001',
  },
}

module.exports = nextConfig
