require('dotenv').config();

// Initialize Application Insights if connection string is provided
if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  const appInsights = require('applicationinsights');
  appInsights.setup(process.env.APPLICATIONINSIGHTS_CONNECTION_STRING)
    .setAutoCollectRequests(true)
    .setAutoCollectPerformance(true)
    .setAutoCollectExceptions(true)
    .setAutoCollectDependencies(true)
    .setAutoCollectConsole(true)
    .setSendLiveMetrics(true)
    .start();
}

const express = require('express');
const pinoHttp = require('pino-http');
const { v4: uuidv4 } = require('uuid');
const logger = require('./logger');
const redisClient = require('./redis');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());
app.use(pinoHttp({ logger }));

// Health check endpoints
app.get('/health', async (req, res) => {
  const redisHealthy = await redisClient.healthCheck();
  const status = redisHealthy ? 'healthy' : 'degraded';
  
  res.status(redisHealthy ? 200 : 503).json({
    status,
    timestamp: new Date().toISOString(),
    checks: {
      redis: redisHealthy ? 'connected' : 'disconnected'
    }
  });
});

app.get('/ready', async (req, res) => {
  if (redisClient.getConnectionStatus()) {
    res.status(200).json({ status: 'ready' });
  } else {
    res.status(503).json({ status: 'not ready', reason: 'Redis not connected' });
  }
});

app.get('/live', (req, res) => {
  res.status(200).json({ status: 'alive' });
});

// ============================================
// Journal API Routes
// ============================================

// List all journal entries for a user
app.get('/api/journals/:userId', async (req, res) => {
  const { userId } = req.params;
  
  try {
    const entriesJson = await redisClient.get(`journal:${userId}:entries`);
    const entries = entriesJson ? JSON.parse(entriesJson) : [];
    
    logger.info({ userId, count: entries.length }, 'Retrieved journal entries');
    
    res.json({
      userId,
      entries: entries.sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt))
    });
  } catch (error) {
    logger.error({ userId, error: error.message }, 'Error retrieving journal entries');
    res.status(500).json({ error: 'Failed to retrieve journal entries' });
  }
});

// Get a specific journal entry
app.get('/api/journals/:userId/:entryId', async (req, res) => {
  const { userId, entryId } = req.params;
  
  try {
    const entryJson = await redisClient.get(`journal:${userId}:entry:${entryId}`);
    
    if (!entryJson) {
      logger.warn({ userId, entryId }, 'Journal entry not found');
      return res.status(404).json({ error: 'Entry not found' });
    }
    
    const entry = JSON.parse(entryJson);
    logger.info({ userId, entryId }, 'Retrieved journal entry');
    
    res.json(entry);
  } catch (error) {
    logger.error({ userId, entryId, error: error.message }, 'Error retrieving journal entry');
    res.status(500).json({ error: 'Failed to retrieve journal entry' });
  }
});

// Create a new journal entry
app.post('/api/journals/:userId', async (req, res) => {
  const { userId } = req.params;
  const { title, content, mood, tags } = req.body;
  
  if (!title || !content) {
    logger.warn({ userId, body: req.body }, 'Invalid journal entry - missing title or content');
    return res.status(400).json({ error: 'Title and content are required' });
  }
  
  try {
    const entryId = uuidv4();
    const now = new Date().toISOString();
    
    const entry = {
      id: entryId,
      userId,
      title,
      content,
      mood: mood || 'neutral',
      tags: tags || [],
      createdAt: now,
      updatedAt: now
    };
    
    // Store the entry
    await redisClient.set(`journal:${userId}:entry:${entryId}`, JSON.stringify(entry));
    
    // Update the entries index
    const entriesJson = await redisClient.get(`journal:${userId}:entries`);
    const entries = entriesJson ? JSON.parse(entriesJson) : [];
    entries.push({ id: entryId, title, mood, createdAt: now, updatedAt: now });
    await redisClient.set(`journal:${userId}:entries`, JSON.stringify(entries));
    
    logger.info({ userId, entryId, title }, 'Created new journal entry');
    
    res.status(201).json({
      message: 'Journal entry created',
      entry
    });
  } catch (error) {
    logger.error({ userId, error: error.message }, 'Error creating journal entry');
    res.status(500).json({ error: 'Failed to create journal entry' });
  }
});

// Update a journal entry
app.put('/api/journals/:userId/:entryId', async (req, res) => {
  const { userId, entryId } = req.params;
  const { title, content, mood, tags } = req.body;
  
  try {
    const existingJson = await redisClient.get(`journal:${userId}:entry:${entryId}`);
    
    if (!existingJson) {
      logger.warn({ userId, entryId }, 'Journal entry not found for update');
      return res.status(404).json({ error: 'Entry not found' });
    }
    
    const existing = JSON.parse(existingJson);
    const now = new Date().toISOString();
    
    const updated = {
      ...existing,
      title: title || existing.title,
      content: content || existing.content,
      mood: mood || existing.mood,
      tags: tags || existing.tags,
      updatedAt: now
    };
    
    await redisClient.set(`journal:${userId}:entry:${entryId}`, JSON.stringify(updated));
    
    // Update the entries index
    const entriesJson = await redisClient.get(`journal:${userId}:entries`);
    const entries = entriesJson ? JSON.parse(entriesJson) : [];
    const idx = entries.findIndex(e => e.id === entryId);
    if (idx !== -1) {
      entries[idx] = { id: entryId, title: updated.title, mood: updated.mood, createdAt: updated.createdAt, updatedAt: now };
      await redisClient.set(`journal:${userId}:entries`, JSON.stringify(entries));
    }
    
    logger.info({ userId, entryId }, 'Updated journal entry');
    
    res.json({
      message: 'Journal entry updated',
      entry: updated
    });
  } catch (error) {
    logger.error({ userId, entryId, error: error.message }, 'Error updating journal entry');
    res.status(500).json({ error: 'Failed to update journal entry' });
  }
});

// Delete a journal entry
app.delete('/api/journals/:userId/:entryId', async (req, res) => {
  const { userId, entryId } = req.params;
  
  try {
    await redisClient.delete(`journal:${userId}:entry:${entryId}`);
    
    // Update the entries index
    const entriesJson = await redisClient.get(`journal:${userId}:entries`);
    const entries = entriesJson ? JSON.parse(entriesJson) : [];
    const filtered = entries.filter(e => e.id !== entryId);
    await redisClient.set(`journal:${userId}:entries`, JSON.stringify(filtered));
    
    logger.info({ userId, entryId }, 'Deleted journal entry');
    
    res.json({ message: 'Journal entry deleted' });
  } catch (error) {
    logger.error({ userId, entryId, error: error.message }, 'Error deleting journal entry');
    res.status(500).json({ error: 'Failed to delete journal entry' });
  }
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  const metrics = {
    uptime: process.uptime(),
    memoryUsage: process.memoryUsage(),
    cpuUsage: process.cpuUsage(),
    redis: {
      connected: redisClient.getConnectionStatus()
    },
    timestamp: new Date().toISOString()
  };
  
  res.json(metrics);
});

// Error handling middleware
app.use((err, req, res, next) => {
  logger.error({
    error: err.message,
    stack: err.stack,
    url: req.url,
    method: req.method
  }, 'Unhandled error');
  
  res.status(500).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// Graceful shutdown
const gracefulShutdown = async (signal) => {
  logger.info({ signal }, 'Received shutdown signal');
  
  try {
    await redisClient.disconnect();
    logger.info('Graceful shutdown completed');
    process.exit(0);
  } catch (error) {
    logger.error({ error: error.message }, 'Error during graceful shutdown');
    process.exit(1);
  }
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Start server
const startServer = async () => {
  try {
    await redisClient.connect();
    logger.info('Redis connection established');
  } catch (error) {
    // Don't exit - start server anyway in degraded mode
    logger.error({ error: error.message }, 'Failed to connect to Redis - starting in degraded mode');
  }
  
  app.listen(PORT, () => {
    logger.info({ port: PORT }, 'Journal app started successfully');
  });
};

startServer();
