/**
 * Types for operations dashboard and SLO/health data structures.
 */

export interface SLOObjective {
  id: string;
  sli: 'availability' | 'dependency_health' | 'latency';
  status: 'healthy' | 'breached' | 'insufficient_data';
  target_pct?: number;
  target_status?: string;
  description: string;
  value: SLOObjectiveValue;
}

export interface SLOObjectiveValue {
  availability_pct?: number;
  total_requests?: number;
  error_5xx?: number;
  dependency_status?: 'ok' | 'degraded' | 'unhealthy';
  max_latency_ms?: number;
  checks?: DependencyCheck[];
}

export interface DependencyCheck {
  name: string;
  status: 'ok' | 'degraded' | 'unhealthy';
  latency_ms: number;
  message?: string;
}

export interface SLOAlert {
  alert_id: string;
  objective: string;
  severity: 'info' | 'warning' | 'critical';
  state: 'firing' | 'resolved' | 'monitoring';
  message: string;
}

export interface SLOSnapshot {
  generated_at_ms: number;
  objectives: SLOObjective[];
  alerts: SLOAlert[];
}

export type HealthStatus = 'healthy' | 'degraded' | 'unhealthy' | 'unknown';
export type AlertSeverity = 'info' | 'warning' | 'critical';
