/**
 * Retry utility for resilient RPC calls
 */

export interface RetryOptions {
  maxAttempts: number;
  delayMs: number;
  onRetry?: (attempt: number, error: Error) => void;
}

/**
 * Retry an async function with linear backoff (delayMs * attempt)
 *
 * @param fn - Async function to retry
 * @param options - Retry configuration
 * @returns Promise resolving to function result
 * @throws Last error if all attempts fail
 */
export async function retryAsync<T>(
  fn: () => Promise<T>,
  options: RetryOptions,
): Promise<T> {
  // Validate maxAttempts
  if (options.maxAttempts < 1) {
    throw new Error('retryAsync: maxAttempts must be at least 1');
  }

  let lastError: Error | undefined;

  for (let attempt = 1; attempt <= options.maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      // Normalize to Error object (handles non-Error throws)
      lastError = error instanceof Error 
        ? error 
        : new Error(String(error));

      if (attempt < options.maxAttempts) {
        options.onRetry?.(attempt, lastError);
        await new Promise((resolve) =>
          setTimeout(resolve, options.delayMs * attempt),
        );
      }
    }
  }

  // Fallback error (should never happen with validation above, but safe)
  throw lastError ?? new Error('retryAsync: exhausted all retry attempts');
}
