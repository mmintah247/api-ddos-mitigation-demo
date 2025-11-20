document.getElementById('checkBalanceBtn').addEventListener('click', () => {
    const accountNumber = document.getElementById('accountNumber').value;
    const resultDiv = document.getElementById('result');
    resultDiv.textContent = 'Loading...';

    fetch(`http://206.189.121.14:5001/balance/${accountNumber}`)
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
