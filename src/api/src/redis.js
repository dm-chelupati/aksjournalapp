const redis = require('redis');
const logger = require('./logger');

class RedisClient {
  constructor() {
    this.client = null;
    this.isConnected = false;
  }

  async connect() {
    const redisHost = process.env.REDIS_HOST || 'localhost';
    const redisPort = process.env.REDIS_PORT || 6379;
    const redisPassword = process.env.REDIS_PASSWORD || '';
    const useTls = process.env.REDIS_TLS === 'true';

    const connectionOptions = {
      socket: {
        host: redisHost,
        port: parseInt(redisPort),
        tls: useTls,
        reconnectStrategy: (retries) => {
          if (retries > 10) {
            logger.error({ retries }, 'Max Redis reconnection attempts reached');
            return new Error('Max reconnection attempts reached');
          }
          const delay = Math.min(retries * 100, 3000);
          logger.warn({ retries, delay }, 'Attempting Redis reconnection');
          return delay;
        }
      }
    };

    if (redisPassword) {
      connectionOptions.password = redisPassword;
    }

    this.client = redis.createClient(connectionOptions);

    // Event handlers for monitoring
    this.client.on('connect', () => {
      logger.info({ host: redisHost, port: redisPort }, 'Redis client connecting');
    });

    this.client.on('ready', () => {
      this.isConnected = true;
      logger.info({ host: redisHost, port: redisPort }, 'Redis client connected and ready');
    });

    this.client.on('error', (err) => {
      this.isConnected = false;
      logger.error({ error: err.message, stack: err.stack }, 'Redis client error');
    });

    this.client.on('end', () => {
      this.isConnected = false;
      logger.warn('Redis client disconnected');
    });

    try {
      await this.client.connect();
      logger.info('Redis connection established successfully');
    } catch (error) {
      logger.error({ error: error.message }, 'Failed to connect to Redis');
      throw error;
    }
  }

  async get(key) {
    const startTime = Date.now();
    try {
      const value = await this.client.get(key);
      const duration = Date.now() - startTime;
      logger.debug({ key, duration, hit: value !== null }, 'Redis GET operation');
      return value;
    } catch (error) {
      logger.error({ key, error: error.message }, 'Redis GET error');
      throw error;
    }
  }

  async set(key, value, ttlSeconds = 3600) {
    const startTime = Date.now();
    try {
      await this.client.set(key, value, { EX: ttlSeconds });
      const duration = Date.now() - startTime;
      logger.debug({ key, duration, ttl: ttlSeconds }, 'Redis SET operation');
    } catch (error) {
      logger.error({ key, error: error.message }, 'Redis SET error');
      throw error;
    }
  }

  async delete(key) {
    const startTime = Date.now();
    try {
      await this.client.del(key);
      const duration = Date.now() - startTime;
      logger.debug({ key, duration }, 'Redis DELETE operation');
    } catch (error) {
      logger.error({ key, error: error.message }, 'Redis DELETE error');
      throw error;
    }
  }

  async healthCheck() {
    try {
      const result = await this.client.ping();
      return result === 'PONG';
    } catch (error) {
      logger.error({ error: error.message }, 'Redis health check failed');
      return false;
    }
  }

  getConnectionStatus() {
    return this.isConnected;
  }

  async disconnect() {
    if (this.client) {
      await this.client.quit();
      logger.info('Redis client disconnected gracefully');
    }
  }
}

module.exports = new RedisClient();
