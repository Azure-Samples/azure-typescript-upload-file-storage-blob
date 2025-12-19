# Frontend Storage Workflow

This document explains how the React frontend requests SAS tokens from the API and uses them to directly upload files to Azure Storage from the browser.

## Overview

The frontend follows a three-step process:

1. **Request a SAS token** from the API for a specific file
2. **Upload directly to Azure Storage** using the SAS token URL
3. **Fetch and display** the list of uploaded files with read-only SAS tokens

This architecture keeps the backend lightweight - it only generates tokens, never handles file data.

## Step 1: Request a SAS Token

When a user selects a file and clicks "Get SAS Token", the frontend requests a write-only SAS token from the API:

```typescript
// From: packages/app/src/App.tsx
const handleFileSasToken = () => {
  const permission = 'w'; // write-only
  const timerange = 10;   // 10 minutes expiration

  if (!selectedFile) return;

  // Build API request URL
  const url = `${API_URL}/api/sas?file=${encodeURIComponent(
    selectedFile.name
  )}&permission=${permission}&container=${containerName}&timerange=${timerange}`;

  fetch(url, {
    method: 'GET',
    headers: {
      'Content-Type': 'application/json'
    }
  })
    .then((response) => {
      if (!response.ok) {
        throw new Error(`Error: ${response.status} ${response.statusText}`);
      }
      return response.json();
    })
    .then((data: SasResponse) => {
      const { url } = data;
      setSasTokenUrl(url); // Store the SAS URL for upload
    });
};
```

**What happens:**
- Frontend sends: `GET /api/sas?file=photo.jpg&permission=w&container=upload&timerange=10`
- API returns: `{ url: "https://storageaccount.blob.core.windows.net/upload/photo.jpg?sv=2024-05-04&..." }`
- This URL is valid for 10 minutes and grants **write-only** access to that specific blob

## Step 2: Upload Directly to Azure Storage

Once the SAS token URL is received, the frontend uploads the file **directly to Azure Storage** - bypassing the API entirely:

```typescript
// From: packages/app/src/App.tsx
const handleFileUpload = () => {
  console.log('SAS Token URL:', sasTokenUrl);

  // Convert file to ArrayBuffer
  convertFileToArrayBuffer(selectedFile as File)
    .then((fileArrayBuffer) => {
      if (fileArrayBuffer === null || fileArrayBuffer.byteLength < 1) {
        throw new Error('Failed to convert file to ArrayBuffer');
      }

      // Create Azure Storage client with SAS URL
      const blockBlobClient = new BlockBlobClient(sasTokenUrl);
      
      // Upload directly to Azure Storage
      return blockBlobClient.uploadData(fileArrayBuffer);
    })
    .then((uploadResponse) => {
      if (!uploadResponse) {
        throw new Error('Upload failed - no response from Azure Storage');
      }
      setUploadStatus('Successfully finished upload');
      
      // After upload, fetch the updated list of files
      const listUrl = `${API_URL}/api/list?container=${containerName}`;
      return fetch(listUrl);
    });
};
```

### File Conversion

Before uploading, the file is converted to an `ArrayBuffer` that the Azure Storage SDK can process:

```typescript
// From: packages/app/src/lib/convert-file-to-arraybuffer.ts
export function convertFileToArrayBuffer(file: File): Promise<ArrayBuffer | null> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();

    reader.onload = () => {
      const arrayBuffer = reader.result;
      resolve(arrayBuffer as ArrayBuffer);
    };

    reader.onerror = () => {
      reject(new Error('Error reading file.'));
    };

    reader.readAsArrayBuffer(file);
  });
}
```

**Key points:**
- The file **never passes through your API server**
- Upload goes directly from browser to Azure Storage
- The SAS token authenticates the request
- No server bandwidth or processing costs for file handling

## Step 3: Fetch and Display Uploaded Files

After a successful upload, the frontend fetches a list of all files in the container. Each file in the list comes with its own **read-only SAS token**:

```typescript
// From: packages/app/src/App.tsx
const listUrl = `${API_URL}/api/list?container=${containerName}`;

fetch(listUrl)
  .then((response) => {
    if (!response.ok) {
      throw new Error(`Error: ${response.status}`);
    }
    return response.json();
  })
  .then((data: ListResponse) => {
    setList(data.list); // Array of SAS URLs with read permission
  });
```

**Response example:**
```json
{
  "list": [
    "https://storageaccount.blob.core.windows.net/upload/photo1.jpg?sv=2024-05-04&se=2025-12-18T15:30:00Z&sr=b&sp=r&...",
    "https://storageaccount.blob.core.windows.net/upload/photo2.jpg?sv=2024-05-04&se=2025-12-18T15:30:00Z&sr=b&sp=r&..."
  ]
}
```

### Displaying Images

The frontend uses the SAS URLs directly in image tags. The browser fetches images from Azure Storage using the embedded read-only tokens:

```typescript
// From: packages/app/src/App.tsx
<Grid container spacing={2}>
  {list.map((item) => {
    const urlWithoutQuery = item.split('?')[0];
    const filename = urlWithoutQuery.split('/').pop() || '';
    const isImage = filename.endsWith('.jpg') || 
                    filename.endsWith('.png') || 
                    filename.endsWith('.jpeg');
    
    return (
      <Grid item xs={6} sm={4} md={3} key={item}>
        <Card>
          {isImage ? (
            <CardMedia component="img" image={item} alt={filename} />
          ) : (
            <Typography>{filename}</Typography>
          )}
        </Card>
      </Grid>
    );
  })}
</Grid>
```

**How it works:**
- Each URL in the list includes a read-only SAS token (`sp=r`)
- Browser makes GET requests directly to Azure Storage
- No authentication required - the token is in the URL
- Tokens expire after 60 minutes (configured in the API)

## Complete Flow Diagram

```
User selects file
    ↓
Frontend → GET /api/sas?file=photo.jpg&permission=w
    ↓
API generates write token (10 min expiration)
    ↓
API ← { url: "https://storage.../photo.jpg?[SAS-TOKEN]" }
    ↓
Frontend → BlockBlobClient.uploadData(file) → Azure Storage (direct)
    ↓
Azure Storage validates SAS token and stores file
    ↓
Frontend → GET /api/list?container=upload
    ↓
API generates read tokens for all blobs (60 min expiration)
    ↓
API ← { list: ["https://storage.../photo1.jpg?[READ-TOKEN]", ...] }
    ↓
Frontend displays images using SAS URLs (browser fetches directly from storage)
```

## Security Benefits

This architecture provides several security advantages:

| Aspect | Implementation | Benefit |
|--------|---------------|---------|
| **Token scoping** | Separate tokens for upload (`w`) vs. view (`r`) | Upload tokens cannot read data; view tokens cannot modify |
| **Time-limited** | 10 min for upload, 60 min for viewing | Tokens automatically expire, limiting exposure window |
| **Direct upload** | Browser → Azure Storage (no API) | API never handles sensitive file data |
| **No credentials in frontend** | Only temporary SAS tokens | No storage keys or long-lived credentials in browser |

## Environment Configuration

The frontend API URL is configured via environment variable:

```typescript
// From: packages/app/src/App.tsx
const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:3000';
```

**Development:** Uses `http://localhost:3000` (local API server)  
**Production:** Uses injected `VITE_API_URL` from Azure Container Apps

## Summary

1. **Request token** - Frontend asks API for a write-only SAS token for specific file
2. **Direct upload** - Browser uploads file directly to Azure Storage using SAS URL
3. **Fetch list** - Frontend requests list of files, each with read-only SAS token
4. **Display** - Browser loads images directly from Azure Storage using SAS URLs

The API only generates tokens - all file transfers happen directly between the browser and Azure Storage.
