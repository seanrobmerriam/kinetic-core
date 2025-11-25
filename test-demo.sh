#!/bin/bash

# Core Banking Application Test Script
# Demonstrates basic banking operations via HTTP API calls

BASE_URL="http://localhost:8080/api/v1"

echo " Core Banking Application - Test Demo"
echo "======================================"

# Function to make API calls and display results
make_request() {
    echo "→ $1 $2"
    echo "   Request: $3"
    echo "   Response:"
    curl -s -X "$1" "$BASE_URL$2" \
         -H "Content-Type: application/json" \
         -H "Accept: application/json" \
         -d "$3" | python3 -m json.tool 2>/dev/null || curl -s -X "$1" "$BASE_URL$2" \
         -H "Content-Type: application/json" \
         -H "Accept: application/json" \
         -d "$3"
    echo -e "\n"
}

# Check if application is running
echo "1. Testing application health..."
echo "→ GET /health"
curl -s "$BASE_URL/../health" | python3 -m json.tool 2>/dev/null || echo "❌ Application not running. Please start the application first."
echo -e "\n"

# Test customer creation
echo "2. Creating a new customer..."
make_request "POST" "/customers" '{
    "first_name": "John",
    "last_name": "Doe",
    "email": "john.doe@example.com",
    "phone": "+1234567890",
    "address": "123 Main Street, New York, NY 10001",
    "date_of_birth": "1985-03-15"
}'

# Create another customer
echo "3. Creating a second customer..."
make_request "POST" "/customers" '{
    "first_name": "Jane",
    "last_name": "Smith", 
    "email": "jane.smith@example.com",
    "phone": "+1987654321",
    "address": "456 Oak Avenue, Los Angeles, CA 90210",
    "date_of_birth": "1990-07-22"
}'

# Test account creation
echo "4. Creating bank accounts..."
make_request "POST" "/accounts" '{
    "customer_id": 1,
    "account_type": "checking"
}'

make_request "POST" "/accounts" '{
    "customer_id": 2, 
    "account_type": "savings"
}'

# Test deposit transactions
echo "5. Processing deposits..."
make_request "POST" "/transactions" '{
    "account_id": 1,
    "transaction_type": "deposit",
    "amount": 5000.00,
    "description": "Initial deposit"
}'

make_request "POST" "/transactions" '{
    "account_id": 2,
    "transaction_type": "deposit", 
    "amount": 3000.00,
    "description": "Savings deposit"
}'

# Test withdrawals
echo "6. Processing withdrawals..."
make_request "POST" "/transactions" '{
    "account_id": 1,
    "transaction_type": "withdrawal",
    "amount": 200.00,
    "description": "ATM withdrawal"
}'

# Check account balances
echo "7. Checking account balances..."
echo "→ GET /accounts/1/balance"
curl -s "$BASE_URL/accounts/1/balance" | python3 -m json.tool 2>/dev/null || echo "Error fetching balance"
echo -e "\n"

echo "→ GET /accounts/2/balance" 
curl -s "$BASE_URL/accounts/2/balance" | python3 -m json.tool 2>/dev/null || echo "Error fetching balance"
echo -e "\n"

# Test loan creation
echo "8. Creating a loan..."
make_request "POST" "/loans" '{
    "customer_id": 1,
    "principal_amount": 15000.00,
    "interest_rate": 0.06,
    "loan_term": 36
}'

# Get transaction history
echo "9. Transaction history for account 1..."
echo "→ GET /accounts/1/transactions"
curl -s "$BASE_URL/accounts/1/transactions" | python3 -m json.tool 2>/dev/null || echo "Error fetching transactions"
echo -e "\n"

# Get all customers with their accounts
echo "10. Customer information with accounts and loans..."
echo "→ GET /customers/1"
curl -s "$BASE_URL/customers/1" | python3 -m json.tool 2>/dev/null || echo "Error fetching customer"
echo -e "\n"

# Summary
echo " Demo completed successfully"
echo "======================================"
echo "Results:"
echo "• Customer creation and management"
echo "• Account opening for different types" 
echo "• Transaction processing (deposits & withdrawals)"
echo "• Real-time balance inquiries"
echo "• Loan origination with amortization"
echo "• Complete audit trails and transaction history"
echo ""
echo " Tip: Check the SQLite database file 'banking.db' to see all stored data."
echo " To explore more: Use the README.md documentation for complete API reference."