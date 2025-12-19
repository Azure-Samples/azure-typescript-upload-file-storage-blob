import { BlockBlobClient } from '@azure/storage-blob';
import { Box, Button, Card, CardMedia, Grid, Typography } from '@mui/material';
import { ChangeEvent, useState } from 'react';
import ErrorBoundary from './components/error-boundary';
import { convertFileToArrayBuffer } from './lib/convert-file-to-arraybuffer';

import './App.css';

// API URL from environment variable (supports both local and production)
const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:3000';

console.log('VITE_API_URL:', import.meta.env.VITE_API_URL);
console.log('API_URL:', API_URL);

type SasResponse = {
  url: string;
};
type ListResponse = {
  list: string[];
};

function App() {
  const containerName = `upload`;
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [sasTokenUrl, setSasTokenUrl] = useState<string>('');
  const [uploadStatus, setUploadStatus] = useState<string>('');
  const [list, setList] = useState<string[]>([]);

  const handleFileSelection = (event: ChangeEvent<HTMLInputElement>) => {
    const { target } = event;

    if (!(target instanceof HTMLInputElement)) return;
    if (
      target?.files === null ||
      target?.files?.length === 0 ||
      target?.files[0] === null
    )
      return;

    setSelectedFile(target?.files[0]);

    // reset
    setSasTokenUrl('');
    setUploadStatus('');
  };

  const handleFileSasToken = () => {
    const permission = 'w'; //write
    const timerange = 10; //minutes (default for v2)

    if (!selectedFile) return;

    // Fastify API uses GET for SAS token generation
    const url = `${API_URL}/api/sas?file=${encodeURIComponent(
      selectedFile.name
    )}&permission=${permission}&container=${containerName}&timerange=${timerange}`;

    console.log('GET SAS URL:', url);

    fetch(url, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json'
      }
    })
      .then((response) => {
        console.log('SAS token fetch response:', response);
        console.log('Response status:', response.status);
        console.log('Response ok:', response.ok);
        
        if (!response.ok) {
          throw new Error(`Error: ${response.status} ${response.statusText} - URL: ${url}`);
        }
        return response.json();
      })
      .then((data: SasResponse) => {
        console.log('SAS token response data:', data);
        const { url } = data;
        console.log('SAS token URL received:', url);
        setSasTokenUrl(url);
      })
      .catch((error: unknown) => {
        console.error('SAS token fetch error:', error);
        if (error instanceof Error) {
          const { message, stack } = error;
          console.error('Error message:', message);
          console.error('Error stack:', stack);
          setSasTokenUrl(`Error getting sas token: ${message} ${stack || ''}`);
        } else {
          console.error('Unknown error type:', error);
          setUploadStatus(String(error));
        }
      });
  };

  const handleFileUpload = () => {
    if (sasTokenUrl === '') {
      console.log('Upload aborted: No SAS token URL');
      return;
    }

    console.log('Starting upload process...');
    console.log('Selected file:', selectedFile?.name, 'Size:', selectedFile?.size);
    console.log('SAS Token URL:', sasTokenUrl);

    convertFileToArrayBuffer(selectedFile as File)
      .then((fileArrayBuffer) => {
        console.log('File converted to ArrayBuffer, size:', fileArrayBuffer?.byteLength);
        
        if (fileArrayBuffer === null || fileArrayBuffer.byteLength < 1) {
          throw new Error('Failed to convert file to ArrayBuffer');
        }

        // Removed arbitrary 256KB limit - Azure Blob Storage supports much larger files
        console.log('Creating BlockBlobClient...');
        const blockBlobClient = new BlockBlobClient(sasTokenUrl);
        console.log('Uploading data to Azure Storage...');
        return blockBlobClient.uploadData(fileArrayBuffer);
      })
      .then((uploadResponse) => {
        console.log('Upload response:', uploadResponse);
        if (!uploadResponse) {
          throw new Error('Upload failed - no response from Azure Storage');
        }
        setUploadStatus('Successfully finished upload');
        
        const listUrl = `${API_URL}/api/list?container=${containerName}`;
        console.log('Fetching blob list from:', listUrl);
        return fetch(listUrl);
      })
      .then((response) => {
        console.log('List response status:', response?.status);
        if (!response) {
          console.error('No response from list API');
          return;
        }
        if (!response.ok) {
          throw new Error(`Error: ${response.status} ${response.statusText} - URL: ${response.url}`);
        }
        return response.json();
      })
      .then((data: ListResponse) => {
        console.log('Blob list received:', data);
        setList(data.list);
      })
      .catch((error: unknown) => {
        console.error('Upload error:', error);
        if (error instanceof Error) {
          const { message, stack } = error;
          setUploadStatus(
            `Failed to finish upload with error : ${message} ${stack || ''}`
          );
        } else {
          setUploadStatus(error as string);
        }
      });
  };

  return (
    <>
      <ErrorBoundary>
        <Box m={4}>
          {/* App Title */}
          <Typography variant="h4" gutterBottom>
            Upload file to Azure Storage
          </Typography>
          <Typography variant="h5" gutterBottom>
            with SAS token
          </Typography>
          <Typography variant="body1" gutterBottom>
            <b>Container: {containerName}</b>
          </Typography>

          {/* File Selection Section */}
          <Box
            display="block"
            justifyContent="left"
            alignItems="left"
            flexDirection="column"
            my={4}
          >
            <Button variant="contained" component="label">
              Select File
              <input type="file" hidden onChange={handleFileSelection} />
            </Button>
            {selectedFile && selectedFile.name && (
              <Box my={2}>
                <Typography variant="body2">{selectedFile.name}</Typography>
              </Box>
            )}
          </Box>

          {/* SAS Token Section */}
          {selectedFile && selectedFile.name && (
            <Box
              display="block"
              justifyContent="left"
              alignItems="left"
              flexDirection="column"
              my={4}
            >
              <Button variant="contained" onClick={handleFileSasToken}>
                Get SAS Token
              </Button>
              {sasTokenUrl && (
                <Box my={2}>
                  <Typography variant="body2">{sasTokenUrl}</Typography>
                </Box>
              )}
            </Box>
          )}

          {/* File Upload Section */}
          {sasTokenUrl && (
            <Box
              display="block"
              justifyContent="left"
              alignItems="left"
              flexDirection="column"
              my={4}
            >
              <Button variant="contained" onClick={handleFileUpload}>
                Upload
              </Button>
              {uploadStatus && (
                <Box my={2}>
                  <Typography variant="body2" gutterBottom>
                    {uploadStatus}
                  </Typography>
                </Box>
              )}
            </Box>
          )}

          {/* Uploaded Files Display */}
          <Grid container spacing={2}>
            {list.map((item) => {
              // Extract filename from URL (before query parameters)
              const urlWithoutQuery = item.split('?')[0];
              const filename = urlWithoutQuery.split('/').pop() || '';
              const isImage = filename.endsWith('.jpg') ||
                              filename.endsWith('.png') ||
                              filename.endsWith('.jpeg') ||
                              filename.endsWith('.gif');
              
              return (
                <Grid item xs={6} sm={4} md={3} key={item}>
                  <Card>
                    {isImage ? (
                      <CardMedia component="img" image={item} alt={filename} />
                    ) : (
                      <Typography variant="body1" gutterBottom>
                        {filename}
                      </Typography>
                    )}
                  </Card>
                </Grid>
              );
            })}
          </Grid>
        </Box>
      </ErrorBoundary>
    </>
  );
}

export default App;
