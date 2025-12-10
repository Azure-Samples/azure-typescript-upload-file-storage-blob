# Frontend App v2 - React with Vite

This is the v2 frontend application built with React, Vite, and Material-UI. It connects to the Fastify API (v2) for file upload functionality.

## Features

- **File Upload**: Upload files to Azure Blob Storage using SAS tokens
- **File Listing**: Display uploaded files from blob storage
- **Image Preview**: Preview uploaded images (jpg, png, gif, jpeg)
- **Material-UI**: Modern, responsive UI components
- **Vite**: Fast development and optimized production builds

## Prerequisites

- Node.js 18 or later
- API server running (see `../api/README.md`)

## Local Development

### 1. Install Dependencies

```bash
cd azure-upload-file-storage/app
npm install
```

### 2. Configure Environment

```bash
cp .env.sample .env
```

Edit `.env` to set the API URL:

```env
# Local development
VITE_API_URL=http://localhost:3000

# Or production API
VITE_API_URL=https://your-api.azurecontainerapps.io
```

### 3. Start Development Server

**Option A: Development Mode (with watch)**
```bash
npm run dev
```

The app will be available at http://localhost:5173

**Option B: Production Preview**
```bash
npm run build
npm run preview
```

The app will be available at http://localhost:4173

### 4. Test with API

Ensure the API server is running first:

```bash
# In another terminal
cd ../api
npm run dev
```

Then:
1. Open http://localhost:5173 in your browser
2. Click "Select File" and choose a file
3. Click "Get SAS Token" - should display a SAS URL
4. Click "Upload" - should upload the file
5. Uploaded files appear in the grid below

## Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `VITE_API_URL` | URL of the Fastify API server | `http://localhost:3000` | Yes |

**Note**: All Vite environment variables must start with `VITE_` to be exposed to the client.

## Build for Production

```bash
npm run build
```

This creates an optimized production build in the `dist/` directory.

### Build Output

```
dist/
├── index.html          # Entry point
├── assets/
│   ├── index-*.js      # Main JavaScript bundle
│   ├── index-*.css     # Compiled CSS
│   └── *.woff2         # Font files
└── vite.svg            # App icon
```

## Docker Build

Build the Docker image:

```bash
docker build -t upload-app .
```

Run the container:

```bash
docker run -p 8080:8080 upload-app
```

The app will be available at http://localhost:8080

### Docker Environment Variables

To set the API URL at runtime:

```bash
# Build with environment variable
docker build \
  --build-arg VITE_API_URL=https://your-api.azurecontainerapps.io \
  -t upload-app .

# Run the container
docker run -p 8080:8080 upload-app
```

## Project Structure

```
app/
├── src/
│   ├── App.tsx              # Main application component
│   ├── App.css              # Application styles
│   ├── main.tsx             # React entry point
│   ├── components/
│   │   └── error-boundary.tsx  # Error boundary component
│   └── lib/
│       └── convert-file-to-arraybuffer.ts  # File conversion utility
├── public/                  # Static assets
├── Dockerfile               # Container image definition
├── nginx.conf               # Nginx server configuration
├── vite.config.ts           # Vite build configuration
├── vite.config.dev.ts       # Vite dev server configuration
├── tsconfig.json            # TypeScript configuration
├── package.json             # Dependencies and scripts
├── .env                     # Local environment variables (not committed)
└── .env.sample              # Environment template
```

## Scripts

| Script | Description |
|--------|-------------|
| `npm run dev` | Start development server with hot reload |
| `npm start` | Build and start preview server |
| `npm run build` | Build for production |
| `npm run preview` | Preview production build |
| `npm run compile` | Type-check TypeScript |
| `npm run lint` | Lint TypeScript/React code |
| `npm run format` | Format code with Prettier |
| `npm run clean` | Remove dist directory |

## Key Changes from v1

| Feature | v1 (Azure Functions) | v2 (Fastify) |
|---------|---------------------|--------------|
| **API URL Config** | `VITE_API_SERVER` | `VITE_API_URL` |
| **SAS Endpoint** | `POST /api/sas` | `GET /api/sas` |
| **Default Token Duration** | 5 minutes | 10 minutes |
| **Environment File** | `.env` (varies) | `.env` with clear structure |
| **CORS** | Managed Functions CORS | Fastify CORS middleware |

### Migration Checklist

If migrating from v1:

- [x] Update environment variable from `VITE_API_SERVER` to `VITE_API_URL`
- [x] Change SAS token request from `POST` to `GET`
- [x] Update default token duration from 5 to 10 minutes
- [x] Ensure API URL in `.env` matches your Fastify API server
- [x] Test file upload flow end-to-end

## API Integration

### SAS Token Generation

```typescript
// GET /api/sas?file=test.txt&permission=w&container=upload&timerange=10
const url = `${API_URL}/api/sas?` +
  `file=${encodeURIComponent(filename)}` +
  `&permission=w` +
  `&container=upload` +
  `&timerange=10`;

const response = await fetch(url, { method: 'GET' });
const data = await response.json();
// data.url contains the SAS URL
```

### File Listing

```typescript
// GET /api/list?container=upload
const url = `${API_URL}/api/list?container=upload`;

const response = await fetch(url);
const data = await response.json();
// data.list contains array of blob URLs
```

## Troubleshooting

### CORS Errors

**Symptom**: Browser console shows CORS errors when calling API

**Solution**: Ensure the API server has CORS configured for your frontend URL:

```bash
# In API .env
FRONTEND_URL=http://localhost:5173
```

For production, set to your Static Web App URL:

```bash
FRONTEND_URL=https://your-app.azurestaticapps.net
```

### Environment Variables Not Working

**Symptom**: `import.meta.env.VITE_API_URL` is `undefined`

**Solutions**:
1. Ensure variable name starts with `VITE_`
2. Restart dev server after changing `.env`
3. Check `.env` file exists and has correct syntax
4. For Docker builds, pass as build arg:
   ```bash
   docker build --build-arg VITE_API_URL=http://api:3000 -t app .
   ```

### API Connection Refused

**Symptom**: `Failed to fetch` or `Connection refused`

**Solutions**:
1. Verify API server is running: `curl http://localhost:3000/health`
2. Check `VITE_API_URL` in `.env` matches API server address
3. For Docker, use host network or container network:
   ```bash
   docker run --network host upload-app
   ```

### Build Fails

**Symptom**: TypeScript compilation errors

**Solutions**:
1. Ensure Node.js version ≥18: `node --version`
2. Clean install dependencies:
   ```bash
   rm -rf node_modules package-lock.json
   npm install
   ```
3. Type-check: `npm run compile`

## Testing

### Manual Testing Checklist

- [ ] App loads without console errors
- [ ] File selection opens file picker
- [ ] Selected file name displays
- [ ] "Get SAS Token" button generates token
- [ ] SAS URL displays in UI
- [ ] "Upload" button uploads file
- [ ] Success message appears after upload
- [ ] Uploaded file appears in grid
- [ ] Images display with preview
- [ ] Non-images show filename

### Browser Compatibility

Tested on:
- ✅ Chrome 120+
- ✅ Firefox 120+
- ✅ Safari 17+
- ✅ Edge 120+

## Deployment

### Azure Static Web Apps

Deploy using Azure Developer CLI:

```bash
# From project root
azd up
```

This will:
1. Build the React app (`npm run build`)
2. Deploy `dist/` to Azure Static Web Apps
3. Configure the Static Web App to proxy API requests to Container Apps

### Manual Deployment

Build the app:

```bash
npm run build
```

Deploy `dist/` folder to your preferred hosting:
- Azure Static Web Apps
- Azure Storage Static Website
- GitHub Pages
- Netlify
- Vercel

**Remember**: Set `VITE_API_URL` environment variable to your production API URL before building!

## Dependencies

### Production

- **react** ^18.2.0 - React library
- **react-dom** ^18.2.0 - React DOM renderer
- **@mui/material** ^5.14.2 - Material-UI components
- **@emotion/react** ^11.11.1 - CSS-in-JS library
- **@emotion/styled** ^11.11.0 - Styled components
- **@azure/storage-blob** ^12.14.0 - Azure Blob Storage client

### Development

- **vite** ^4.4.0 - Build tool and dev server
- **typescript** ^5.0.2 - TypeScript compiler
- **@vitejs/plugin-react** ^4.0.1 - Vite React plugin
- **eslint** ^9.20.1 - Linter
- **prettier** ^3.0.0 - Code formatter

## Security

### Content Security Policy

Nginx configuration includes security headers:
- `X-Frame-Options: SAMEORIGIN` - Prevent clickjacking
- `X-Content-Type-Options: nosniff` - Prevent MIME sniffing
- `X-XSS-Protection: 1; mode=block` - XSS protection
- `Referrer-Policy: no-referrer-when-downgrade` - Referrer control

### File Upload Security

- File size limit: 256 KB (configurable in `App.tsx`)
- Only uploads to SAS URLs generated by API
- SAS tokens are time-limited (10 minutes default)
- SAS tokens use user delegation (no account keys)

## Performance

### Build Optimization

- **Code splitting**: Vendor chunks separated
- **Tree shaking**: Unused code eliminated
- **Minification**: JavaScript and CSS minified
- **Gzip compression**: Enabled in nginx

### Runtime Optimization

- **Static asset caching**: 1 year cache for hashed assets
- **No cache for HTML**: Always fetch latest index.html
- **Lazy loading**: Components loaded on demand

## License

This project is licensed under the MIT License.

## Support

For issues or questions:
1. Check [TROUBLESHOOTING](#troubleshooting) section
2. Review [API documentation](./../api/README.md)
3. Check browser console for errors
4. Verify API server is running and accessible

## Related Documentation

- **[API README](./../api/README.md)** - Fastify API documentation
- **[API Configuration](./../api/CONFIGURATION.md)** - API setup guide
- **[SAS Tokens Guide](./../api/SAS-TOKENS.md)** - User delegation SAS documentation
- **[Migration Guide](./../api/MIGRATION.md)** - v1 to v2 migration
