export type EventCategory = 'terminal' | 'mutation' | 'inspect' | 'thought' | 'user' | 'response' | 'info';

export type RiskLevel = 'safe' | 'low' | 'medium' | 'high' | 'critical';

export interface SecretFinding {
  type: string;
  preview: string;
}

export interface NetworkEgress {
  type: string;
  destination: string;
}

export interface PackageInstalled {
  manager: string;
  package: string;
}

export interface InjectionFindingItem {
  step: number;
  turn_id: number;
  type: string;
  severity: string;
  source: string;
  target?: string;
  snippet: string;
  timestamp?: string;
}

export interface EventItem {
  step: number;
  turn_id?: number;
  timestamp: string;
  status: string;
  source: string;
  raw_type: string;
  category: EventCategory;
  title: string;
  summary: string;
  details: string;
  target?: string;
  cwd?: string;
  command?: string;
  thinking?: string;
  tool?: string;
  risk_level?: RiskLevel;
  risk_reasons?: string[];
  secret_findings?: SecretFinding[];
  is_boundary_escape?: boolean;
  boundary_escape_reason?: string;
  network_egress?: NetworkEgress;
  package_installed?: PackageInstalled;
  injection_finding?: InjectionFindingItem;
}

export interface TurnItem {
  id: number;
  prompt: string;
  raw_prompt?: string;
  preview?: string;
  timestamp: string;
  ended_at?: string;
  duration_seconds?: number;
  duration_str?: string;
  status: 'in_progress' | 'completed';
  events_count: number;
  files_modified_list: string[];
  command_count: number;
  mutation_count: number;
  inspect_count: number;
  thought_count: number;
  security_alerts_count?: number;
  high_risk_count?: number;
  latest_thought?: string;
  events: EventItem[];
}

export interface RadarRepo {
  name: string;
  branch: string;
  modified_files: number;
}

export interface ReportItem {
  filename: string;
  filepath: string;
  size_kb: number;
  date: string;
}

export interface SecretAuditItem {
  step: number;
  turn_id: number;
  type: string;
  preview: string;
}

export interface BoundaryEscapeItem {
  step: number;
  turn_id: number;
  reason: string;
  cwd?: string;
  target?: string;
}

export interface NetworkEgressItem {
  step: number;
  turn_id: number;
  type: string;
  destination: string;
  timestamp: string;
}

export interface PackageItem {
  step: number;
  turn_id: number;
  manager: string;
  package: string;
  timestamp: string;
}

export interface SecurityAuditData {
  secrets: SecretAuditItem[];
  boundary_escapes: BoundaryEscapeItem[];
  network_egress: NetworkEgressItem[];
  packages: PackageItem[];
  injections: InjectionFindingItem[];
}

export interface SummaryData {
  total_steps: number;
  total_turns: number;
  session_uuid: string;
  category_counts: Record<string, number>;
  total_thoughts: number;
  security_alerts_count?: number;
  high_risk_count?: number;
  security_audit?: SecurityAuditData;
  turns: TurnItem[];
  active_turn: TurnItem | null;
  files_modified: string[];
  recent_events: EventItem[];
  workspace_root?: string;
}

export interface SessionInfo {
  session_uuid: string;
  short_id: string;
  total_steps: number;
  preview: string;
  is_active: boolean;
  is_live: boolean;
}

export type ViewMode = 'turns' | 'log' | 'audit';
