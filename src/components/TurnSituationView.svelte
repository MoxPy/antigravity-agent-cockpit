<script lang="ts">
  import MetricCards from './MetricCards.svelte';
  import TurnsNavigator from './TurnsNavigator.svelte';
  import TurnCanvas from './TurnCanvas.svelte';
  import StepInspector from './StepInspector.svelte';
  import { showTurnsNav, showInspector } from '../stores/uiStore';
</script>

<div class="turn-situation-view-wrapper">
  <!-- High-level Metric Cards Strip (Dedicated ONLY to Turn Situation View) -->
  <MetricCards />

  <!-- Master-Detail 3-Column Situation Layout -->
  <main
    class="turn-situation-layout"
    class:nav-closed={!$showTurnsNav}
    class:inspector-closed={!$showInspector}
  >
    {#if $showTurnsNav}
      <TurnsNavigator />
    {/if}

    <TurnCanvas />

    {#if $showInspector}
      <StepInspector />
    {/if}
  </main>
</div>
