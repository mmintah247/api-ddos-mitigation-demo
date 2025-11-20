document.getElementById('checkBalanceBtn').addEventListener('click', () => {
    const accountNumber = document.getElementById('accountNumber').value.trim();
    const resultDiv = document.getElementById('result');
    const errorMessage = document.getElementById('errorMessage');
    const accountInput = document.getElementById('accountNumber');
    
    // Clear previous error
    errorMessage.style.display = 'none';
    accountInput.style.borderColor = '';
    
    // Validate account number is not empty
    if (!accountNumber) {
        errorMessage.textContent = 'Please enter an account number';
        errorMessage.style.display = 'block';
        accountInput.style.borderColor = 'var(--danger)';
        resultDiv.textContent = 'No account queried yet.';
        resultDiv.className = 'result-empty';
        return;
    }
    
    resultDiv.textContent = 'Loading...';
    resultDiv.className = '';

    fetch(`http://165.232.42.130:5001/balance/${accountNumber}`)
        .then(response => {
            if (!response.ok) {
                throw new Error('Account not found');
            }
            return response.json();
        })
        .then(data => {
            if (data.error) {
                resultDiv.textContent = data.error;
            } else {
                resultDiv.textContent = `Name: ${data.full_name}, Balance: ${data.formatted_balance}`;
            }
        })
        .catch(error => {
            resultDiv.textContent = `Error: ${error.message}`;
        });
});

// Clear error on input
document.getElementById('accountNumber').addEventListener('input', function() {
    document.getElementById('errorMessage').style.display = 'none';
    this.style.borderColor = '';
});
