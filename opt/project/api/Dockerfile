# Start from a base Ubuntu image
FROM ubuntu:22.04

# Set non-interactive mode for package installations
ENV DEBIAN_FRONTEND=noninteractive

# Update Ubuntu and install Python, pip, and venv
RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-venv

# Set the working directory inside the container
WORKDIR /app

# Copy the requirements file and install dependencies
COPY requirements.txt .
RUN pip3 install -r requirements.txt

# Copy the rest of the application code
COPY . .

# Command to run the application
CMD ["python3", "app.py"]