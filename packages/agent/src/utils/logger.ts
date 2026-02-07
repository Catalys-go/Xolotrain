/**
 * Structured logging using Winston
 */

import winston from "winston";
import { mkdirSync } from "fs";
import { config } from "../config";

const logFormat = winston.format.combine(
  winston.format.timestamp({ format: "HH:mm:ss MM-DD-YYYY" }),
  winston.format.errors({ stack: true }),
  winston.format.splat(),
  winston.format.json(),
);

const consoleFormat = winston.format.combine(
  winston.format.colorize(),
  winston.format.timestamp({ format: "HH:mm:ss" }),
  winston.format.printf(({ level, message, timestamp, ...metadata }) => {
    let msg = `${timestamp} [${level}]: ${message}`;

    // Add metadata if present
    const metadataKeys = Object.keys(metadata);
    if (metadataKeys.length > 0) {
      const metadataStr = JSON.stringify(metadata, null, 2);
      msg += `\n${metadataStr}`;
    }

    return msg;
  }),
);

// Create logs directory if it doesn't exist
try {
  mkdirSync("logs", { recursive: true });
} catch (error) {
  // Directory already exists
}

export const logger = winston.createLogger({
  level: config.logLevel || "info",
  format: logFormat,
  transports: [
    // Console output
    new winston.transports.Console({
      format: consoleFormat,
    }),

    // File output for all logs
    new winston.transports.File({
      filename: "logs/agent.log",
      maxsize: 10485760, // 10MB
      maxFiles: 5,
    }),

    // File output for errors only
    new winston.transports.File({
      filename: "logs/error.log",
      level: "error",
      maxsize: 10485760, // 10MB
      maxFiles: 5,
    }),
  ],
});


// Helper functions for common log patterns
export const logHealthUpdate = (data: {
  petId: string;
  oldHealth: number;
  newHealth: number;
  reason: string;
  txHash?: string;
  gasUsed?: bigint;
}) => {
  logger.info("Health update submitted", {
    type: "health_update",
    ...data,
    gasUsed: data.gasUsed?.toString(),
    timestamp: Date.now(),
  });
};

export const logError = (message: string, error: Error, context?: any) => {
  logger.error(message, {
    error: error.message,
    stack: error.stack,
    ...context,
    timestamp: Date.now(),
  });
};

export const logMonitoringCycle = (data: {
  petsChecked: number;
  updatesQueued: number;
  duration: number;
}) => {
  logger.info("Monitoring cycle complete", {
    type: "monitoring_cycle",
    ...data,
    timestamp: Date.now(),
  });
};
