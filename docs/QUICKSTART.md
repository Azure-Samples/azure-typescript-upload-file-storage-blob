# Quick Reference - Workspace Commands

## Most Common Commands

```bash
# Development (starts both API and frontend)
npm run dev

# Production build (builds both)
npm run build

# Docker (starts both with docker-compose)
npm run docker:up:build

# Deploy to Azure
npm run deploy
```

## Installation

```bash
# Install all dependencies (root + both workspaces)
npm install

# Or install everything explicitly
npm run install:all
```

## Development Commands

| Command | What It Does |
|---------|--------------|
| `npm run dev` | Start API (3000) + Frontend (5173) concurrently |
| `npm run dev:api` | Start only API dev server |
| `npm run dev:app` | Start only frontend dev server |

## Build Commands

| Command | What It Does |
|---------|--------------|
| `npm run build` | Build both API and frontend |
| `npm run build:api` | Build only API (TypeScript → JavaScript) |
| `npm run build:app` | Build only frontend (Vite → static files) |
| `npm run clean` | Clean all build artifacts |

## Testing Commands

| Command | What It Does |
|---------|--------------|
| `npm run test:sas` | Test SAS token generation |
| `npm run check` | TypeScript type-check both workspaces |
| `npm run lint` | Lint both workspaces |
| `npm run format` | Format code with Prettier |

## Docker Commands

| Command | What It Does |
|---------|--------------|
| `npm run docker:up:build` | Build images and start containers |
| `npm run docker:up` | Start containers (use existing images) |
| `npm run docker:down` | Stop containers |
| `npm run docker:logs` | View logs from both services |
| `npm run docker:logs:api` | View only API logs |
| `npm run docker:logs:app` | View only frontend logs |
| `npm run docker:clean` | Remove containers, volumes, images |

## Deployment Commands

| Command | What It Does |
|---------|--------------|
| `npm run deploy` | Deploy all services to Azure (`azd up`) |
| `npm run logs` | View logs from Azure |
| `npm run logs:api` | View API logs from Azure Container Apps |

## Workspace Structure

```
packages/
├── package.json          ← Root workspace (you are here)
├── api/                  ← API workspace
│   └── package.json
└── app/                  ← Frontend workspace
    └── package.json
```

## How Workspaces Work

The root `package.json` defines workspaces:
```json
"workspaces": ["api", "app"]
```

This allows you to:
- Run commands in specific workspaces from root: `npm run build --workspace=api`
- Share dependencies across workspaces
- Manage all packages with one `npm install`

## Common Workflows

### First-Time Setup
```bash
npm install              # Install all dependencies
npm run setup            # Run automated setup script
npm run dev              # Start development
```

### Daily Development
```bash
npm run dev              # Start both services
# API: http://localhost:3000
# Frontend: http://localhost:5173
```

### Before Commit
```bash
npm run check            # Type-check
npm run lint             # Lint
npm run build            # Build
```

### Local Testing with Docker
```bash
npm run docker:up:build  # Build and start
# API: http://localhost:3000
# Frontend: http://localhost:8080

npm run docker:logs      # Watch logs
npm run docker:down      # Stop
```

### Deploy to Azure
```bash
npm run deploy           # One command deployment
npm run logs             # View production logs
```

## Troubleshooting

### Command not found?
Make sure you're in the root directory:
```bash
cd /workspaces/file-upload/packages
```

### Dependencies missing?
```bash
npm run clean
npm install
```

### API won't start?
```bash
az login                 # Authenticate
cat api/.env             # Check configuration
```

### Docker issues?
```bash
npm run docker:clean     # Remove everything
npm run docker:up:build  # Rebuild
```

## Environment Files

Make sure these exist:

- `api/.env` - API configuration (copy from `api/.env.sample`)
- `app/.env` - Frontend configuration (copy from `app/.env.sample`)

```bash
# API
cd api && cp .env.sample .env
# Edit: AZURE_STORAGE_ACCOUNT_NAME

# Frontend
cd ../app && cp .env.sample .env
# Edit: VITE_API_URL (default is fine for local dev)
```

## Documentation

- **[README.md](../packages/README.md)** - Full workspace documentation
- **[DEPLOYMENT.md](../packages/DEPLOYMENT.md)** - Azure deployment guide
- **[api/README.md](../packages/api/README.md)** - API documentation
- **[app/README.md](../packages/app/README.md)** - Frontend documentation

## Tips

1. **Use workspaces** - All commands can run from root
2. **Use concurrently** - `npm run dev` starts both services
3. **Use Docker Compose** - Tests the full stack locally
4. **Use `azd up`** - Deploys everything to Azure in one command

## Getting Help

```bash
# List all available scripts
npm run

# Check workspace structure
npm ls --workspace=api
npm ls --workspace=app

# Check versions
node --version
npm --version
az --version
```
