/**
 * Health Calculator - Deterministic health formula for LP positions
 *
 * Health is based on whether the position is in-range or out-of-range.
 * In-range positions earn fees (healthy), out-of-range positions don't (unhealthy).
 */

/** How close the position is to being at the range edges */
export interface PositionState {
  currentTick: number;
  tickLower: number;
  tickUpper: number;
  liquidity: bigint;
}

/** Health status categories matching game design visual states */
export enum HealthStatus {
  HEALTHY = "HEALTHY",     // 80-100: 🟢 Happy, animated, vibrant
  ALERT = "ALERT",         // 50-79:  🟡 Alert, slower animation
  SAD = "SAD",             // 20-49:  🟠 Sad, sluggish, dimmed
  CRITICAL = "CRITICAL"    // 0-19:   🔴 Critical, barely moving
}

/**
 * Calculate health score (0-100) based on LP position state
 *
 * Formula:
 * - In range: 100 (healthy, earning fees)
 * - Out of range: Degrades based on distance from range
 *
 * @param currentTick - Current tick of the pool
 * @param tickLower - Lower bound of position range
 * @param tickUpper - Upper bound of position range
 * @returns Health score between 0 and 100
 */
export function calculateHealth(
  currentTick: number,
  tickLower: number,
  tickUpper: number,
  penaltyMultiplier: number = 2, // Configurable per design
): number {
  // Validate inputs
  if (tickLower >= tickUpper) {
    throw new Error(
      `Invalid tick range: tickLower (${tickLower}) >= tickUpper (${tickUpper})`,
    );
  }

  // Check if position is in range
  const inRange = currentTick >= tickLower && currentTick <= tickUpper;

  if (inRange) {
    // Position is earning fees - perfect health
    return 100;
  }

  // Position is out of range - calculate health penalty
  const tickRange = tickUpper - tickLower;

  // Distance from nearest edge of range
  const distanceFromRange = Math.min(
    Math.abs(currentTick - tickLower),
    Math.abs(currentTick - tickUpper),
  );

  // Health decreases proportionally to distance
  // Uses configurable penalty multiplier (default: 2)
  const healthPenalty =
    (distanceFromRange / tickRange) * 100 * penaltyMultiplier;

  // Clamp to [0, 100] as per game design
  const health = Math.max(0, Math.min(100, 100 - healthPenalty));

  return Math.floor(health); // Return integer for consistency
}

/**
 * Calculate health with additional context
 * Returns both health score and reason
 */
export function calculateHealthWithReason(
  currentTick: number,
  tickLower: number,
  tickUpper: number,
  penaltyMultiplier: number = 2,
): { health: number; reason: string; inRange: boolean } {
  const health = calculateHealth(currentTick, tickLower, tickUpper, penaltyMultiplier);
  const inRange = currentTick >= tickLower && currentTick <= tickUpper;

  let reason: string;
  if (inRange) {
    reason = "position_in_range";
  } else if (currentTick < tickLower) {
    reason = "position_below_range";
  } else {
    reason = "position_above_range";
  }

  return { health, reason, inRange };
}

/**
 * Get health status category based on health value
 * Matches game design visual states
 * 
 * @param health - Health value (0-100)
 * @returns HealthStatus enum value
 */
export function getHealthStatus(health: number): HealthStatus {
  if (health >= 80) return HealthStatus.HEALTHY;
  if (health >= 50) return HealthStatus.ALERT;
  if (health >= 20) return HealthStatus.SAD;
  return HealthStatus.CRITICAL;
}

/**
 * Check if health change is significant enough to warrant update
 *
 * @param oldHealth - Previous health value
 * @param newHealth - New calculated health value
 * @param threshold - Minimum change required (default: 5)
 * @returns true if health changed by >= threshold
 */
export function shouldUpdateHealth(
  oldHealth: number,
  newHealth: number,
  threshold: number = 5,
): boolean {
  return Math.abs(newHealth - oldHealth) >= threshold;
}
