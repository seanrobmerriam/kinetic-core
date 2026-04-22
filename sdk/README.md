# IronLedger Client SDKs

Client SDKs generated from the IronLedger OpenAPI specification.

## Available SDKs

| Language | Directory | Package |
|----------|-----------|---------|
| Java | `java/` | `ironledger` |
| Python | `python/` | `ironledger` |
| Node.js (TypeScript) | `nodejs/` | `ironledger` |
| .NET | `dotnet/` | `ironledger` |

## Generating SDKs

From the repository root, with the server running:

```bash
./scripts/generate-sdks.sh [server_url]
```

Default server URL: `http://localhost:8080`

### Prerequisites

- Node.js and npm
- A running IronLedger server

The script uses `npx @openapitools/openapi-generator-cli` (auto-downloaded).

## Usage Examples

### Python

```python
import ironledger
from ironledger.api import AccountsApi

client = ironledger.ApiClient(configuration=ironledger.Configuration(
    host="http://localhost:8080/api/v1",
    access_token="your-session-token"
))
api = AccountsApi(client)
accounts = api.list_accounts()
```

### TypeScript (Node.js)

```typescript
import { AccountsApi, Configuration } from 'ironledger';

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
