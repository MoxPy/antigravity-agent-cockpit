<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import Header from './components/Header.svelte';
  import TurnSituationView from './components/TurnSituationView.svelte';
  import GranularLogView from './components/GranularLogView.svelte';
  import SecurityAuditView from './components/SecurityAuditView.svelte';
  import ReportVaultModal from './components/ReportVaultModal.svelte';
  import { initSession, pollSession } from './stores/sessionStore';
  import { viewMode } from './stores/uiStore';

  let pollInterval: any = null;

  onMount(() => {
    initSession();
    pollInterval = setInterval(pollSession, 1500);
  });

  onDestroy(() => {
    if (pollInterval) {
      clearInterval(pollInterval);
      pollInterval = null;
    }
  });
</script>

<svg style="position: absolute; width: 0; height: 0; overflow: hidden; pointer-events: none;" aria-hidden="true">
  <defs>
    <linearGradient id="g-gemini-gradient" x1="2" y1="2" x2="22" y2="22" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#4285F4" />
      <stop offset="50%" stop-color="#9B72CB" />
      <stop offset="100%" stop-color="#D96570" />
    </linearGradient>
  </defs>
</svg>

<div class="cockpit-container">
  <Header />

  {#if $viewMode === 'turns'}
    <TurnSituationView />
  {:else if $viewMode === 'log'}
    <GranularLogView />
  {:else if $viewMode === 'audit'}
    <SecurityAuditView />
  {/if}
</div>

<ReportVaultModal />
