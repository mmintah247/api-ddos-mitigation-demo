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

## Observability Dashboard
```bash
- URL: https://167.71.118.73:8443/
```

