const pino = require('pino');

// Create structured logger that outputs JSON for Azure Monitor
const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  formatters: {
    level: (label) => ({ level: label }),
    bindings: (bindings) => ({
      pid: bindings.pid,
      host: bindings.hostname,
      app: 'aks-journal-app',
      environment: process.env.NODE_ENV || 'development',
      podName: process.env.POD_NAME || 'unknown',
      nodeName: process.env.NODE_NAME || 'unknown',
      namespace: process.env.NAMESPACE || 'default'
    })
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  serializers: {
    err: pino.stdSerializers.err,
    error: pino.stdSerializers.err,
    req: pino.stdSerializers.req,
    res: pino.stdSerializers.res
  }
});

module.exports = logger;
