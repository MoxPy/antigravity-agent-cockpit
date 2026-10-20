<script lang="ts">
  import { summary } from '../stores/sessionStore';
  import { viewMode } from '../stores/uiStore';
  import { toArray } from '../lib/security';
  import Icon from './Icon.svelte';

  $: totalSessionAlerts = $summary.security_alerts_count || 0;

  $: sec = $summary?.security_audit;
  $: auditSecrets = toArray(sec?.secrets);
  $: auditEscapes = toArray(sec?.boundary_escapes);
  $: auditEgress = toArray(sec?.network_egress);
  $: auditPackages = toArray(sec?.packages);
</script>

<section class="overview-metrics-strip" aria-label="Session Overview Metrics">
  <div class="metric-card metric-card-wide">
    <div class="metric-label-row">
      <div class="label-with-icon">
        <Icon name="sparkle" size={13} color="#8ab4f8" />
        <span class="metric-label">Active Request</span>
      </div>
      {#if $summary.active_turn}
        <span class="status-chip active">Turn #{$summary.active_turn.id}</span>
      {/if}
    </div>
    <div class="metric-objective-text" title={$summary.active_turn?.prompt || 'No active request'}>
      {$summary.active_turn?.prompt || 'Waiting for next request...'}
    </div>
  </div>

  <div class="metric-card">
    <div class="metric-label-row">
      <div class="label-with-icon">
        <Icon name="terminal" size={13} color="#9aa0a6" />
        <span class="metric-label">Logged Operations</span>
      </div>
    </div>
    <div class="metric-value">{$summary.total_steps || 0}</div>
    <div class="metric-subtext">across {$summary.total_turns || 0} conversation turns</div>
  </div>

  <div class="metric-card">
    <div class="metric-label-row">
      <div class="label-with-icon">
        <Icon name="edit" size={13} color="#81c995" />
        <span class="metric-label">Files Modified</span>
      </div>
    </div>
    <div class="metric-value">{$summary.files_modified?.length || 0}</div>
    <div class="metric-subtext">
      {$summary.category_counts.mutation || 0} edits recorded
    </div>
  </div>

  <div
    role="button"
    tabindex="0"
    class="metric-card card-interactive"
    class:card-alert={totalSessionAlerts > 0}
    on:click={() => $viewMode = 'audit'}
    on:keydown={(e) => { if (e.key === 'Enter') $viewMode = 'audit'; }}
    title="Open Security & Perimeter Audit"
  >
    <div class="metric-label-row">
      <div class="label-with-icon">
        <Icon name={totalSessionAlerts > 0 ? "shield-alert" : "shield-check"} size={13} color={totalSessionAlerts > 0 ? "#f28b82" : "#81c995"} />
        <span class="metric-label">Security & Perimeter</span>
      </div>
      <Icon name="external" size={12} color="#9aa0a6" />
    </div>
    <div class="metric-value" class:text-red={totalSessionAlerts > 0} class:text-green={totalSessionAlerts === 0}>
      {#if totalSessionAlerts > 0}
        {totalSessionAlerts} Alert{totalSessionAlerts > 1 ? 's' : ''}
      {:else}
        0 Incidents
      {/if}
    </div>
    <div class="metric-subtext sec-chips-subtext">
      <span class="sec-chip-sub" title="{auditSecrets.length} Credentials">
        <Icon name="key" size={10} /> {auditSecrets.length}
      </span>
      <span class="sec-chip-sub" title="{auditEscapes.length} Escapes">
        <Icon name="escape" size={10} /> {auditEscapes.length}
      </span>
      <span class="sec-chip-sub" title="{auditEgress.length} Network calls">
        <Icon name="globe" size={10} /> {auditEgress.length}
      </span>
      <span class="sec-chip-sub" title="{auditPackages.length} Packages">
        <Icon name="package" size={10} /> {auditPackages.length}
      </span>
    </div>
  </div>
</section>
