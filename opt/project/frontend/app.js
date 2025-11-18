document.getElementById('checkBalanceBtn').addEventListener('click', () => {
    const accountNumber = document.getElementById('accountNumber').value;
    const resultDiv = document.getElementById('result');
    resultDiv.textContent = 'Loading...';

    // *** Make sure this points to port 5001 ***
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