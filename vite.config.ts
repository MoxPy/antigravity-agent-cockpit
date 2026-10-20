import { defineConfig } from 'vite';
import { svelte, vitePreprocess } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  plugins: [
    svelte({
      preprocess: vitePreprocess(),
    }),
  ],
  clearScreen: false,
  server: {
    port: 5173,
    strictPort: true,
  },
});
