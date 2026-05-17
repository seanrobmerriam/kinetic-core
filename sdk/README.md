# Kinetic Core Client SDKs

Client SDKs generated from the Kinetic Core OpenAPI specification.

## Available SDKs

| Language | Directory | Package |
|----------|-----------|---------|
| Java | `java/` | `kinetic_core` |
| Python | `python/` | `kinetic_core` |
| Node.js (TypeScript) | `nodejs/` | `kinetic_core` |
| .NET | `dotnet/` | `kinetic_core` |

## Generating SDKs

From the repository root, with the server running:

```bash
./scripts/generate-sdks.sh [server_url]
```

Default server URL: `http://localhost:8080`

### Prerequisites

- Node.js and npm
- A running Kinetic Core server

The script uses `npx @openapitools/openapi-generator-cli` (auto-downloaded).

## Usage Examples

### Python

```python
import kinetic_core
from kinetic_core.api import AccountsApi

client = kinetic_core.ApiClient(configuration=kinetic_core.Configuration(
    host="http://localhost:8080/api/v1",
    access_token="your-session-token"
))
api = AccountsApi(client)
accounts = api.list_accounts()
```

### TypeScript (Node.js)

```typescript
import { AccountsApi, Configuration } from 'kinetic_core';

const api = new AccountsApi(new Configuration({
  basePath: 'http://localhost:8080/api/v1',
  accessToken: 'your-session-token',
}));

const accounts = await api.listAccounts();
```

## Notes

- SDKs are generated artifacts — do not edit them manually.
- Re-run `generate-sdks.sh` after API changes.
- The `openapi.json` snapshot in this directory reflects the spec at generation time.
