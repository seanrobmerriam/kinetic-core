/**
 * API client for operations and observability endpoints.
 */

import { api } from '../api';
import type { SLOSnapshot } from '../types/operations';

/**
 * Fetch current SLO snapshot with all objectives and alerts.
 */
export async function getSLOSnapshot(): Promise<SLOSnapshot> {
  return api<SLOSnapshot>("GET", "/operations/slo");
}

/**
 * Poll SLO snapshot with automatic retry on error.
 */
export async function pollSLOSnapshot(retries = 3): Promise<SLOSnapshot | null> {
  let lastError: Error | null = null;
  
  for (let i = 0; i < retries; i++) {
    try {
      return await getSLOSnapshot();
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      if (i < retries - 1) {
        // Exponential backoff
        await new Promise(resolve => setTimeout(resolve, Math.pow(2, i) * 100));
      }
    }
  }
  
  console.error('Failed to fetch SLO snapshot after retries:', lastError);
  return null;
}
