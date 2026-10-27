import { build, loadConfigFromFile } from '../frontend/node_modules/vite/dist/node/index.js'

const loaded = await loadConfigFromFile(
  { command: 'build', mode: 'production' },
  '/app/frontend/vite.config.ts',
  '/app/frontend',
)
if (!loaded) throw new Error('Could not load the frontend build configuration')

// Type checking runs separately. Avoid starting a second large process on the VPS.
const plugins = loaded.config.plugins.filter((plugin) => plugin?.name !== 'vite-plugin-checker')
await build({ ...loaded.config, configFile: false, plugins })
