# For Vulnerable server



### Payload Test to simulate DDOS attack
```bash
wrk -t10 -c50000 -d30s --latency http://165.232.42.130:5001/balance/
```

### stop and start services Services
```bash
docker compose -f docker-compose.vulnerable.yml down
docker compose -f docker-compose.vulnerable.yml up -d --build --force-recreate
```



### webpage for banking app
```bash
http://165.232.42.130:8081/
```

### phpmyadmin dashboard
```bash
http://165.232.42.130:8080/
```

### api test from web browser
```bash
http://165.232.42.130:5001/balance/1005880649042
```

### check api logs
```bash
docker logs -f --tail 10 api
```




# For observability

## Stop and start containers if there need be
```bash
docker compose -f docker-compose.lpar2rrdserver.yml down
docker compose -f docker-compose.lpar2rrdserver.yml up -d --build --force-recreate
```

## observability
```bash
https://167.71.118.73:8443/
```



# API DDoS Mitigation Demo

## Load Testing

### Payload Test to simulate DDOS attack
```bash
wrk -t2 -c2000 -d120s --latency http://206.189.121.14:5001/balance/
```

### web app UI
```bash
http://206.189.121.14:8081/
```

### Balance Endpoint
```bash
http://206.189.121.14:5001/balance/1056824615097
```

## Docker Compose Operations

### Restart Services
```bash
docker compose -f docker-compose.mitigated.yml down
docker compose -f docker-compose.mitigated.yml up -d --build --force-recreate
```

## Monitoring

### Check API Logs
```bash
docker logs -f --tail 10 api
```

### Check Docker Stats
```bash
docker stats api
```

## Observability
[Dashboard](https://167.71.118.73:8443/)

## Cloud Mitigated







