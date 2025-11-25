# Core Banking Web Application

A concise, production-ready core banking system built in Go, featuring essential banking operations similar to Apache Fineract. This application provides RESTful APIs for customer management, account operations, transaction processing, and loan management.

##� Core Banking Features

- **Customer Management**: Complete customer onboarding and data management
- **Account Operations**: Create and manage checking/savings accounts  
- **Transaction Processing**: Handle deposits, withdrawals, transfers, and payments
- **Loan Management**: Originate and manage loans with automatic payment calculation
- **Security**: JWT-based authentication with role-based access control
- **Audit Trails**: Complete transaction history and balance tracking

## Quick Start

### Prerequisites

- Go 1.21 or higher
- Git (for cloning)

### Installation

## In your terminal of choice:

# Clone the repository (if from git)
```bash
git clone https://github.com/seanrobmerriam/banking-app
cd banking-app

# Install dependencies
go mod download

# Set environment variables
export JWT_SECRET="your-super-secret-jwt-key-here"
export DB_PATH="banking.db"  # Optional, defaults to banking.db
export PORT="8080"           # Optional, defaults to 8080

# Run the application
go run main.go

The application will start on `http://localhost:8080`

### Database

- Uses SQLite by default for simplicity
- Easily configurable for PostgreSQL/MySQL
- Automatic migrations on startup
- Foreign key constraints enabled

##  API Documentation

### Base URL
```
http://localhost:8080/api/v1
```

### Authentication

All protected endpoints require JWT authentication. Include the token in the Authorization header:

```http
Authorization: Bearer <your-jwt-token>
```

### Endpoints Overview

#### Health Check
```http
GET /health
```
Returns application health status.

#### Customer Management

##### Get All Customers
```http
GET /api/v1/customers?page=1&limit=10
```
**Response:**
```json
{
  "customers": [...],
  "total": 50,
  "page": 1,
  "limit": 10
}
```

##### Get Customer by ID
```http
GET /api/v1/customers/:id
```
**Response:**
```json
{
  "id": 1,
  "first_name": "John",
  "last_name": "Doe",
  "email": "john.doe@example.com",
  "phone": "+1234567890",
  "address": "123 Main St, City, State",
  "date_of_birth": "1990-01-01",
  "status": "active",
  "accounts": [...],
  "loans": [...]
}
```

##### Create Customer
```http
POST /api/v1/customers
Content-Type: application/json

{
  "first_name": "John",
  "last_name": "Doe", 
  "email": "john.doe@example.com",
  "phone": "+1234567890",
  "address": "123 Main St, City, State",
  "date_of_birth": "1990-01-01"
}
```

##### Update Customer
```http
PUT /api/v1/customers/:id
Content-Type: application/json

{
  "phone": "+1987654321",
  "address": "456 New St, City, State"
}
```

##### Delete Customer
```http
DELETE /api/v1/customers/:id
```
*Note: Cannot delete customers with active accounts*

#### Account Management

##### Get All Accounts
```http
GET /api/v1/accounts?page=1&limit=10
```
**Response:**
```json
{
  "accounts": [...],
  "total": 25,
  "page": 1,
  "limit": 10
}
```

##### Get Account by ID
```http
GET /api/v1/accounts/:id
```
**Response:**
```json
{
  "id": 1,
  "account_number": "ACC20241124165830123",
  "customer_id": 1,
  "account_type": "checking",
  "balance": 1500.00,
  "currency": "USD",
  "status": "active",
  "customer": {...},
  "transactions": [...]
}
```

##### Create Account
```http
POST /api/v1/accounts
Content-Type: application/json

{
  "customer_id": 1,
  "account_type": "checking",
  "currency": "USD"
}
```
**Response:**
```json
{
  "message": "Account created successfully",
  "account": {
    "id": 1,
    "account_number": "ACC20241124165830123",
    "customer_id": 1,
    "account_type": "checking",
    "balance": 0.00,
    "currency": "USD",
    "status": "active"
  }
}
```

##### Get Account Balance
```http
GET /api/v1/accounts/:id/balance
```
**Response:**
```json
{
  "account_id": 1,
  "account_number": "ACC20241124165830123",
  "balance": 1500.00,
  "currency": "USD",
  "status": "active"
}
```

##### Get Account Transactions
```http
GET /api/v1/accounts/:id/transactions
```
**Response:**
```json
{
  "account_id": 1,
  "transactions": [
    {
      "id": 1,
      "transaction_id": "TXN20241124165830123",
      "account_id": 1,
      "transaction_type": "deposit",
      "amount": 2000.00,
      "description": "Initial deposit",
      "balance_before": 0.00,
      "balance_after": 2000.00,
      "created_at": "2024-11-24T16:58:30Z"
    }
  ]
}
```

#### 💳 Transaction Processing

##### Process Transaction
```http
POST /api/v1/transactions
Content-Type: application/json

{
  "account_id": 1,
  "transaction_type": "deposit",
  "amount": 100.00,
  "description": "ATM deposit"
}
```
**Valid Transaction Types:**
- `deposit` - Add money to account
- `withdrawal` - Remove money from account  
- `transfer` - Transfer between accounts
- `payment` - Make a payment

**Response:**
```json
{
  "message": "Transaction processed successfully",
  "transaction": {
    "id": 1,
    "transaction_id": "TXN20241124165830123",
    "account_id": 1,
    "transaction_type": "deposit",
    "amount": 100.00,
    "description": "ATM deposit",
    "balance_before": 2000.00,
    "balance_after": 2100.00,
    "created_at": "2024-11-24T16:58:30Z"
  }
}
```

##### Get All Transactions
```http
GET /api/v1/transactions?page=1&limit=10&account_id=1&type=deposit
```
**Query Parameters:**
- `page` - Page number (default: 1)
- `limit` - Records per page (default: 10)
- `account_id` - Filter by account ID
- `type` - Filter by transaction type

#### 🏦 Loan Management

##### Create Loan
```http
POST /api/v1/loans
Content-Type: application/json

{
  "customer_id": 1,
  "principal_amount": 10000.00,
  "interest_rate": 0.05,
  "loan_term": 60
}
```
**Response:**
```json
{
  "message": "Loan created successfully",
  "loan": {
    "id": 1,
    "loan_number": "LOAN20241124165830123",
    "customer_id": 1,
    "principal_amount": 10000.00,
    "interest_rate": 0.05,
    "loan_term": 60,
    "status": "active",
    "remaining_balance": 10000.00,
    "monthly_payment": 188.71,
    "disbursement_date": "2024-11-24",
    "due_date": "2029-11-24"
  }
}
```

##### Get All Loans
```http
GET /api/v1/loans?page=1&limit=10
```

##### Get Loan by ID
```http
GET /api/v1/loans/:id
```

##### Update Loan
```http
PUT /api/v1/loans/:id
Content-Type: application/json

{
  "status": "paid_off"
}
```

##### Delete Loan
```http
DELETE /api/v1/loans/:id
```

## 🛠️ Architecture & Design Decisions

### Database Design
- **SQLite for development**: Easy to set up, no external dependencies
- **GORM for ORM**: Automatic migrations, relationship management
- **Soft deletes**: Maintains audit trails for regulatory compliance
- **Foreign key constraints**: Ensures data integrity

### Security Features
- **JWT authentication**: Stateless, scalable authentication
- **Role-based access**: Support for admin/user roles
- **Input validation**: Prevents SQL injection and data corruption
- **Transaction atomicity**: Ensures consistent account balances

### Business Logic
- **Account balance tracking**: Automatic balance updates
- **Transaction validation**: Prevents overdrafts and invalid operations
- **Loan amortization**: Standard payment calculation formula
- **Unique identifiers**: System-generated account/transaction IDs

## 🔧 Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `JWT_SECRET` | - | Secret key for JWT signing (required) |
| `DB_PATH` | `banking.db` | SQLite database file path |
| `PORT` | `8080` | HTTP server port |

### Example Configuration
```bash
export JWT_SECRET="super-secure-random-secret-key"
export DB_PATH="/var/lib/banking/app.db"
export PORT="8080"
```

## Important Notes

### Production Considerations

1. **Database**: Replace SQLite with PostgreSQL/MySQL for production
2. **Security**: 
   - Use HTTPS in production
   - Implement proper password hashing
   - Add rate limiting and request validation
   - Implement proper session management
3. **Monitoring**: Add logging, metrics, and health checks
4. **Backup**: Implement automated database backup procedures
5. **Compliance**: Ensure compliance with banking regulations

### Transaction Safety

- All monetary operations use database transactions
- Account balances are updated atomically
- Insufficient balance checks prevent overdrafts
- Complete audit trails for regulatory compliance

### Error Handling

- Consistent error response format
- Proper HTTP status codes
- Database constraint violation handling
- Validation error reporting

## Testing

### API Testing Examples

```bash
# Health check
curl http://localhost:8080/health

# Create a customer
curl -X POST http://localhost:8080/api/v1/customers \
  -H "Content-Type: application/json" \
  -d '{"first_name":"John","last_name":"Doe","email":"john@example.com"}'

# Create an account
curl -X POST http://localhost:8080/api/v1/accounts \
  -H "Content-Type: application/json" \
  -d '{"customer_id":1,"account_type":"checking"}'

# Process a deposit
curl -X POST http://localhost:8080/api/v1/transactions \
  -H "Content-Type: application/json" \
  -d '{"account_id":1,"transaction_type":"deposit","amount":100.00,"description":"Test deposit"}'

# Check account balance
curl http://localhost:8080/api/v1/accounts/1/balance
```

## Project Structure

```
banking-app/
├── main.go              # Application entry point
├── go.mod              # Go module definition
├── models/
│   └── models.go       # Data models (Customer, Account, Transaction, Loan)
├── database/
│   └── database.go     # Database initialization and migrations
├── handlers/
│   └── handlers.go     # HTTP request handlers
├── middleware/
│   └── auth.go         # Authentication middleware
└── README.md           # This documentation
```

## Key Features Implemented

 **Customer Management** - Complete CRUD operations  
**Account Operations** - Create, manage, and query accounts  
**Transaction Processing** - Deposits, withdrawals, transfers  
**Loan Management** - Loan origination with amortization  
**Authentication** - JWT-based security  
**Data Integrity** - Database transactions and constraints  
**Audit Trails** - Complete transaction history  
**RESTful APIs** - Standard HTTP operations  
**Error Handling** - Comprehensive error management  
**Documentation** - Complete API documentation  

##  To Do

- **Account Types**: Savings, checking, money market, CDs
- **Interest Calculation**: Daily balance interest computation  
- **Statement Generation**: Monthly/quarterly statements
- **Wire Transfers**: International transfer capabilities
- **Investment Products**: Basic investment account support
- **Mobile Banking**: Mobile app API endpoints
- **Notification System**: SMS/Email alerts
- **Enhanced Reporting**: Financial reporting APIs
- **Multi-currency**: Support for multiple currencies
- **API Rate Limiting**: Request throttling and abuse prevention

---

**Built in Go for robust, scalable core banking operations**
